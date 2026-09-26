import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_capture_kit/src/document/document_boundary_detection.dart';

/// Draws a light rectangle on a dark, uniform background — the simplest case
/// the detector is designed for: a real luminance discontinuity at the
/// document's edge.
img.Image _cardOnBackground({
  required int imageSize,
  required List<img.Point> corners,
}) {
  final image = img.Image(width: imageSize, height: imageSize);
  img.fill(image, color: img.ColorRgb8(20, 20, 20));
  img.fillPolygon(image, vertices: corners, color: img.ColorRgb8(230, 230, 230));
  return image;
}

void main() {
  group('detectDocumentBoundary', () {
    test('finds an axis-aligned card centered in the frame', () {
      final image = _cardOnBackground(
        imageSize: 400,
        corners: [
          img.Point(80, 100),
          img.Point(320, 100),
          img.Point(320, 300),
          img.Point(80, 300),
        ],
      );

      final result = detectDocumentBoundary(image)!;
      expect(result.quad.topLeft.x, closeTo(80 / 400, 0.03));
      expect(result.quad.topLeft.y, closeTo(100 / 400, 0.03));
      expect(result.quad.bottomRight.x, closeTo(320 / 400, 0.03));
      expect(result.quad.bottomRight.y, closeTo(300 / 400, 0.03));
      expect(result.confidence, greaterThan(0.3));
    });

    test('finds a perspective-skewed (trapezoidal) card', () {
      // The far (top) edge is narrower than the near (bottom) edge, as a
      // card photographed at an angle would appear.
      final image = _cardOnBackground(
        imageSize: 400,
        corners: [
          img.Point(140, 100),
          img.Point(260, 100),
          img.Point(320, 300),
          img.Point(80, 300),
        ],
      );

      final result = detectDocumentBoundary(image)!;
      // The detected top edge should be narrower than the bottom edge.
      final topWidth = result.quad.topRight.x - result.quad.topLeft.x;
      final bottomWidth = result.quad.bottomRight.x - result.quad.bottomLeft.x;
      expect(topWidth, lessThan(bottomWidth));
    });

    test('returns null for a featureless, uniform image', () {
      final image = img.Image(width: 300, height: 300);
      img.fill(image, color: img.ColorRgb8(128, 128, 128));

      expect(detectDocumentBoundary(image), isNull);
    });

    test('returns null when the "document" fills almost the entire frame '
        '(no background ring to flood-fill from)', () {
      final image = _cardOnBackground(
        imageSize: 300,
        corners: [
          img.Point(2, 2),
          img.Point(298, 2),
          img.Point(298, 298),
          img.Point(2, 298),
        ],
      );
      expect(detectDocumentBoundary(image), isNull);
    });

    test('returns null when the candidate region is implausibly small', () {
      final image = _cardOnBackground(
        imageSize: 400,
        corners: [
          img.Point(190, 195),
          img.Point(210, 195),
          img.Point(210, 205),
          img.Point(190, 205),
        ],
      );
      expect(detectDocumentBoundary(image), isNull);
    });

    test('is resolution-independent: the same scene at different sizes '
        'yields the same normalized quad', () {
      const relativeCorners = [
        (0.2, 0.25),
        (0.8, 0.25),
        (0.8, 0.75),
        (0.2, 0.75),
      ];
      img.Image buildAt(int size) => _cardOnBackground(
            imageSize: size,
            corners: [
              for (final (x, y) in relativeCorners) img.Point(x * size, y * size)
            ],
          );

      final small = detectDocumentBoundary(buildAt(200))!;
      final large = detectDocumentBoundary(buildAt(900))!;

      expect(small.quad.topLeft.x, closeTo(large.quad.topLeft.x, 0.03));
      expect(small.quad.topLeft.y, closeTo(large.quad.topLeft.y, 0.03));
      expect(small.quad.bottomRight.x, closeTo(large.quad.bottomRight.x, 0.03));
    });
  });
}
