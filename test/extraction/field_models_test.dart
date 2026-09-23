import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

void main() {
  const evidence = FieldEvidence(
    side: DocumentSide.front,
    sourceText: '٩٩٠١٢٣٤٥٦٧',
    boundingBoxes: [
      NormalizedRect(left: 0.1, top: 0.4, right: 0.5, bottom: 0.45),
    ],
    ocrConfidence: 0.42,
    matchedLabel: 'الرقم الوطني',
  );

  group('ExtractedField', () {
    test('missing carries no value and needs review', () {
      const field = ExtractedField.missing(DocumentFieldId.dateOfBirth);
      expect(field.status, FieldStatus.missing);
      expect(field.value, isNull);
      expect(field.needsReview, isTrue);
    });

    test('uncertain fields need review, recognized ones do not', () {
      const uncertain = ExtractedField(
        id: DocumentFieldId.nationalIdNumber,
        status: FieldStatus.uncertain,
        value: '9901234567',
        uncertaintyReasons: [FieldUncertaintyReason.lowOcrConfidence],
      );
      const recognized = ExtractedField(
        id: DocumentFieldId.nationalIdNumber,
        status: FieldStatus.recognized,
        value: '9901234567',
      );
      expect(uncertain.needsReview, isTrue);
      expect(recognized.needsReview, isFalse);
    });

    test('manual correction preserves the raw value and the evidence', () {
      const field = ExtractedField(
        id: DocumentFieldId.nationalIdNumber,
        status: FieldStatus.uncertain,
        value: '9901234S67',
        rawValue: '٩٩٠١٢٣٤S٦٧',
        evidence: evidence,
        uncertaintyReasons: [FieldUncertaintyReason.ambiguousCharacters],
      );

      final corrected = field.withManualCorrection('9901234567');

      expect(corrected.status, FieldStatus.manuallyCorrected);
      expect(corrected.value, '9901234567');
      // What the document actually showed survives the correction.
      expect(corrected.rawValue, '٩٩٠١٢٣٤S٦٧');
      expect(corrected.evidence, same(evidence));
      expect(corrected.uncertaintyReasons, isEmpty);
      expect(corrected.needsReview, isFalse);
    });

    test('correction does not mutate the original field', () {
      const field = ExtractedField(
        id: DocumentFieldId.dateOfBirth,
        status: FieldStatus.uncertain,
        value: '1990-01-02',
      );
      field.withManualCorrection('1990-02-01');
      expect(field.value, '1990-01-02');
      expect(field.status, FieldStatus.uncertain);
    });
  });

  group('FieldEvidence', () {
    test('enclosingBox unions every box', () {
      const multi = FieldEvidence(
        side: DocumentSide.back,
        sourceText: 'two lines',
        boundingBoxes: [
          NormalizedRect(left: 0.1, top: 0.2, right: 0.4, bottom: 0.25),
          NormalizedRect(left: 0.15, top: 0.3, right: 0.6, bottom: 0.35),
        ],
      );
      final box = multi.enclosingBox!;
      expect(box.left, 0.1);
      expect(box.top, 0.2);
      expect(box.right, 0.6);
      expect(box.bottom, 0.35);
    });

    test('enclosingBox is null when there are no boxes', () {
      const empty = FieldEvidence(
        side: DocumentSide.front,
        sourceText: '',
        boundingBoxes: [],
      );
      expect(empty.enclosingBox, isNull);
    });
  });

  group('ExtractedFieldSet', () {
    final set = ExtractedFieldSet(
      profileId: 'test_profile',
      fields: const [
        ExtractedField(
          id: DocumentFieldId.fullNameArabic,
          status: FieldStatus.recognized,
          value: 'محمد',
        ),
        ExtractedField(
          id: DocumentFieldId.nationalIdNumber,
          status: FieldStatus.uncertain,
          value: '990123456',
          uncertaintyReasons: [FieldUncertaintyReason.failedFormatValidation],
        ),
        ExtractedField.missing(DocumentFieldId.expiryDate),
      ],
    );

    test('lookup by id', () {
      expect(set[DocumentFieldId.fullNameArabic]?.value, 'محمد');
      expect(set[DocumentFieldId.sex], isNull);
    });

    test('reports uncertain and missing fields as needing review', () {
      expect(
        set.fieldsNeedingReview.map((f) => f.id),
        containsAll([
          DocumentFieldId.nationalIdNumber,
          DocumentFieldId.expiryDate,
        ]),
      );
      expect(set.hasFieldsNeedingReview, isTrue);
    });

    test('withField replaces by id and leaves the rest alone', () {
      final updated = set.withField(
        set[DocumentFieldId.nationalIdNumber]!
            .withManualCorrection('9901234567'),
      );
      expect(updated.fields, hasLength(3));
      expect(updated[DocumentFieldId.nationalIdNumber]!.value, '9901234567');
      expect(
        updated[DocumentFieldId.nationalIdNumber]!.status,
        FieldStatus.manuallyCorrected,
      );
      expect(updated[DocumentFieldId.fullNameArabic]!.value, 'محمد');
      // The original set is untouched.
      expect(set[DocumentFieldId.nationalIdNumber]!.value, '990123456');
    });
  });
}
