import 'package:meta/meta.dart';

/// Structured reason a capture flow failed.
///
/// Hosts should switch on this enum rather than parsing [SmartCaptureException.message],
/// which is intended for developer logs and may be reworded at any time.
enum SmartCaptureErrorCode {
  /// The user dismissed the capture screen without producing a result.
  ///
  /// Not an error in the usual sense; surfaced so the host can distinguish a
  /// deliberate cancel from a failure.
  cancelled,

  /// Camera permission was denied for this request.
  cameraPermissionDenied,

  /// Camera permission was denied and the OS will not prompt again. The host
  /// must send the user to system settings.
  cameraPermissionPermanentlyDenied,

  /// No usable camera was reported by the platform.
  cameraUnavailable,

  /// The camera was acquired but failed during preview or capture.
  cameraFailure,

  /// The high-resolution still could not be captured or decoded.
  captureFailed,

  /// Perspective correction could not produce a rectified image, typically
  /// because the four corners were never located with enough confidence.
  rectificationFailed,

  /// No OCR engine was available for the requested script on this platform.
  ///
  /// The canonical case is Arabic on Android with the Tesseract engine
  /// excluded from the build.
  ocrEngineUnavailable,

  /// The OCR engine was reached but failed to process the image.
  ocrFailed,

  /// The requested document profile is not registered.
  unknownDocumentProfile,

  /// The supplied options are internally inconsistent, e.g. a minimum
  /// threshold above the corresponding maximum.
  invalidOptions,

  /// The platform reported a failure that does not map to any case above.
  /// Inspect [SmartCaptureException.cause] for detail.
  platformError,
}

/// Error thrown by every `SmartCapture` entry point.
@immutable
class SmartCaptureException implements Exception {
  const SmartCaptureException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  /// Machine-readable reason. Switch on this.
  final SmartCaptureErrorCode code;

  /// Developer-facing description. Never contains OCR text, field values or
  /// any other personal data — see the privacy notes in the README.
  final String message;

  /// The underlying platform error, when there was one.
  final Object? cause;

  final StackTrace? stackTrace;

  /// Whether the host can reasonably offer the user a retry.
  ///
  /// Permission denials and unknown profiles are configuration problems that a
  /// retry cannot fix; transient capture and OCR failures often clear on a
  /// second attempt.
  bool get isRetryable => switch (code) {
        SmartCaptureErrorCode.cameraFailure ||
        SmartCaptureErrorCode.captureFailed ||
        SmartCaptureErrorCode.rectificationFailed ||
        SmartCaptureErrorCode.ocrFailed =>
          true,
        _ => false,
      };

  @override
  String toString() =>
      'SmartCaptureException(${code.name}: $message${cause == null ? '' : ' | cause: $cause'})';
}
