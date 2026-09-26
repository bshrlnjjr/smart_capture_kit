import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/src/document/hull_geometry.dart';
import 'package:smart_capture_kit/src/document/perspective_transform.dart' show Pt;

void main() {
  group('convexHull', () {
    test('a square with an interior point drops the interior point', () {
      final hull = convexHull(const [
        (0.0, 0.0),
        (10.0, 0.0),
        (10.0, 10.0),
        (0.0, 10.0),
        (5.0, 5.0), // interior
      ]);
      expect(hull, hasLength(4));
      expect(hull, isNot(contains((5.0, 5.0))));
      for (final corner in const [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]) {
        expect(hull, contains(corner));
      }
    });

    test('drops a collinear point sitting on an edge', () {
      final hull = convexHull(const [
        (0.0, 0.0),
        (5.0, 0.0), // collinear, on the bottom edge
        (10.0, 0.0),
        (10.0, 10.0),
        (0.0, 10.0),
      ]);
      expect(hull, isNot(contains((5.0, 0.0))));
      expect(hull, hasLength(4));
    });

    test('fewer than 3 points is returned unchanged (deduplicated)', () {
      expect(convexHull(const [(0.0, 0.0)]), [(0.0, 0.0)]);
      expect(
        convexHull(const [(0.0, 0.0), (0.0, 0.0)]),
        [(0.0, 0.0)],
      );
    });

    test('handles a rotated square correctly', () {
      // A square rotated 45 degrees: diamond corners.
      final hull = convexHull(const [
        (5.0, 0.0),
        (10.0, 5.0),
        (5.0, 10.0),
        (0.0, 5.0),
        (5.0, 5.0), // center, interior
      ]);
      expect(hull, hasLength(4));
      expect(hull, isNot(contains((5.0, 5.0))));
    });
  });

  group('reduceHullToQuad', () {
    test('reduces an axis-aligned rectangle hull to its 4 corners', () {
      final quad = reduceHullToQuad(
        const [(10.0, 10.0), (90.0, 10.0), (90.0, 90.0), (10.0, 90.0)],
        imageWidth: 100,
        imageHeight: 100,
      )!;
      expect(quad.topLeft.x, closeTo(0.10, 1e-9));
      expect(quad.topLeft.y, closeTo(0.10, 1e-9));
      expect(quad.bottomRight.x, closeTo(0.90, 1e-9));
      expect(quad.bottomRight.y, closeTo(0.90, 1e-9));
    });

    test('picks the farthest point per quadrant, ignoring closer ones', () {
      final quad = reduceHullToQuad(
        const [
          (10.0, 10.0), // true top-left corner
          (30.0, 30.0), // a nearer, spurious top-left-ish hull point
          (90.0, 10.0),
          (90.0, 90.0),
          (10.0, 90.0),
        ],
        imageWidth: 100,
        imageHeight: 100,
      )!;
      expect(quad.topLeft.x, closeTo(0.10, 1e-9));
      expect(quad.topLeft.y, closeTo(0.10, 1e-9));
    });

    test('returns null when a quadrant has no hull point at all', () {
      // Only 3 quadrants populated: no point below-and-left of the centroid.
      final quad = reduceHullToQuad(
        const [(50.0, 10.0), (90.0, 50.0), (50.0, 50.0)],
        imageWidth: 100,
        imageHeight: 100,
      );
      expect(quad, isNull);
    });

    test('returns null for fewer than 4 hull points', () {
      final quad = reduceHullToQuad(
        const <Pt>[(0.0, 0.0), (10.0, 10.0)],
        imageWidth: 100,
        imageHeight: 100,
      );
      expect(quad, isNull);
    });
  });
}
