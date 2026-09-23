import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A point expressed in the *normalized* coordinate space of an image, where
/// `(0, 0)` is the top-left corner and `(1, 1)` the bottom-right corner.
///
/// Normalized coordinates let guidance computed on a low-resolution preview
/// frame be compared against, and reused on, the full-resolution capture
/// without rescaling every consumer.
@immutable
class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);

  final double x;
  final double y;

  /// Euclidean distance to [other] in normalized units.
  double distanceTo(NormalizedPoint other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));

  NormalizedPoint operator -(NormalizedPoint other) =>
      NormalizedPoint(x - other.x, y - other.y);

  /// Whether the point lies inside the unit square, i.e. inside the image.
  bool get isInsideImage => x >= 0 && x <= 1 && y >= 0 && y <= 1;

  @override
  bool operator ==(Object other) =>
      other is NormalizedPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'NormalizedPoint(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';
}

/// An axis-aligned rectangle in normalized image coordinates.
@immutable
class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Builds a rect from pixel coordinates measured against an image of
  /// [imageWidth] x [imageHeight] pixels.
  factory NormalizedRect.fromPixels({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required int imageWidth,
    required int imageHeight,
  }) {
    assert(imageWidth > 0 && imageHeight > 0);
    return NormalizedRect(
      left: left / imageWidth,
      top: top / imageHeight,
      right: right / imageWidth,
      bottom: bottom / imageHeight,
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;

  NormalizedPoint get center =>
      NormalizedPoint(left + width / 2, top + height / 2);

  /// The rect that encloses both this rect and [other].
  ///
  /// Used to build a single evidence box for a field whose text spans several
  /// OCR lines.
  NormalizedRect union(NormalizedRect other) => NormalizedRect(
        left: math.min(left, other.left),
        top: math.min(top, other.top),
        right: math.max(right, other.right),
        bottom: math.max(bottom, other.bottom),
      );

  @override
  bool operator ==(Object other) =>
      other is NormalizedRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'NormalizedRect($left, $top, $right, $bottom)';
}

/// Four corners of a detected document, in normalized image coordinates.
///
/// Corners are stored in a fixed order so that perspective correction and
/// distortion checks do not have to re-derive orientation. Use
/// [Quad.fromUnorderedPoints] when the detector emits corners in arbitrary
/// order.
@immutable
class Quad {
  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Orders four arbitrary corner points into a consistent clockwise quad.
  ///
  /// Points are assigned by their position relative to the centroid, which is
  /// robust to the moderate rotation a hand-held capture produces. It is *not*
  /// robust to rotation beyond roughly 45 degrees; at that point the capture
  /// should be rejected on orientation grounds rather than silently reordered.
  factory Quad.fromUnorderedPoints(List<NormalizedPoint> points) {
    if (points.length != 4) {
      throw ArgumentError.value(
        points.length,
        'points',
        'A quad requires exactly 4 points',
      );
    }
    final cx = points.map((p) => p.x).reduce((a, b) => a + b) / 4;
    final cy = points.map((p) => p.y).reduce((a, b) => a + b) / 4;

    NormalizedPoint? topLeft, topRight, bottomRight, bottomLeft;
    for (final p in points) {
      final isLeft = p.x < cx;
      final isTop = p.y < cy;
      if (isTop && isLeft) {
        topLeft = p;
      } else if (isTop && !isLeft) {
        topRight = p;
      } else if (!isTop && !isLeft) {
        bottomRight = p;
      } else {
        bottomLeft = p;
      }
    }

    if (topLeft == null ||
        topRight == null ||
        bottomRight == null ||
        bottomLeft == null) {
      throw ArgumentError.value(
        points,
        'points',
        'Points do not form a quad with one corner per quadrant; the shape is '
            'degenerate or rotated too far to order reliably',
      );
    }
    return Quad(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    );
  }

  final NormalizedPoint topLeft;
  final NormalizedPoint topRight;
  final NormalizedPoint bottomRight;
  final NormalizedPoint bottomLeft;

  List<NormalizedPoint> get corners =>
      [topLeft, topRight, bottomRight, bottomLeft];

  /// Whether every corner lies within the image bounds.
  ///
  /// A `false` result means at least one corner is cut off by the frame edge.
  bool get isFullyInsideImage => corners.every((c) => c.isInsideImage);

  /// Area of the quad as a fraction of the whole image, via the shoelace
  /// formula.
  ///
  /// Drives the "document too small in frame" check: a card occupying a small
  /// fraction of the image yields too few pixels per character for OCR.
  double get areaFraction {
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// A measure of perspective distortion in the range `[0, 1]`, where `0` is a
  /// perfect rectangle.
  ///
  /// Computed as the relative disagreement between the lengths of opposite
  /// sides. A card photographed straight-on has equal opposite sides; tilting
  /// the phone shortens the far edge.
  double get perspectiveDistortion {
    double side(NormalizedPoint a, NormalizedPoint b) => a.distanceTo(b);

    final top = side(topLeft, topRight);
    final bottom = side(bottomLeft, bottomRight);
    final left = side(topLeft, bottomLeft);
    final right = side(topRight, bottomRight);

    double ratio(double a, double b) {
      final maxSide = math.max(a, b);
      if (maxSide <= 0) return 1;
      return (a - b).abs() / maxSide;
    }

    return math.max(ratio(top, bottom), ratio(left, right));
  }

  /// Aspect ratio (width / height) estimated from the averaged side lengths.
  ///
  /// Returns `null` for a degenerate quad with zero height, rather than
  /// dividing by zero or inventing a plausible-looking number.
  double? get estimatedAspectRatio {
    final width =
        (topLeft.distanceTo(topRight) + bottomLeft.distanceTo(bottomRight)) / 2;
    final height =
        (topLeft.distanceTo(bottomLeft) + topRight.distanceTo(bottomRight)) / 2;
    if (height <= 0) return null;
    return width / height;
  }

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode =>
      Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'Quad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}
