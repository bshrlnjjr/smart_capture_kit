import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

void main() {
  group('NormalizedRect', () {
    test('fromPixels divides by the image dimensions', () {
      final rect = NormalizedRect.fromPixels(
        left: 100,
        top: 50,
        right: 300,
        bottom: 250,
        imageWidth: 400,
        imageHeight: 500,
      );
      expect(rect.left, 0.25);
      expect(rect.top, 0.1);
      expect(rect.width, closeTo(0.5, 1e-9));
      expect(rect.height, closeTo(0.4, 1e-9));
    });

    test('union encloses both rects', () {
      const a = NormalizedRect(left: 0.1, top: 0.1, right: 0.3, bottom: 0.3);
      const b = NormalizedRect(left: 0.5, top: 0.05, right: 0.6, bottom: 0.4);
      final u = a.union(b);
      expect(u.left, 0.1);
      expect(u.top, 0.05);
      expect(u.right, 0.6);
      expect(u.bottom, 0.4);
    });

    test('center sits at the midpoint', () {
      const r = NormalizedRect(left: 0.2, top: 0.2, right: 0.8, bottom: 0.6);
      expect(r.center.x, closeTo(0.5, 1e-9));
      expect(r.center.y, closeTo(0.4, 1e-9));
    });
  });

  group('Quad', () {
    const perfect = Quad(
      topLeft: NormalizedPoint(0.1, 0.2),
      topRight: NormalizedPoint(0.9, 0.2),
      bottomRight: NormalizedPoint(0.9, 0.8),
      bottomLeft: NormalizedPoint(0.1, 0.8),
    );

    test('orders shuffled corners into the canonical arrangement', () {
      final quad = Quad.fromUnorderedPoints(const [
        NormalizedPoint(0.9, 0.8),
        NormalizedPoint(0.1, 0.2),
        NormalizedPoint(0.1, 0.8),
        NormalizedPoint(0.9, 0.2),
      ]);
      expect(quad, perfect);
    });

    test('rejects a point count other than four', () {
      expect(
        () => Quad.fromUnorderedPoints(const [NormalizedPoint(0, 0)]),
        throwsArgumentError,
      );
    });

    test('rejects a degenerate shape with two points in one quadrant', () {
      expect(
        () => Quad.fromUnorderedPoints(const [
          NormalizedPoint(0.1, 0.1),
          NormalizedPoint(0.2, 0.15),
          NormalizedPoint(0.9, 0.9),
          NormalizedPoint(0.95, 0.95),
        ]),
        throwsArgumentError,
      );
    });

    test('areaFraction matches the rectangle area', () {
      // 0.8 wide by 0.6 tall.
      expect(perfect.areaFraction, closeTo(0.48, 1e-9));
    });

    test('a rectangle has zero perspective distortion', () {
      expect(perfect.perspectiveDistortion, closeTo(0, 1e-9));
    });

    test('a tilted card reports non-zero perspective distortion', () {
      // Top edge shorter than the bottom edge: the card leans away.
      const tilted = Quad(
        topLeft: NormalizedPoint(0.2, 0.2),
        topRight: NormalizedPoint(0.8, 0.2),
        bottomRight: NormalizedPoint(0.9, 0.8),
        bottomLeft: NormalizedPoint(0.1, 0.8),
      );
      expect(tilted.perspectiveDistortion, greaterThan(0.2));
    });

    test('isFullyInsideImage is false when a corner is cut off', () {
      const cutOff = Quad(
        topLeft: NormalizedPoint(-0.05, 0.2),
        topRight: NormalizedPoint(0.9, 0.2),
        bottomRight: NormalizedPoint(0.9, 0.8),
        bottomLeft: NormalizedPoint(0.1, 0.8),
      );
      expect(cutOff.isFullyInsideImage, isFalse);
      expect(perfect.isFullyInsideImage, isTrue);
    });

    test('estimatedAspectRatio reflects the shape', () {
      // 0.8 / 0.6.
      expect(perfect.estimatedAspectRatio, closeTo(0.8 / 0.6, 1e-9));
    });

    test('estimatedAspectRatio is null for a zero-height quad', () {
      const flat = Quad(
        topLeft: NormalizedPoint(0.1, 0.5),
        topRight: NormalizedPoint(0.9, 0.5),
        bottomRight: NormalizedPoint(0.9, 0.5),
        bottomLeft: NormalizedPoint(0.1, 0.5),
      );
      expect(flat.estimatedAspectRatio, isNull);
    });
  });
}
