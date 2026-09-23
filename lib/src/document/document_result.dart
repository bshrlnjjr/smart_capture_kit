import 'package:meta/meta.dart';

import '../common/capture_image.dart';
import '../common/geometry.dart';
import '../common/quality.dart';
import '../extraction/field_models.dart';
import '../ocr/ocr_models.dart';

/// Everything captured and computed for one side of a document.
@immutable
class DocumentSideCapture {
  const DocumentSideCapture({
    required this.side,
    required this.originalImage,
    required this.qualityReport,
    this.rectifiedImage,
    this.detectedCorners,
    this.ocr,
    this.userContinuedDespiteFailures = false,
  });

  final DocumentSide side;

  /// The frame exactly as captured, with no geometric correction.
  final CaptureImage originalImage;

  /// The perspective-corrected card, cropped to its detected boundary.
  ///
  /// `null` when correction was disabled, or when the four corners were never
  /// located confidently enough to warp from. A `null` here with a present
  /// [originalImage] is a normal outcome, not an error.
  final CaptureImage? rectifiedImage;

  /// Corners located in [originalImage], in normalized coordinates.
  final Quad? detectedCorners;

  /// Checks run against the full-resolution capture.
  final QualityReport qualityReport;

  /// Raw OCR for this side, when OCR was requested and succeeded.
  final OcrPageResult? ocr;

  final bool userContinuedDespiteFailures;

  Future<void> dispose() async {
    await originalImage.delete();
    await rectifiedImage?.delete();
  }

  @override
  String toString() => 'DocumentSideCapture(${side.name}, '
      'rectified=${rectifiedImage != null}, ocr=${ocr != null})';
}

/// Result of a completed document capture.
@immutable
class DocumentCaptureResult {
  const DocumentCaptureResult({
    required this.profileId,
    required this.front,
    this.back,
    this.fields,
  });

  /// Profile used for capture guidance and extraction.
  final String profileId;

  final DocumentSideCapture front;

  /// The back capture, when [DocumentSides.frontAndBack] was requested.
  final DocumentSideCapture? back;

  /// Structured fields, when the profile defines a mapping and OCR ran.
  ///
  /// `null` when OCR was disabled. An empty field set — as opposed to `null` —
  /// means the profile ran but declares no fields yet, which is the current
  /// state of every shipped profile. See
  /// `doc/decisions/0001-ocr-engine-selection.md`.
  final ExtractedFieldSet? fields;

  /// Whether any field needs human review before use.
  bool get hasFieldsNeedingReview => fields?.hasFieldsNeedingReview ?? false;

  /// Whether every quality check that ran, on every captured side, passed.
  bool get allEvaluatedChecksPassed =>
      front.qualityReport.allEvaluatedChecksPassed &&
      (back?.qualityReport.allEvaluatedChecksPassed ?? true);

  /// Returns a copy with [field] replacing its current entry.
  ///
  /// Used by the review flow to record a manual correction without mutating
  /// the original result.
  DocumentCaptureResult withCorrectedField(ExtractedField field) {
    final current = fields;
    if (current == null) return this;
    return DocumentCaptureResult(
      profileId: profileId,
      front: front,
      back: back,
      fields: current.withField(field),
    );
  }

  /// Deletes every image file across every side.
  Future<void> dispose() async {
    await front.dispose();
    await back?.dispose();
  }

  @override
  String toString() => 'DocumentCaptureResult($profileId, '
      'back=${back != null}, fields=${fields?.fields.length ?? 0})';
}
