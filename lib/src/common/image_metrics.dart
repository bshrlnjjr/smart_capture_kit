import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Brightness and sharpness measurements for a decoded image.
///
/// Both scores are normalized to roughly `[0, 1]` but neither is a calibrated
/// physical unit — they are comparison scores tuned against the default
/// thresholds in [PortraitQualityThresholds] and [DocumentQualityThresholds].
/// A host with stricter needs should treat the thresholds, not these
/// formulas, as the tuning knob.
class ImageMetrics {
  const ImageMetrics({required this.meanBrightness, required this.sharpness});

  /// Mean normalized luminance across the sampled pixels, in `[0, 1]`.
  final double meanBrightness;

  /// Normalized Laplacian-variance sharpness score, in `[0, 1]` for anything
  /// that will look sharp to a person; blur pushes it toward `0`.
  final double sharpness;

  @override
  String toString() =>
      'ImageMetrics(brightness=${meanBrightness.toStringAsFixed(3)}, '
      'sharpness=${sharpness.toStringAsFixed(3)})';
}

/// Computes [ImageMetrics] for [image].
///
/// Designed to run inside `compute()` so a full-resolution capture never
/// blocks the UI isolate. Downscales internally before doing any per-pixel
/// work, so cost is roughly constant regardless of the source resolution.
ImageMetrics computeImageMetrics(img.Image image) {
  // A few hundred pixels on the long edge is plenty for both a brightness
  // average and a Laplacian estimate; anything higher only adds cost.
  final analysisImage = _downscaleForAnalysis(image, maxDimension: 320);
  final gray = img.grayscale(analysisImage);

  final brightness = _meanLuminance(gray);
  final sharpness = _laplacianSharpness(gray);

  return ImageMetrics(meanBrightness: brightness, sharpness: sharpness);
}

img.Image _downscaleForAnalysis(img.Image image, {required int maxDimension}) {
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

double _meanLuminance(img.Image gray) {
  var sum = 0.0;
  final pixelCount = gray.width * gray.height;
  for (final pixel in gray) {
    sum += pixel.r; // grayscale: r == g == b.
  }
  final mean = pixelCount == 0 ? 0.0 : sum / pixelCount;
  return (mean / 255.0).clamp(0.0, 1.0);
}

/// Variance of the discrete Laplacian, a standard focus measure: a sharp
/// image has strong local contrast at edges, which the Laplacian responds to;
/// a blurred image has none, so its variance collapses toward zero.
double _laplacianSharpness(img.Image gray) {
  final width = gray.width;
  final height = gray.height;
  if (width < 3 || height < 3) return 0.0;

  double luma(int x, int y) => gray.getPixel(x, y).r.toDouble();

  final laplacians = <double>[];
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final value = -4 * luma(x, y) +
          luma(x - 1, y) +
          luma(x + 1, y) +
          luma(x, y - 1) +
          luma(x, y + 1);
      laplacians.add(value);
    }
  }
  if (laplacians.isEmpty) return 0.0;

  final mean = laplacians.reduce((a, b) => a + b) / laplacians.length;
  var variance = 0.0;
  for (final v in laplacians) {
    variance += (v - mean) * (v - mean);
  }
  variance /= laplacians.length;

  // Empirically, variance above ~1200 on an 8-bit image reads as clearly
  // sharp and variance near 0 as clearly blurred; this is a scaling choice,
  // not a physical constant, and is deliberately generous rather than strict
  // — see the "do not silently reject on a low-confidence signal" principle
  // in the README.
  return (variance / 1200.0).clamp(0.0, 1.0);
}

/// Fraction of pixels in [image] whose normalized luminance is at or above
/// [luminanceThreshold] — a specular-highlight ("glare") estimate.
///
/// Callers evaluating document glare should pass the *rectified* document
/// image (or an image already cropped to the document's bounds), not the
/// full original capture: glare is only a meaningful concern within the
/// document itself, and including surrounding background would let a bright
/// window or lamp behind the card inflate the fraction for a card that is
/// perfectly readable.
double computeGlareFraction(img.Image image, {required double luminanceThreshold}) {
  final gray = img.grayscale(image);
  final threshold255 = (luminanceThreshold.clamp(0.0, 1.0) * 255).round();
  var brightCount = 0;
  final total = gray.width * gray.height;
  if (total == 0) return 0.0;
  for (final pixel in gray) {
    if (pixel.r >= threshold255) brightCount++;
  }
  return brightCount / total;
}
