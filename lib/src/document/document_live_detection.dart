import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'document_boundary_detection.dart';

/// Pixel layout of a live preview plane.
enum LivePlaneFormat {
  /// One luminance byte per pixel — the Y plane of NV21 / YUV420, which is
  /// all boundary detection needs.
  luma8,

  /// Four bytes per pixel in B, G, R, A order, as iOS delivers preview
  /// frames.
  bgra8888,
}

/// One live preview plane plus how to read and orient it.
///
/// A plain value class of primitives and a byte buffer, so it can cross the
/// isolate boundary without a custom codec.
class LivePlane {
  const LivePlane({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.format,
    required this.rotationDegrees,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Row stride in bytes, which may exceed `width * bytesPerPixel` when the
  /// platform pads rows.
  final int bytesPerRow;

  final LivePlaneFormat format;

  /// Clockwise rotation (0, 90, 180 or 270) that turns the sensor-oriented
  /// plane upright, with the same meaning as ML Kit's `InputImageRotation`.
  final int rotationDegrees;
}

/// Detects the document boundary in one live preview plane, on a background
/// isolate.
///
/// The returned quad is normalized against the *upright* frame — the same
/// orientation the camera preview is shown in — so it can be drawn straight
/// over the preview.
Future<DocumentBoundaryDetection?> detectDocumentInLivePlane(
  LivePlane plane, {
  int maxAnalysisDimension = 320,
}) =>
    compute(_detectWorker, (plane: plane, maxDimension: maxAnalysisDimension));

DocumentBoundaryDetection? _detectWorker(
  ({LivePlane plane, int maxDimension}) request,
) {
  final gray = lumaImageFromPlane(
    request.plane,
    maxDimension: request.maxDimension,
  );
  if (gray == null) return null;
  return detectDocumentBoundary(
    gray,
    maxAnalysisDimension: request.maxDimension,
  );
}

/// Builds a small, upright, single-channel luminance image from [plane].
///
/// Downsamples by averaging each `step x step` block rather than picking one
/// pixel from it: sensor noise at full resolution would otherwise alias into
/// spurious edges that the Sobel pass in [detectDocumentBoundary] then has to
/// fight.
///
/// Returns `null` when [plane]'s buffer is too short for its declared
/// geometry, rather than reading past its end.
img.Image? lumaImageFromPlane(LivePlane plane, {required int maxDimension}) {
  final bytesPerPixel = plane.format == LivePlaneFormat.luma8 ? 1 : 4;
  if (plane.width <= 0 || plane.height <= 0) return null;
  final required =
      (plane.height - 1) * plane.bytesPerRow + plane.width * bytesPerPixel;
  if (plane.bytes.length < required) return null;

  final step = math.max(
    1,
    (math.max(plane.width, plane.height) / maxDimension).ceil(),
  );
  final outWidth = plane.width ~/ step;
  final outHeight = plane.height ~/ step;
  if (outWidth == 0 || outHeight == 0) return null;

  final out = img.Image(width: outWidth, height: outHeight, numChannels: 1);
  final bytes = plane.bytes;
  final blockArea = step * step;

  for (var oy = 0; oy < outHeight; oy++) {
    for (var ox = 0; ox < outWidth; ox++) {
      var sum = 0;
      for (var dy = 0; dy < step; dy++) {
        final rowStart = (oy * step + dy) * plane.bytesPerRow;
        for (var dx = 0; dx < step; dx++) {
          final i = rowStart + (ox * step + dx) * bytesPerPixel;
          if (bytesPerPixel == 1) {
            sum += bytes[i];
          } else {
            // Rec. 601 luma, integer-weighted: B, G, R byte order.
            sum +=
                (29 * bytes[i] + 150 * bytes[i + 1] + 77 * bytes[i + 2]) >> 8;
          }
        }
      }
      out.setPixelR(ox, oy, sum ~/ blockArea);
    }
  }

  final rotation = plane.rotationDegrees % 360;
  return rotation == 0 ? out : img.copyRotate(out, angle: rotation);
}
