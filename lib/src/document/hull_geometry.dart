import '../common/geometry.dart';
import 'perspective_transform.dart' show Pt;

/// Convex hull via Andrew's monotone chain, O(n log n).
///
/// Pure geometry, independent of image processing, so the boundary detector's
/// hardest-to-get-wrong step can be unit tested with plain point lists rather
/// than only through slower, harder-to-debug rendered-image tests.
///
/// Returns the hull in counter-clockwise order starting from the lowest,
/// then leftmost, point. Collinear points on an edge are dropped. Fewer than
/// 3 distinct points return the (deduplicated) input unchanged — there is no
/// hull to compute.
List<Pt> convexHull(List<Pt> points) {
  final unique = <Pt>{...points}.toList()
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  if (unique.length < 3) return unique;

  double cross(Pt o, Pt a, Pt b) =>
      (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);

  final lower = <Pt>[];
  for (final p in unique) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }

  final upper = <Pt>[];
  for (final p in unique.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }

  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Reduces a convex hull to the 4 corners of the document it most likely
/// bounds, assuming the document is roughly axis-aligned in frame.
///
/// The assumption holds for guided capture, where the on-screen overlay leads
/// the user to hold the card close to upright — the same assumption
/// `Quad.fromUnorderedPoints` already documents and degrades the same way:
/// reliable up to moderate rotation, not for a card turned close to 45
/// degrees. For each of the 4 quadrants around the hull's centroid, this
/// picks the single hull point farthest from the centroid; a quadrant with no
/// hull point at all (a genuinely non-rectangular or very rotated shape)
/// returns `null` rather than guessing.
///
/// [imageWidth] and [imageHeight] convert the pixel-space hull to the
/// normalized `Quad` every other capture-side API already uses.
Quad? reduceHullToQuad(
  List<Pt> hull, {
  required double imageWidth,
  required double imageHeight,
}) {
  if (hull.length < 4) return null;

  final cx = hull.map((p) => p.$1).reduce((a, b) => a + b) / hull.length;
  final cy = hull.map((p) => p.$2).reduce((a, b) => a + b) / hull.length;

  Pt? topLeft, topRight, bottomRight, bottomLeft;
  double bestTL = -1, bestTR = -1, bestBR = -1, bestBL = -1;

  for (final p in hull) {
    final dx = p.$1 - cx;
    final dy = p.$2 - cy;
    final dist = dx * dx + dy * dy;
    final isLeft = dx < 0;
    final isTop = dy < 0;
    if (isTop && isLeft) {
      if (dist > bestTL) {
        bestTL = dist;
        topLeft = p;
      }
    } else if (isTop && !isLeft) {
      if (dist > bestTR) {
        bestTR = dist;
        topRight = p;
      }
    } else if (!isTop && !isLeft) {
      if (dist > bestBR) {
        bestBR = dist;
        bottomRight = p;
      }
    } else {
      if (dist > bestBL) {
        bestBL = dist;
        bottomLeft = p;
      }
    }
  }

  if (topLeft == null || topRight == null || bottomRight == null || bottomLeft == null) {
    return null;
  }

  NormalizedPoint normalize(Pt p) =>
      NormalizedPoint(p.$1 / imageWidth, p.$2 / imageHeight);

  return Quad(
    topLeft: normalize(topLeft),
    topRight: normalize(topRight),
    bottomRight: normalize(bottomRight),
    bottomLeft: normalize(bottomLeft),
  );
}
