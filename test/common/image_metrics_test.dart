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

  group('computeGlareFraction', () {
    test('a uniformly dark image has zero glare', () {
      final fraction = computeGlareFraction(
        _solidImage(64, 20),
        luminanceThreshold: 0.9,
      );
      expect(fraction, 0.0);
    });

    test('a uniformly blown-out image is entirely glare', () {
      final fraction = computeGlareFraction(
        _solidImage(64, 255),
        luminanceThreshold: 0.9,
      );
      expect(fraction, 1.0);
    });

    test('a bright patch on a dark background reports its exact area '
        'fraction', () {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(20, 20, 20));
      // A 20x20 blown-out patch: 4% of the 100x100 image.
      img.fillRect(image, x1: 40, y1: 40, x2: 60, y2: 60, color: img.ColorRgb8(255, 255, 255));

      final fraction = computeGlareFraction(image, luminanceThreshold: 0.9);
      expect(fraction, closeTo(0.04, 0.005));
    });

    test('raising the threshold lowers the reported fraction', () {
      final image = img.Image(width: 50, height: 50);
      img.fill(image, color: img.ColorRgb8(200, 200, 200)); // ~0.78 normalized

      final lowThreshold = computeGlareFraction(image, luminanceThreshold: 0.5);
      final highThreshold = computeGlareFraction(image, luminanceThreshold: 0.95);
      expect(lowThreshold, 1.0);
      expect(highThreshold, 0.0);
    });
  });
}
