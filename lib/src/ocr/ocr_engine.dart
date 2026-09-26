import 'package:meta/meta.dart';

import '../common/capture_image.dart';
import 'ocr_models.dart';

/// One image handed to an [OcrEngine] for recognition.
@immutable
class OcrRequest {
  const OcrRequest({
    required this.image,
    required this.side,
    required this.scripts,
  });

  /// The image to read. Normally the rectified document image, because
  /// perspective correction materially improves recognition.
  final CaptureImage image;

  final DocumentSide side;

  /// Scripts to look for. An engine that cannot handle a requested script must
  /// throw rather than quietly return Latin-only results.
  final List<OcrScript> scripts;
}

/// Contract for a text recognition backend.
///
/// The plugin ships [NativeOcrEngine]: Apple Vision on iOS and ML Kit (Latin
/// only, for now) on Android. A host may supply its own — typically a cloud
/// adapter backed by its own server — and pass it through
/// [DocumentCaptureOptions.ocrEngineOverride].
///
/// ## Implementing a cloud adapter
///
/// The plugin deliberately ships no cloud implementation and stores no
/// credentials. If your adapter sends image data off the device, its
/// [descriptor] must report `isOffDevice: true`. The host application is
/// responsible for disclosing that to the user before capture, and for the
/// legal basis of the transfer.
abstract class OcrEngine {
  /// Identifies this engine in results.
  OcrEngineDescriptor get descriptor;

  /// Scripts this engine can recognize on the current platform.
  ///
  /// Queried at runtime rather than declared statically, because availability
  /// is platform- and version-dependent. Apple Vision, for example, exposes
  /// Arabic only through request revision 3 at the accurate recognition level.
  Future<Set<OcrScript>> supportedScripts();

  /// Recognizes text in [request].
  ///
  /// Throws [SmartCaptureException] with
  /// [SmartCaptureErrorCode.ocrEngineUnavailable] when a requested script is
  /// unsupported, and [SmartCaptureErrorCode.ocrFailed] on processing errors.
  Future<OcrPageResult> recognize(OcrRequest request);

  /// Releases native resources. Safe to call more than once.
  Future<void> dispose() async {}
}
