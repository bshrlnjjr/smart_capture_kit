import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/src/document/document_boundary_detection.dart';
import 'package:smart_capture_kit/src/document/document_live_detection.dart';

/// A luma8 plane of [width] x [height] (row stride [bytesPerRow]) that is
/// dark everywhere except a bright axis-aligned rectangle.
LivePlane _lumaPlaneWithRect({
  required int width,
  required int height,
  int? bytesPerRow,
  required (int, int, int, int) rect, // left, top, right, bottom (exclusive)
  int rotationDegrees = 0,
}) {
  final stride = bytesPerRow ?? width;
  final bytes = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < stride; x++) {
      final inside = x >= rect.$1 && x < rect.$3 && y >= rect.$2 && y < rect.$4;
      // Row padding is filled with a distinct value so reading it by mistake
      // would show up in the output.
      bytes[y * stride + x] = x >= width ? 255 : (inside ? 230 : 20);
    }
  }
  return LivePlane(
    bytes: bytes,
    width: width,
    height: height,
    bytesPerRow: stride,
    format: LivePlaneFormat.luma8,
    rotationDegrees: rotationDegrees,
  );
}

void main() {
  group('lumaImageFromPlane', () {
    test('averages blocks down to the requested size', () {
      final plane = _lumaPlaneWithRect(
        width: 640,
        height: 480,
        rect: (0, 0, 0, 0),
      );
      final image = lumaImageFromPlane(plane, maxDimension: 320)!;
      expect(image.width, 320);
      expect(image.height, 240);
      expect(image.getPixel(10, 10).r, 20);
    });

    test('skips row padding', () {
      final plane = _lumaPlaneWithRect(
        width: 100,
        height: 50,
        bytesPerRow: 128,
        rect: (0, 0, 0, 0),
      );
      final image = lumaImageFromPlane(plane, maxDimension: 100)!;
      expect(image.width, 100);
      for (var x = 0; x < image.width; x++) {
        expect(image.getPixel(x, 0).r, 20, reason: 'column $x');
      }
    });

    test('rotates 90 degrees clockwise so a top-left patch ends top-right', () {
      final plane = _lumaPlaneWithRect(
        width: 40,
        height: 20,
        rect: (0, 0, 4, 4),
        rotationDegrees: 90,
      );
      final image = lumaImageFromPlane(plane, maxDimension: 40)!;
      expect(image.width, 20);
      expect(image.height, 40);
      expect(image.getPixel(19, 0).r, 230);
      expect(image.getPixel(0, 0).r, 20);
    });

    test('converts bgra8888 to luminance', () {
      // Pure green pixels: Rec. 601 weight ~0.587.
      final bytes = Uint8List(4 * 4 * 4);
      for (var i = 0; i < bytes.length; i += 4) {
        bytes[i + 1] = 255; // G
        bytes[i + 3] = 255; // A
      }
      final image = lumaImageFromPlane(
        LivePlane(
          bytes: bytes,
          width: 4,
          height: 4,
          bytesPerRow: 16,
          format: LivePlaneFormat.bgra8888,
          rotationDegrees: 0,
        ),
        maxDimension: 4,
      )!;
      expect(image.getPixel(0, 0).r, closeTo(0.587 * 255, 2));
    });

    test('returns null for a buffer shorter than its declared geometry', () {
      final image = lumaImageFromPlane(
        LivePlane(
          bytes: Uint8List(10),
          width: 100,
          height: 100,
          bytesPerRow: 100,
          format: LivePlaneFormat.luma8,
          rotationDegrees: 0,
        ),
        maxDimension: 50,
      );
      expect(image, isNull);
    });
  });

  group('detectDocumentBoundary on a live plane', () {
    test('finds a card in a rotated landscape sensor frame, upright', () {
      // Sensor frame 640x480 (landscape). The card spans x 200..440 and
      // y 90..390 in sensor space — i.e. it is taller than wide there, and
      // wider than tall once rotated upright into a 480x640 portrait frame.
      final plane = _lumaPlaneWithRect(
        width: 640,
        height: 480,
        rect: (200, 90, 440, 390),
        rotationDegrees: 90,
      );
      final gray = lumaImageFromPlane(plane, maxDimension: 320)!;
      final detection = detectDocumentBoundary(
        gray,
        maxAnalysisDimension: 320,
      )!;

      expect(detection.imageAspectRatio, closeTo(480 / 640, 0.01));
      // Rotating 90 degrees clockwise maps sensor (x, y) to upright
      // (H - y, x): sensor y 90..390 becomes upright x 90..390 of 480.
      expect(detection.quad.topLeft.x, closeTo(90 / 480, 0.03));
      expect(detection.quad.bottomRight.x, closeTo(390 / 480, 0.03));
      expect(detection.quad.topLeft.y, closeTo(200 / 640, 0.03));
      expect(detection.quad.bottomRight.y, closeTo(440 / 640, 0.03));
      expect(detection.estimatedAspectRatio, closeTo(300 / 240, 0.08));
    });
  });
}
