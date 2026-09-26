import 'package:image/image.dart' as img;

import '../common/geometry.dart';
import 'perspective_transform.dart';

/// Warps the region of [source] bounded by [quad] into an axis-aligned
/// rectangle of [outputWidth] x [outputHeight], correcting the perspective
/// distortion a photographed card has when the camera was not perfectly
/// fronto-parallel to it.
///
/// [quad] is in normalized (0..1) coordinates against [source]'s own
/// dimensions, matching every other corner-carrying type in this package.
///
/// Returns `null` when [quad] cannot be inverted to a perspective map (a
/// degenerate quad — see [solvePerspectiveMap]) rather than producing a
/// warped image built on meaningless coefficients.
img.Image? rectifyDocument({
  required img.Image source,
  required Quad quad,
  required int outputWidth,
  required int outputHeight,
}) {
  final srcWidth = source.width.toDouble();
  final srcHeight = source.height.toDouble();

  final map = solvePerspectiveMap(
    from: [
      (0.0, 0.0),
      (outputWidth.toDouble(), 0.0),
      (outputWidth.toDouble(), outputHeight.toDouble()),
      (0.0, outputHeight.toDouble()),
    ],
    to: [
      (quad.topLeft.x * srcWidth, quad.topLeft.y * srcHeight),
      (quad.topRight.x * srcWidth, quad.topRight.y * srcHeight),
      (quad.bottomRight.x * srcWidth, quad.bottomRight.y * srcHeight),
      (quad.bottomLeft.x * srcWidth, quad.bottomLeft.y * srcHeight),
    ],
  );
  if (map == null) return null;

  final output = img.Image(width: outputWidth, height: outputHeight);
  final fill = img.ColorRgb8(32, 32, 32);

  for (var oy = 0; oy < outputHeight; oy++) {
    for (var ox = 0; ox < outputWidth; ox++) {
      final (sx, sy) = map.apply(ox + 0.5, oy + 0.5);
      if (sx < 0 || sy < 0 || sx > srcWidth - 1 || sy > srcHeight - 1) {
        output.setPixel(ox, oy, fill);
        continue;
      }
      output.setPixel(ox, oy, _bilinearSample(source, sx, sy));
    }
  }
  return output;
}

img.Color _bilinearSample(img.Image image, double x, double y) {
  final x0 = x.floor().clamp(0, image.width - 1);
  final y0 = y.floor().clamp(0, image.height - 1);
  final x1 = (x0 + 1).clamp(0, image.width - 1);
  final y1 = (y0 + 1).clamp(0, image.height - 1);
  final fx = x - x0;
  final fy = y - y0;

  final p00 = image.getPixel(x0, y0);
  final p10 = image.getPixel(x1, y0);
  final p01 = image.getPixel(x0, y1);
  final p11 = image.getPixel(x1, y1);

  double lerp(num a, num b, double t) => a + (b - a) * t;
  double channel(num c00, num c10, num c01, num c11) => lerp(
        lerp(c00, c10, fx),
        lerp(c01, c11, fx),
        fy,
      );

  return img.ColorRgb8(
    channel(p00.r, p10.r, p01.r, p11.r).round(),
    channel(p00.g, p10.g, p01.g, p11.g).round(),
    channel(p00.b, p10.b, p01.b, p11.b).round(),
  );
}
