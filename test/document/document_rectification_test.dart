import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_capture_kit/src/common/geometry.dart';
import 'package:smart_capture_kit/src/document/document_rectification.dart';

void main() {
  group('rectifyDocument', () {
    test('an axis-aligned quad rectifies to a faithful crop', () {
      final source = img.Image(width: 200, height: 200);
      img.fill(source, color: img.ColorRgb8(0, 0, 0));
      // A solid white square occupying the middle half of the image.
      img.fillRect(
        source,
        x1: 50,
        y1: 50,
        x2: 150,
        y2: 150,
        color: img.ColorRgb8(255, 255, 255),
      );

      const quad = Quad(
        topLeft: NormalizedPoint(0.25, 0.25),
        topRight: NormalizedPoint(0.75, 0.25),
        bottomRight: NormalizedPoint(0.75, 0.75),
        bottomLeft: NormalizedPoint(0.25, 0.75),
      );

      final rectified = rectifyDocument(
        source: source,
        quad: quad,
        outputWidth: 100,
        outputHeight: 100,
      )!;

      expect(rectified.width, 100);
      expect(rectified.height, 100);
      // The whole output should be uniformly white, since the quad exactly
      // bounds the white square.
      final center = rectified.getPixel(50, 50);
      expect(center.r, closeTo(255, 2));
      final corner = rectified.getPixel(2, 2);
      expect(corner.r, closeTo(255, 2));
    });

    test('a trapezoidal (perspective) quad still maps corners correctly', () {
      final source = img.Image(width: 400, height: 400);
      img.fill(source, color: img.ColorRgb8(10, 10, 10));
      // Paint each quadrant a distinct color so corner correspondence is
      // verifiable directly, not just "it's uniformly one color".
      img.fillRect(source, x1: 0, y1: 0, x2: 200, y2: 200, color: img.ColorRgb8(255, 0, 0));
      img.fillRect(source, x1: 200, y1: 0, x2: 400, y2: 200, color: img.ColorRgb8(0, 255, 0));
      img.fillRect(source, x1: 200, y1: 200, x2: 400, y2: 400, color: img.ColorRgb8(0, 0, 255));
      img.fillRect(source, x1: 0, y1: 200, x2: 200, y2: 400, color: img.ColorRgb8(255, 255, 0));

      // A quad whose 4 corners sit exactly at the 4 quadrant-boundary
      // intersections plus a bit of skew on the top edge.
      const quad = Quad(
        topLeft: NormalizedPoint(0.1, 0.05),
        topRight: NormalizedPoint(0.9, 0.15),
        bottomRight: NormalizedPoint(0.95, 0.95),
        bottomLeft: NormalizedPoint(0.05, 0.85),
      );

      final rectified = rectifyDocument(
        source: source,
        quad: quad,
        outputWidth: 100,
        outputHeight: 100,
      )!;

      // Each output corner should sample from deep inside its corresponding
      // source quadrant color, not bleed into a neighboring one.
      expect(rectified.getPixel(5, 5).r, greaterThan(200)); // near red quadrant
      expect(rectified.getPixel(94, 5).g, greaterThan(200)); // near green quadrant
      expect(rectified.getPixel(94, 94).b, greaterThan(200)); // near blue quadrant
      expect(rectified.getPixel(5, 94).r, greaterThan(200)); // near yellow (r+g)
      expect(rectified.getPixel(5, 94).g, greaterThan(200));
    });

    test('an out-of-bounds sample is filled rather than left uninitialized', () {
      final source = img.Image(width: 50, height: 50);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));

      // A quad that extends beyond the source image bounds.
      const quad = Quad(
        topLeft: NormalizedPoint(-0.5, -0.5),
        topRight: NormalizedPoint(1.5, -0.5),
        bottomRight: NormalizedPoint(1.5, 1.5),
        bottomLeft: NormalizedPoint(-0.5, 1.5),
      );

      final rectified = rectifyDocument(
        source: source,
        quad: quad,
        outputWidth: 60,
        outputHeight: 60,
      )!;
      // Corners of the output map outside the source and should be filled,
      // not sampled as if they were white.
      final corner = rectified.getPixel(0, 0);
      expect(corner.r, lessThan(200));
    });

    test('returns null for a degenerate (collinear) quad', () {
      final source = img.Image(width: 50, height: 50);
      const degenerate = Quad(
        topLeft: NormalizedPoint(0.0, 0.5),
        topRight: NormalizedPoint(0.33, 0.5),
        bottomRight: NormalizedPoint(0.66, 0.5),
        bottomLeft: NormalizedPoint(1.0, 0.5),
      );
      expect(
        rectifyDocument(
          source: source,
          quad: degenerate,
          outputWidth: 50,
          outputHeight: 50,
        ),
        isNull,
      );
    });
  });
}
