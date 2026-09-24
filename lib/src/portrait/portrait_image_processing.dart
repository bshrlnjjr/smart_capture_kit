import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../common/capture_image.dart';
import '../common/geometry.dart';
import '../common/image_metrics.dart';
import '../common/temp_files.dart';

/// Decoded dimensions plus [ImageMetrics] for one image file.
///
/// A plain, `compute`-friendly value class: everything on it is a primitive,
/// so it can cross the isolate boundary without a custom codec.
class DecodedImageInfo {
  const DecodedImageInfo({
    required this.width,
    required this.height,
    required this.metrics,
  });

  final int width;
  final int height;
  final ImageMetrics metrics;
}

class _DecodeRequest {
  const _DecodeRequest(this.path);
  final String path;
}

/// Decodes the image at [path] and computes [ImageMetrics], entirely on a
/// background isolate.
///
/// This is the only place a full-resolution capture is decoded for analysis;
/// doing it once and reusing the result avoids paying the decode cost twice.
Future<DecodedImageInfo> decodeAndAnalyzeImage(String path) =>
    compute(_decodeAndAnalyzeWorker, _DecodeRequest(path));

DecodedImageInfo _decodeAndAnalyzeWorker(_DecodeRequest request) {
  final bytes = File(request.path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw FormatException('Could not decode image at ${request.path}');
  }
  return DecodedImageInfo(
    width: image.width,
    height: image.height,
    metrics: computeImageMetrics(image),
  );
}

/// Flips [path] horizontally in place, overwriting the file.
///
/// Exists to normalize away a real platform inconsistency rather than one
/// this package invented: `camera_avfoundation` leaves AVFoundation's default
/// `automaticallyAdjustsVideoMirroring` in effect for the still-photo
/// connection, so an iOS front-camera capture comes back mirrored by
/// default; `camera_android_camerax`'s `ImageCapture` use case never mirrors.
/// Without this, the same [PortraitCaptureOptions.mirrorFrontCameraOutput]
/// setting would produce opposite results on the two platforms.
Future<void> flipHorizontalInPlace(String path) =>
    compute(_flipWorker, path);

void _flipWorker(String path) {
  final bytes = File(path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) return;
  final flipped = img.flipHorizontal(image);
  File(path).writeAsBytesSync(img.encodeJpg(flipped, quality: 95));
}

class _CropRequest {
  const _CropRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.faceBox,
    required this.aspectRatio,
    required this.paddingFactor,
  });

  final String sourcePath;
  final String outputPath;
  final NormalizedRect faceBox;
  final double? aspectRatio;
  final double paddingFactor;
}

class _CropOutcome {
  const _CropOutcome(this.width, this.height);
  final int width;
  final int height;
}

/// Crops [sourcePath] to [faceBox] plus padding, optionally forced to
/// [aspectRatio], and writes the result to a new file in the plugin's
/// temporary directory.
///
/// Returns `null` if the computed crop rectangle would be degenerate (e.g. a
/// face box right at the image edge with no room to pad) — callers should
/// treat that the same as "no cropped image was produced" rather than as an
/// error, since the original image is always still available.
Future<CaptureImage?> producePortraitCrop({
  required String sourcePath,
  required NormalizedRect faceBox,
  double? aspectRatio,
  double paddingFactor = 0.6,
}) async {
  final outputPath = await SmartCaptureTempFiles.newFilePath('portrait_cropped');
  final outcome = await compute(
    _cropWorker,
    _CropRequest(
      sourcePath: sourcePath,
      outputPath: outputPath,
      faceBox: faceBox,
      aspectRatio: aspectRatio,
      paddingFactor: paddingFactor,
    ),
  );
  if (outcome == null) return null;
  return CaptureImage(
    path: outputPath,
    kind: CaptureImageKind.cropped,
    width: outcome.width,
    height: outcome.height,
  );
}

_CropOutcome? _cropWorker(_CropRequest request) {
  final bytes = File(request.sourcePath).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final width = image.width.toDouble();
  final height = image.height.toDouble();

  final faceLeft = request.faceBox.left * width;
  final faceTop = request.faceBox.top * height;
  final faceWidth = request.faceBox.width * width;
  final faceHeight = request.faceBox.height * height;

  // Pad symmetrically around the face box first, in source pixels.
  var cropLeft = faceLeft - faceWidth * request.paddingFactor;
  var cropTop = faceTop - faceHeight * request.paddingFactor * 1.4; // more headroom above
  var cropRight = faceLeft + faceWidth + faceWidth * request.paddingFactor;
  var cropBottom = faceTop + faceHeight + faceHeight * request.paddingFactor * 1.8; // shoulders

  // Then force the requested aspect ratio by growing the shorter dimension
  // around its own center, never by shrinking — shrinking could cut into the
  // face the padding above was meant to protect.
  final targetRatio = request.aspectRatio;
  if (targetRatio != null && targetRatio > 0) {
    final cropWidth = cropRight - cropLeft;
    final cropHeight = cropBottom - cropTop;
    final currentRatio = cropWidth / cropHeight;
    if (currentRatio < targetRatio) {
      final neededWidth = cropHeight * targetRatio;
      final delta = (neededWidth - cropWidth) / 2;
      cropLeft -= delta;
      cropRight += delta;
    } else if (currentRatio > targetRatio) {
      final neededHeight = cropWidth / targetRatio;
      final delta = (neededHeight - cropHeight) / 2;
      cropTop -= delta;
      cropBottom += delta;
    }
  }

  // Clamp to the source image. Clamping can reintroduce a slightly wrong
  // aspect ratio at the frame edges; that is an acceptable tradeoff against
  // fabricating pixels that were not captured.
  cropLeft = cropLeft.clamp(0, width);
  cropTop = cropTop.clamp(0, height);
  cropRight = cropRight.clamp(0, width);
  cropBottom = cropBottom.clamp(0, height);

  final outWidth = (cropRight - cropLeft).round();
  final outHeight = (cropBottom - cropTop).round();
  if (outWidth < 16 || outHeight < 16) return null;

  final cropped = img.copyCrop(
    image,
    x: cropLeft.round(),
    y: cropTop.round(),
    width: outWidth,
    height: outHeight,
  );

  File(request.outputPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodeJpg(cropped, quality: 92));

  return _CropOutcome(cropped.width, cropped.height);
}
