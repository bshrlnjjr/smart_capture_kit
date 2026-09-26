import '../common/errors.dart';
import '../ocr/ocr_engine.dart';
import '../ocr/ocr_models.dart';
import 'document_profile.dart';
import 'document_result.dart';

/// Runs OCR over every captured side of [capture] and then [profile]'s field
/// extractor, returning a copy of [capture] with the results attached.
///
/// - Each side is read from its rectified image when one exists — perspective
///   correction materially improves recognition — and from the original
///   otherwise.
/// - The engine is asked only for the profile's scripts it can actually read
///   on this device. Every page records what was requested
///   ([OcrPageResult.requestedScripts]), so a field missing because its
///   script was never read (Arabic on Android today) is distinguishable from
///   one missing because it was not printed.
/// - An OCR failure never discards the capture: the images and quality
///   reports are returned with [DocumentCaptureResult.ocrError] set and no
///   OCR or fields.
Future<DocumentCaptureResult> runDocumentOcr({
  required DocumentCaptureResult capture,
  required DocumentProfile profile,
  required OcrEngine engine,
}) async {
  try {
    final supported = await engine.supportedScripts();
    final scripts = [
      for (final script in profile.expectedScripts)
        if (supported.contains(script)) script,
    ];
    if (scripts.isEmpty) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.ocrEngineUnavailable,
        message: '${engine.descriptor.displayName} cannot read any script '
            'profile "${profile.id}" expects '
            '(${profile.expectedScripts.map((s) => s.name).join(', ')}).',
      );
    }

    Future<DocumentSideCapture> read(DocumentSideCapture side) async {
      final page = await engine.recognize(OcrRequest(
        image: side.rectifiedImage ?? side.originalImage,
        side: side.side,
        scripts: scripts,
      ));
      return side.withOcr(page);
    }

    final front = await read(capture.front);
    final back = capture.back == null ? null : await read(capture.back!);
    final fields = profile.extractor.extract(
      profileId: profile.id,
      front: front.ocr,
      back: back?.ocr,
    );
    return DocumentCaptureResult(
      profileId: capture.profileId,
      front: front,
      back: back,
      fields: fields,
    );
  } catch (e) {
    return DocumentCaptureResult(
      profileId: capture.profileId,
      front: capture.front,
      back: capture.back,
      ocrError: e is SmartCaptureException
          ? e
          : SmartCaptureException(
              code: SmartCaptureErrorCode.ocrFailed,
              message: 'Text recognition failed.',
              cause: e,
            ),
    );
  }
}
