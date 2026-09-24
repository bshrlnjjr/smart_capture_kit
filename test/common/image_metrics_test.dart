import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_capture_kit/src/common/image_metrics.dart';

img.Image _solidImage(int size, int gray) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(gray, gray, gray));
  return image;
}

img.Image _checkerboardImage(int size, {int cell = 4}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final isBlack = ((x ~/ cell) + (y ~/ cell)).isEven;
      image.setPixelRgb(x, y, isBlack ? 0 : 255, isBlack ? 0 : 255, isBlack ? 0 : 255);
    }
  }
  return image;
}

void main() {
  group('computeImageMetrics brightness', () {
    test('a black image reports brightness near 0', () {
      final metrics = computeImageMetrics(_solidImage(64, 0));
      expect(metrics.meanBrightness, closeTo(0.0, 0.02));
    });

    test('a white image reports brightness near 1', () {
      final metrics = computeImageMetrics(_solidImage(64, 255));
      expect(metrics.meanBrightness, closeTo(1.0, 0.02));
    });

    test('a mid-gray image reports brightness near 0.5', () {
      final metrics = computeImageMetrics(_solidImage(64, 128));
      expect(metrics.meanBrightness, closeTo(128 / 255, 0.02));
    });
  });

  group('computeImageMetrics sharpness', () {
    test('a flat, featureless image scores minimal sharpness', () {
      final metrics = computeImageMetrics(_solidImage(128, 128));
      expect(metrics.sharpness, closeTo(0.0, 0.01));
    });

    test('a high-contrast checkerboard scores clearly higher than flat', () {
      final flat = computeImageMetrics(_solidImage(128, 128));
      final sharp = computeImageMetrics(_checkerboardImage(128));
      expect(sharp.sharpness, greaterThan(flat.sharpness));
      expect(sharp.sharpness, greaterThan(0.3));
    });

    test('sharpness is always within [0, 1]', () {
      final metrics = computeImageMetrics(_checkerboardImage(200, cell: 1));
      expect(metrics.sharpness, inInclusiveRange(0.0, 1.0));
    });
  });

  group('computeImageMetrics scaling', () {
    test('produces consistent results regardless of source resolution', () {
      // The analysis downscales internally, so a large solid-color image
      // should not report meaningfully different brightness than a small one.
      final small = computeImageMetrics(_solidImage(32, 200));
      final large = computeImageMetrics(_solidImage(2000, 200));
      expect(small.meanBrightness, closeTo(large.meanBrightness, 0.02));
    });
  });
}
