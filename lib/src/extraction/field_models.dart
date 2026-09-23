import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../ocr/ocr_models.dart';

/// A field a document profile may define.
///
/// A profile declares which of these it supports. A field absent from a
/// profile is never guessed at, and a field a profile declares but the OCR did
/// not find is reported as [FieldStatus.missing] rather than omitted.
enum DocumentFieldId {
  fullNameArabic,
  fullNameLatin,
  givenNameArabic,
  givenNameLatin,
  familyNameArabic,
  familyNameLatin,
  nationalIdNumber,
  documentNumber,
  dateOfBirth,
  sex,
  nationality,
  placeOfBirth,
  issueDate,
  expiryDate,
  issuingAuthority,
}

/// How much the pipeline trusts an extracted value.
enum FieldStatus {
  /// A value was found and passed the profile's validation rules with
  /// sufficient confidence.
  recognized,

  /// A value was found but something is off: low OCR confidence, a failed
  /// format check, an ambiguous character, or several equally plausible
  /// candidates. The value is provided so a user can correct it, and must not
  /// be used without review.
  uncertain,

  /// The profile declares this field but no candidate was found. [ExtractedField.value]
  /// is `null`. The pipeline never fabricates a plausible value to fill a gap.
  missing,

  /// A human replaced the extracted value through the review flow.
  manuallyCorrected,
}

/// Why a field ended up [FieldStatus.uncertain].
///
/// Reported so a review screen can explain itself rather than showing a bare
/// warning icon.
enum FieldUncertaintyReason {
  /// The engine's confidence fell below the profile's floor.
  lowOcrConfidence,

  /// The value did not match the expected format, e.g. a national ID with the
  /// wrong digit count.
  failedFormatValidation,

  /// A date parsed to a calendar value that cannot be right, such as an expiry
  /// before an issue date.
  implausibleDate,

  /// More than one candidate matched equally well.
  ambiguousCandidates,

  /// Characters that the script confuses routinely were present, and the
  /// pipeline declined to pick one silently.
  ambiguousCharacters,

  /// The field's label was found but no value could be associated with it.
  labelWithoutValue,

  /// The region holding the field was flagged by a quality check, e.g. glare.
  degradedSourceRegion,
}

/// Where an extracted value came from.
///
/// Evidence exists so that nothing in the result is unattributable. A host can
/// draw the box on the image, show the exact source text, and let a reviewer
/// judge for themselves.
@immutable
class FieldEvidence {
  const FieldEvidence({
    required this.side,
    required this.sourceText,
    required this.boundingBoxes,
    this.ocrConfidence,
    this.matchedLabel,
  });

  final DocumentSide side;

  /// The exact OCR text the value was derived from, unnormalized.
  final String sourceText;

  /// One or more boxes covering the source text.
  ///
  /// A list rather than a single box because a value may span several lines,
  /// and because cursive right-to-left text is often split into non-adjacent
  /// runs by the recognizer.
  final List<NormalizedRect> boundingBoxes;

  final double? ocrConfidence;

  /// The printed label this value was matched against, when the profile used
  /// label-based mapping. `null` when the value was located by position or
  /// format instead.
  final String? matchedLabel;

  /// A single box enclosing all of [boundingBoxes], for a simple highlight.
  NormalizedRect? get enclosingBox {
    if (boundingBoxes.isEmpty) return null;
    return boundingBoxes.reduce((a, b) => a.union(b));
  }

  @override
  String toString() => 'FieldEvidence(${side.name}, '
      '${boundingBoxes.length} boxes, conf=$ocrConfidence)';
}

/// One field extracted from a document.
@immutable
class ExtractedField {
  const ExtractedField({
    required this.id,
    required this.status,
    this.value,
    this.rawValue,
    this.evidence,
    this.uncertaintyReasons = const [],
    this.confidence,
  });

  /// A field the profile declares but the pipeline did not find.
  const ExtractedField.missing(this.id)
      : status = FieldStatus.missing,
        value = null,
        rawValue = null,
        evidence = null,
        uncertaintyReasons = const [],
        confidence = null;

  final DocumentFieldId id;

  final FieldStatus status;

  /// The value after the profile's normalization and validation, or `null`
  /// when [status] is [FieldStatus.missing].
  ///
  /// For a date this is an ISO-8601 `yyyy-MM-dd` string. For a name it is the
  /// OCR text with surrounding whitespace removed and nothing else changed.
  final String? value;

  /// The exact OCR substring before any normalization.
  ///
  /// Differs from [value] whenever digits were converted or whitespace was
  /// collapsed. Kept so a reviewer can see what was actually printed.
  final String? rawValue;

  final FieldEvidence? evidence;

  /// Why this field is uncertain. Empty unless [status] is
  /// [FieldStatus.uncertain].
  final List<FieldUncertaintyReason> uncertaintyReasons;

  /// Combined confidence in `[0, 1]`, folding OCR confidence together with how
  /// well the value matched the profile's expectations. `null` when the engine
  /// reported no confidence and the profile defines no scoring rule.
  final double? confidence;

  bool get needsReview =>
      status == FieldStatus.uncertain || status == FieldStatus.missing;

  /// Returns a copy marked [FieldStatus.manuallyCorrected] with [newValue].
  ///
  /// [rawValue] and [evidence] are carried through unchanged, so a correction
  /// never erases what the document actually showed.
  ExtractedField withManualCorrection(String newValue) => ExtractedField(
        id: id,
        status: FieldStatus.manuallyCorrected,
        value: newValue,
        rawValue: rawValue,
        evidence: evidence,
        uncertaintyReasons: const [],
        confidence: null,
      );

  @override
  String toString() =>
      'ExtractedField(${id.name}: ${status.name}, hasValue=${value != null})';
}

/// All fields a profile produced for one document.
@immutable
class ExtractedFieldSet {
  const ExtractedFieldSet({
    required this.profileId,
    required this.fields,
  });

  /// The document profile that performed the extraction.
  final String profileId;

  final List<ExtractedField> fields;

  ExtractedField? operator [](DocumentFieldId id) {
    for (final f in fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<ExtractedField> get fieldsNeedingReview =>
      fields.where((f) => f.needsReview).toList();

  bool get hasFieldsNeedingReview => fieldsNeedingReview.isNotEmpty;

  /// Returns a copy with [field] replacing the existing entry for its id.
  ExtractedFieldSet withField(ExtractedField field) => ExtractedFieldSet(
        profileId: profileId,
        fields: [
          for (final f in fields)
            if (f.id == field.id) field else f,
        ],
      );

  @override
  String toString() => 'ExtractedFieldSet($profileId, ${fields.length} fields, '
      '${fieldsNeedingReview.length} need review)';
}
