import 'package:meta/meta.dart';

import '../extraction/field_models.dart';
import '../ocr/ocr_models.dart';

/// Standard ID-1 card ratio (85.60 mm x 53.98 mm), used by most national ID
/// cards, driving licences and bank cards.
const double idCardAspectRatioId1 = 85.60 / 53.98;

/// ID-3 passport data page ratio (125 mm x 88 mm).
const double passportAspectRatioId3 = 125.0 / 88.0;

/// How complete a profile's field mapping is.
///
/// Exists so that "this profile reads text but does not yet map fields" is a
/// first-class, visible state rather than an empty result the host has to
/// interpret.
enum ProfileExtractionSupport {
  /// The profile guides capture and returns raw OCR, but defines no field
  /// mapping. Structured extraction returns an empty field set.
  rawTextOnly,

  /// The profile maps a subset of the fields printed on the document.
  partialFieldMapping,

  /// The profile maps every field it declares.
  fullFieldMapping,
}

/// Maps OCR output onto structured fields for one document type.
///
/// Implementations live behind this interface so a new document can be
/// supported by registering a profile, with no change to the capture or OCR
/// layers.
abstract class DocumentFieldExtractor {
  /// Extracts fields from the OCR of one or both sides.
  ///
  /// Must return a [ExtractedField] for every id in
  /// [DocumentProfile.declaredFields] — using [ExtractedField.missing] when
  /// nothing was found. Never omit a declared field, and never invent a value
  /// for one.
  ExtractedFieldSet extract({
    required String profileId,
    OcrPageResult? front,
    OcrPageResult? back,
  });
}

/// A [DocumentFieldExtractor] that maps nothing.
///
/// Used by profiles at [ProfileExtractionSupport.rawTextOnly]. Returns every
/// declared field as missing, which is accurate: no mapping has been defined,
/// so nothing was found.
class NoFieldExtractor implements DocumentFieldExtractor {
  const NoFieldExtractor(this.declaredFields);

  final List<DocumentFieldId> declaredFields;

  @override
  ExtractedFieldSet extract({
    required String profileId,
    OcrPageResult? front,
    OcrPageResult? back,
  }) =>
      ExtractedFieldSet(
        profileId: profileId,
        fields: [
          for (final id in declaredFields) ExtractedField.missing(id),
        ],
      );
}

/// Everything the plugin knows about one kind of document.
@immutable
class DocumentProfile {
  const DocumentProfile({
    required this.id,
    required this.displayName,
    required this.aspectRatio,
    required this.extractionSupport,
    required this.extractor,
    this.declaredFields = const [],
    this.expectedScripts = const [OcrScript.latin],
    this.hasBack = true,
    this.aspectRatioTolerance = 0.15,
    this.notes,
  });

  /// Stable identifier used in [DocumentCaptureOptions.documentProfile], e.g.
  /// `jo_national_id`.
  final String id;

  final String displayName;

  /// Expected width / height of the card.
  final double aspectRatio;

  /// How far a detected quad's ratio may deviate from [aspectRatio], as a
  /// fraction, before the aspect-ratio check warns.
  final double aspectRatioTolerance;

  /// Whether this document has a back side worth capturing.
  final bool hasBack;

  /// Scripts to ask the OCR engine for.
  ///
  /// Drives engine selection: a profile listing [OcrScript.arabic] routes to
  /// Apple Vision on iOS and Tesseract on Android.
  final List<OcrScript> expectedScripts;

  /// Fields this profile claims the document carries.
  ///
  /// Empty until real, redacted samples have been inspected. Declaring a field
  /// here is a claim that it is printed on the document, so the list stays
  /// empty rather than optimistic.
  final List<DocumentFieldId> declaredFields;

  final ProfileExtractionSupport extractionSupport;

  final DocumentFieldExtractor extractor;

  /// Free-text notes for developers, shown in documentation rather than UI.
  final String? notes;

  @override
  String toString() =>
      'DocumentProfile($id, ${extractionSupport.name}, '
      '${declaredFields.length} declared fields)';
}

/// The profiles the plugin knows about.
///
/// A host registers its own profile with [register] and then passes the id to
/// [DocumentCaptureOptions].
class DocumentProfileRegistry {
  DocumentProfileRegistry._();

  static final Map<String, DocumentProfile> _profiles = {
    genericIdCard.id: genericIdCard,
    jordanNationalId.id: jordanNationalId,
  };

  /// A profile for any ID-1 sized card, with no field mapping.
  ///
  /// The sensible default when you want guided capture, rectification and raw
  /// OCR without claiming to understand the document's layout.
  static const DocumentProfile genericIdCard = DocumentProfile(
    id: 'generic_id_card',
    displayName: 'Generic ID-1 card',
    aspectRatio: idCardAspectRatioId1,
    expectedScripts: [OcrScript.latin],
    extractionSupport: ProfileExtractionSupport.rawTextOnly,
    extractor: NoFieldExtractor([]),
    notes: 'Guided capture, perspective correction and raw OCR only. '
        'No field mapping is attempted for an unknown layout.',
  );

  /// Reference profile for the Jordanian national identity card.
  ///
  /// **Field mapping is deliberately not implemented.** The card is ID-1 sized
  /// and carries Arabic and Latin text, both of which are safe to state from
  /// the physical format alone. Which fields are printed, where they sit, and
  /// what their labels read cannot be encoded responsibly before legally
  /// obtained, redacted samples have been inspected — guessing a layout is how
  /// a pipeline starts reading the wrong number into the wrong field.
  ///
  /// Until then this profile guides capture, rectifies the card and returns
  /// complete raw OCR for both sides. [declaredFields] stays empty, so
  /// extraction reports nothing rather than reporting something wrong.
  static const DocumentProfile jordanNationalId = DocumentProfile(
    id: 'jo_national_id',
    displayName: 'Jordan national ID card',
    aspectRatio: idCardAspectRatioId1,
    expectedScripts: [OcrScript.arabic, OcrScript.latin],
    extractionSupport: ProfileExtractionSupport.rawTextOnly,
    extractor: NoFieldExtractor([]),
    notes: 'ID-1 format, Arabic and Latin script. Dates and the national '
        'number are printed in Western digits (confirmed by the project owner, '
        '2026-09-26). Field labels and layout intentionally undefined pending '
        'inspection of redacted samples; see '
        'doc/decisions/0001-ocr-engine-selection.md, open risk 5.',
  );

  /// All registered profiles.
  static List<DocumentProfile> get all => _profiles.values.toList();

  /// The profile with [id], or `null` when none is registered.
  static DocumentProfile? find(String id) => _profiles[id];

  /// Registers [profile], replacing any profile with the same id.
  static void register(DocumentProfile profile) {
    _profiles[profile.id] = profile;
  }
}
