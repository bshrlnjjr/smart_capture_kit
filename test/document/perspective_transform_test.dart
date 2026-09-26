import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/src/document/perspective_transform.dart';

void main() {
  group('solvePerspectiveMap', () {
    test('recovers the identity map for a unit-square-to-itself correspondence',
        () {
      final map = solvePerspectiveMap(
        from: const [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)],
        to: const [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)],
      )!;
      final (x, y) = map.apply(0.37, 0.82);
      expect(x, closeTo(0.37, 1e-9));
      expect(y, closeTo(0.82, 1e-9));
    });

    test('recovers a pure scale-and-translate affine map', () {
      // dest unit square -> a 200x100 rect placed at (50, 60): this has no
      // perspective term at all, so the solved g/h coefficients should be ~0.
      final map = solvePerspectiveMap(
        from: const [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)],
        to: const [(50.0, 60.0), (250.0, 60.0), (250.0, 160.0), (50.0, 160.0)],
      )!;
      expect(map.coefficients[6], closeTo(0, 1e-9)); // g
      expect(map.coefficients[7], closeTo(0, 1e-9)); // h

      final (cx, cy) = map.apply(0.5, 0.5);
      expect(cx, closeTo(150.0, 1e-6));
      expect(cy, closeTo(110.0, 1e-6));
    });

    test('reproduces an interior point of a known perspective warp, not just '
        'the 4 corners used to solve it', () {
      // A hand-picked, genuinely projective map (nonzero g/h): forward-warp a
      // 5x5 grid of (u,v) points through it, feed 4 of the corners as the
      // "known" correspondence, then check the solver reconstructs the exact
      // same map by verifying it reproduces an interior point it was never
      // given — the strong version of this test, since 4 correct corners
      // alone would already be satisfied by the true solution.
      final knownMap =
          PerspectiveMap([1.2, 0.3, 10, -0.1, 0.9, 5, 0.0008, 0.0003]);

      Pt forward(double u, double v) => knownMap.apply(u, v);

      final corners = [
        forward(0, 0),
        forward(100, 0),
        forward(100, 100),
        forward(0, 100),
      ];
      final interior = forward(37, 64);

      final solved = solvePerspectiveMap(
        from: const [(0.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0)],
        to: corners,
      )!;
      final reconstructed = solved.apply(37, 64);

      expect(reconstructed.$1, closeTo(interior.$1, 1e-6));
      expect(reconstructed.$2, closeTo(interior.$2, 1e-6));
    });

    test('returns null for a degenerate, collinear point set', () {
      final map = solvePerspectiveMap(
        from: const [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)],
        to: const [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)],
      );
      expect(map, isNull);
    });

    test('rejects anything other than exactly 4 point pairs', () {
      expect(
        () => solvePerspectiveMap(
          from: const [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0)],
          to: const [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0)],
        ),
        throwsArgumentError,
      );
    });
  });
}
