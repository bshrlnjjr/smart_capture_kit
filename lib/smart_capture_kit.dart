/// Guided portrait and identity-card capture for Flutter, with on-device
/// quality checks and OCR field extraction.
///
/// See `SmartCapture` for the entry points, and the README for platform setup
/// and privacy notes.
library;

export 'src/common/capture_image.dart';
export 'src/common/errors.dart';
export 'src/common/geometry.dart';
export 'src/common/guidance.dart';
export 'src/common/labels.dart';
export 'src/common/quality.dart';
export 'src/document/document_options.dart';
export 'src/document/document_profile.dart';
export 'src/document/document_result.dart';
export 'src/extraction/field_models.dart';
export 'src/ocr/ocr_engine.dart';
export 'src/ocr/ocr_models.dart';
export 'src/ocr/text_normalization.dart';
export 'src/portrait/portrait_options.dart';
export 'src/portrait/portrait_result.dart';
export 'src/smart_capture.dart';
