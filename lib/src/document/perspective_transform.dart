/// Solves and applies the projective (perspective) transform used to
/// rectify a photographed document.
///
/// This is the same well-established 4-point-correspondence method OpenCV's
/// `getPerspectiveTransform` uses — a projective map has 8 degrees of
/// freedom, and 4 point correspondences (2 equations each) determine it
/// exactly by solving an 8x8 linear system. Deliberately not a bilinear
/// mapping: bilinear only reproduces a true perspective warp for a
/// parallelogram source, and a photographed card under camera perspective is
/// essentially never a parallelogram.
library;

/// A 2D point as a record — no need for a dedicated class since every
/// consumer just wants `.$1`/`.$2` or destructuring, and this keeps the
/// public surface free of a type that would otherwise duplicate
/// `NormalizedPoint` for a purely internal, pixel-space concern.
typedef Pt = (double x, double y);

/// A solved projective map from a `(u, v)` domain to an `(x, y)` range:
///
/// ```
/// x = (m0*u + m1*v + m2) / (m6*u + m7*v + 1)
/// y = (m3*u + m4*v + m5) / (m6*u + m7*v + 1)
/// ```
///
/// Built by [solvePerspectiveMap] to map an axis-aligned output rectangle's
/// `(u, v)` pixel coordinates to the `(x, y)` pixel coordinates of the
/// detected, possibly skewed, quad in the source image — i.e. it is already
/// the *inverse* direction a rectification warp needs (destination pixel to
/// source pixel), so no separate matrix inversion step is required.
class PerspectiveMap {
  const PerspectiveMap(this.coefficients) : assert(coefficients.length == 8);

  final List<double> coefficients;

  Pt apply(double u, double v) {
    final m = coefficients;
    final denom = m[6] * u + m[7] * v + 1.0;
    final x = (m[0] * u + m[1] * v + m[2]) / denom;
    final y = (m[3] * u + m[4] * v + m[5]) / denom;
    return (x, y);
  }
}

/// Solves for the projective map taking each `from[i]` to `to[i]`.
///
/// Exactly 4 correspondences are required — a projective transform has 8
/// degrees of freedom and each point pair contributes 2 equations. Returns
/// `null` when the system is singular (e.g. 3+ collinear points), which
/// callers treat the same as "no confident rectification" rather than
/// propagating garbage coefficients.
PerspectiveMap? solvePerspectiveMap({
  required List<Pt> from,
  required List<Pt> to,
}) {
  if (from.length != 4 || to.length != 4) {
    throw ArgumentError('solvePerspectiveMap requires exactly 4 point pairs');
  }

  // Build the 8x8 system A*m = b described in the class doc: for each pair
  // (u,v) -> (x,y),
  //   m0*u + m1*v + m2                     - m6*u*x - m7*v*x = x
  //                     m3*u + m4*v + m5   - m6*u*y - m7*v*y = y
  final a = List.generate(8, (_) => List<double>.filled(8, 0));
  final b = List<double>.filled(8, 0);

  for (var i = 0; i < 4; i++) {
    final (u, v) = from[i];
    final (x, y) = to[i];

    final rowX = i * 2;
    a[rowX][0] = u;
    a[rowX][1] = v;
    a[rowX][2] = 1;
    a[rowX][6] = -u * x;
    a[rowX][7] = -v * x;
    b[rowX] = x;

    final rowY = i * 2 + 1;
    a[rowY][3] = u;
    a[rowY][4] = v;
    a[rowY][5] = 1;
    a[rowY][6] = -u * y;
    a[rowY][7] = -v * y;
    b[rowY] = y;
  }

  final solved = _solveLinearSystem(a, b);
  return solved == null ? null : PerspectiveMap(solved);
}

/// Gaussian elimination with partial pivoting on an `n`x`n` system.
///
/// Small, self-contained, and only used here — not worth pulling in a linear
/// algebra dependency for one 8x8 solve.
List<double>? _solveLinearSystem(List<List<double>> a, List<double> b) {
  final n = b.length;
  // Augment for elimination; work on copies so callers' inputs are untouched.
  final m = List.generate(n, (i) => List<double>.from(a[i]));
  final rhs = List<double>.from(b);

  for (var col = 0; col < n; col++) {
    var pivotRow = col;
    var pivotValue = m[col][col].abs();
    for (var row = col + 1; row < n; row++) {
      if (m[row][col].abs() > pivotValue) {
        pivotRow = row;
        pivotValue = m[row][col].abs();
      }
    }
    if (pivotValue < 1e-9) return null; // singular: degenerate point set

    if (pivotRow != col) {
      final tmpRow = m[col];
      m[col] = m[pivotRow];
      m[pivotRow] = tmpRow;
      final tmpB = rhs[col];
      rhs[col] = rhs[pivotRow];
      rhs[pivotRow] = tmpB;
    }

    for (var row = col + 1; row < n; row++) {
      final factor = m[row][col] / m[col][col];
      if (factor == 0) continue;
      for (var k = col; k < n; k++) {
        m[row][k] -= factor * m[col][k];
      }
      rhs[row] -= factor * rhs[col];
    }
  }

  final result = List<double>.filled(n, 0);
  for (var row = n - 1; row >= 0; row--) {
    var sum = rhs[row];
    for (var col = row + 1; col < n; col++) {
      sum -= m[row][col] * result[col];
    }
    result[row] = sum / m[row][row];
  }
  return result;
}
