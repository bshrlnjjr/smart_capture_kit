import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../common/geometry.dart';
import 'hull_geometry.dart';
import 'perspective_transform.dart' show Pt;

/// A detected document boundary plus how much the detector trusts it.
class DocumentBoundaryDetection {
  const DocumentBoundaryDetection({
    required this.quad,
    required this.confidence,
    required this.imageAspectRatio,
  });

  /// Normalized (0..1) corners, resolution-independent regardless of the
  /// analysis size this ran at.
  final Quad quad;

  /// Width / height of the image [quad] is normalized against — needed to
  /// turn [quad] back into a pixel-space shape (see
  /// [Quad.estimatedAspectRatio]).
  final double imageAspectRatio;

  /// The detected card's width / height in pixels.
  double? get estimatedAspectRatio =>
      quad.estimatedAspectRatio(imageAspectRatio: imageAspectRatio);

  /// Rough confidence in `[0, 1]`. Not a calibrated probability — a
  /// comparison score combining how plausible the enclosed area and shape
  /// are, tuned against [DocumentQualityThresholds]' defaults the same way
  /// `ImageMetrics` is.
  final double confidence;
}

/// Finds the document boundary in [image] and returns it as a normalized
/// [Quad], or `null` when no boundary could be found with reasonable
/// confidence.
///
/// ## How this works, and its real limitations
///
/// This is a classical edge-based heuristic, not a learned model: downscale
/// for speed, take a Sobel gradient-magnitude edge map, threshold and dilate
/// it to close small gaps in the document's outline, then flood-fill inward
/// from the image border. Any pixel the flood fill cannot reach — because the
/// (dilated) edge map walled it off — is treated as the document's interior.
/// The interior's convex hull is reduced to 4 corners via
/// [reduceHullToQuad].
///
/// This works well for the case this package guides the user toward: a card
/// held close to fronto-parallel, roughly centered, against a background with
/// a real luminance/texture discontinuity at the card's edge. It degrades on:
///
/// - a background as low-contrast as the card itself (no edge to find),
/// - a card touching the image border (no background ring to flood-fill
///   from on that side — see [Quad.isFullyInsideImage] for why that case
///   should fail a check anyway, not silently rectify a clipped card),
/// - heavy clutter that closes off a competing, wrong "interior" first.
///
/// None of these fail unsafely: they return `null` here, which every caller
/// treats as "no confident detection" — never a guessed quad. See
/// `doc/decisions/0002-document-boundary-detection.md` for the fuller
/// tradeoff discussion and what would justify moving to a native/OpenCV
/// implementation instead.
DocumentBoundaryDetection? detectDocumentBoundary(
  img.Image image, {
  int maxAnalysisDimension = 480,
}) {
  final analysis = _downscale(image, maxAnalysisDimension);
  final gray = img.grayscale(analysis);
  final width = gray.width;
  final height = gray.height;
  if (width < 20 || height < 20) return null;

  final magnitude = _sobelMagnitude(gray);
  final edgeMask = _threshold(magnitude, width, height);
  final dilated = _dilate(edgeMask, width, height);
  final interior = _floodFillInteriorMask(dilated, width, height);
  if (interior == null) return null;

  final boundaryPoints = _extractBoundaryPoints(interior, width, height);
  if (boundaryPoints.length < 4) return null;

  final hull = convexHull(boundaryPoints);
  final quad = reduceHullToQuad(
    hull,
    imageWidth: width.toDouble(),
    imageHeight: height.toDouble(),
  );
  if (quad == null) return null;

  final areaFraction = quad.areaFraction;
  if (areaFraction < 0.05 || areaFraction > 0.98) return null;

  // A confidence score, not a calibrated probability: area comfortably inside
  // a plausible range and a shape close to a real rectangle both raise it;
  // either one being marginal pulls it down rather than failing outright,
  // leaving the pass/warn/fail judgement to the caller's thresholds.
  final areaScore = 1.0 - (2 * (areaFraction - 0.5)).abs().clamp(0.0, 1.0);
  final shapeScore = 1.0 - quad.perspectiveDistortion.clamp(0.0, 1.0);
  final confidence = (0.5 * areaScore + 0.5 * shapeScore).clamp(0.0, 1.0);

  return DocumentBoundaryDetection(
    quad: quad,
    confidence: confidence,
    imageAspectRatio: width / height,
  );
}

img.Image _downscale(img.Image image, int maxDimension) {
  final longest = math.max(image.width, image.height);
  if (longest <= maxDimension) return image;
  final scale = maxDimension / longest;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

/// Sobel gradient magnitude, flattened row-major.
List<double> _sobelMagnitude(img.Image gray) {
  final width = gray.width;
  final height = gray.height;
  final out = List<double>.filled(width * height, 0);

  double luma(int x, int y) => gray.getPixel(x, y).r.toDouble();

  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final gx = -luma(x - 1, y - 1) +
          luma(x + 1, y - 1) -
          2 * luma(x - 1, y) +
          2 * luma(x + 1, y) -
          luma(x - 1, y + 1) +
          luma(x + 1, y + 1);
      final gy = -luma(x - 1, y - 1) -
          2 * luma(x, y - 1) -
          luma(x + 1, y - 1) +
          luma(x - 1, y + 1) +
          2 * luma(x, y + 1) +
          luma(x + 1, y + 1);
      out[y * width + x] = math.sqrt(gx * gx + gy * gy);
    }
  }
  return out;
}

/// Binarizes the magnitude map at a fraction of its own maximum.
///
/// A relative threshold rather than a fixed one, so the detector is not
/// tuned to one exposure level — a dim and a bright photo of the same scene
/// produce comparable edge masks.
List<bool> _threshold(List<double> magnitude, int width, int height) {
  var maxVal = 0.0;
  for (final v in magnitude) {
    if (v > maxVal) maxVal = v;
  }
  if (maxVal <= 0) return List.filled(width * height, false);
  final cutoff = maxVal * 0.20;
  return [for (final v in magnitude) v >= cutoff];
}

/// One round of binary dilation, closing single-pixel gaps in the outline
/// that would otherwise leak the flood fill through the document's border.
List<bool> _dilate(List<bool> mask, int width, int height) {
  final out = List<bool>.from(mask);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (mask[y * width + x]) continue;
      outer:
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          if (mask[ny * width + nx]) {
            out[y * width + x] = true;
            break outer;
          }
        }
      }
    }
  }
  return out;
}

/// Flood-fills from every border pixel across non-edge cells, iteratively
/// (an explicit stack, not recursion — this runs on downscaled images but
/// still touches tens of thousands of cells, well beyond a safe recursion
/// depth). Returns a mask of the unreached ("interior") cells, or `null` when
/// the fill reached the whole image, meaning no closed boundary was found.
List<bool>? _floodFillInteriorMask(List<bool> edgeMask, int width, int height) {
  final visited = List<bool>.filled(width * height, false);
  final stack = <int>[];

  void seed(int x, int y) {
    final i = y * width + x;
    if (!edgeMask[i] && !visited[i]) {
      visited[i] = true;
      stack.add(i);
    }
  }

  for (var x = 0; x < width; x++) {
    seed(x, 0);
    seed(x, height - 1);
  }
  for (var y = 0; y < height; y++) {
    seed(0, y);
    seed(width - 1, y);
  }

  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % width;
    final y = i ~/ width;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx;
      final ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      final ni = ny * width + nx;
      if (!edgeMask[ni] && !visited[ni]) {
        visited[ni] = true;
        stack.add(ni);
      }
    }
  }

  var interiorCount = 0;
  final interior = List<bool>.filled(width * height, false);
  for (var i = 0; i < visited.length; i++) {
    if (!visited[i]) {
      interior[i] = true;
      interiorCount++;
    }
  }
  return interiorCount == 0 ? null : interior;
}

/// Points on the outer edge of the interior mask — enough to define its
/// shape for a convex hull without feeding every interior pixel into it.
List<Pt> _extractBoundaryPoints(List<bool> interior, int width, int height) {
  final points = <Pt>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!interior[y * width + x]) continue;
      final onBoundary = x == 0 ||
          y == 0 ||
          x == width - 1 ||
          y == height - 1 ||
          !interior[y * width + (x - 1)] ||
          !interior[y * width + (x + 1)] ||
          !interior[(y - 1) * width + x] ||
          !interior[(y + 1) * width + x];
      if (onBoundary) {
        points.add((x.toDouble(), y.toDouble()));
      }
    }
  }
  return points;
}
