import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../common/capture_image.dart';
import '../common/geometry.dart';
import '../common/image_metrics.dart';
import '../common/temp_files.dart';
import 'document_boundary_detection.dart';
import 'document_rectification.dart';

/// Decoded dimensions, boundary detection and [ImageMetrics] for one
/// full-resolution document capture — everything the final analysis pass
/// needs, computed in a single background-isolate decode.
class DocumentDecodedInfo {
  const DocumentDecodedInfo({
    required this.width,
    required this.height,
    required this.metrics,
    required this.detection,
  });

  final int width;
  final int height;
  final ImageMetrics metrics;
  final DocumentBoundaryDetection? detection;
}

class _DecodeRequest {
  const _DecodeRequest(this.path);
  final String path;
}

/// Decodes the image at [path], detects its document boundary and computes
/// [ImageMetrics], entirely on a background isolate.
Future<DocumentDecodedInfo> decodeAndAnalyzeDocument(String path) =>
    compute(_decodeAndAnalyzeWorker, _DecodeRequest(path));

DocumentDecodedInfo _decodeAndAnalyzeWorker(_DecodeRequest request) {
  final bytes = File(request.path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw FormatException('Could not decode image at ${request.path}');
  }
  return DocumentDecodedInfo(
    width: image.width,
    height: image.height,
    metrics: computeImageMetrics(image),
    detection: detectDocumentBoundary(image),
  );
}

class _RectifyRequest {
  const _RectifyRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.quad,
    required this.outputWidth,
    required this.outputHeight,
    required this.glareLuminanceThreshold,
  });

  final String sourcePath;
  final String outputPath;
  final Quad quad;
  final int outputWidth;
  final int outputHeight;
  final double glareLuminanceThreshold;
}

class _RectifyOutcome {
  const _RectifyOutcome({
    required this.width,
    required this.height,
    required this.glareFraction,
  });
  final int width;
  final int height;
  final double glareFraction;
}

/// Result of a successful rectification: the corrected image plus glare
/// measured on it.
class DocumentRectificationResult {
  const DocumentRectificationResult({
    required this.image,
    required this.glareFraction,
  });
  final CaptureImage image;
  final double glareFraction;
}

/// Perspective-corrects [sourcePath] using [quad], writing the result to a
/// new file in the plugin's temporary directory, and measures glare on the
/// corrected image in the same background-isolate pass.
///
/// Returns `null` when [quad] could not be inverted to a perspective map —
/// see [rectifyDocument] — in which case the caller keeps the original image
/// only, exactly as [DocumentSideCapture.rectifiedImage] documents.
Future<DocumentRectificationResult?> produceDocumentRectification({
  required String sourcePath,
  required Quad quad,
  required double aspectRatio,
  required double glareLuminanceThreshold,
  int targetLongEdge = 1400,
}) async {
  final outputWidth = aspectRatio >= 1 ? targetLongEdge : (targetLongEdge * aspectRatio).round();
  final outputHeight = aspectRatio >= 1 ? (targetLongEdge / aspectRatio).round() : targetLongEdge;

  final outputPath = await SmartCaptureTempFiles.newFilePath('document_rectified');
  final outcome = await compute(
    _rectifyWorker,
    _RectifyRequest(
      sourcePath: sourcePath,
      outputPath: outputPath,
      quad: quad,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      glareLuminanceThreshold: glareLuminanceThreshold,
    ),
  );
  if (outcome == null) return null;

  return DocumentRectificationResult(
    image: CaptureImage(
      path: outputPath,
      kind: CaptureImageKind.rectified,
      width: outcome.width,
      height: outcome.height,
    ),
    glareFraction: outcome.glareFraction,
  );
}

_RectifyOutcome? _rectifyWorker(_RectifyRequest request) {
  final bytes = File(request.sourcePath).readAsBytesSync();
  final source = img.decodeImage(bytes);
  if (source == null) return null;

  final rectified = rectifyDocument(
    source: source,
    quad: request.quad,
    outputWidth: request.outputWidth,
    outputHeight: request.outputHeight,
  );
  if (rectified == null) return null;

  File(request.outputPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodeJpg(rectified, quality: 92));

  return _RectifyOutcome(
    width: rectified.width,
    height: rectified.height,
    glareFraction: computeGlareFraction(
      rectified,
      luminanceThreshold: request.glareLuminanceThreshold,
    ),
  );
}
