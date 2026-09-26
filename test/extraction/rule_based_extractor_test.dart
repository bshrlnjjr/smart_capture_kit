import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

/// Rules for the synthetic benchmark card in tool/ocr_benchmark — a made-up
/// layout, not any real document's.
final List<FieldRule> _syntheticCardRules = [
  const FieldRule(
    field: DocumentFieldId.fullNameArabic,
    labels: ['الاسم'],
    kind: FieldValueKind.text,
    script: OcrScript.arabic,
  ),
  const FieldRule(
    field: DocumentFieldId.fullNameLatin,
    labels: ['Name'],
    kind: FieldValueKind.text,
    script: OcrScript.latin,
  ),
  const FieldRule(
    field: DocumentFieldId.dateOfBirth,
    labels: ['تاريخ الولادة', 'Date of Birth'],
    kind: FieldValueKind.date,
    dateMeaning: DateMeaning.past,
  ),
  const FieldRule(
    field: DocumentFieldId.placeOfBirth,
    labels: ['مكان الولادة'],
    kind: FieldValueKind.text,
    script: OcrScript.arabic,
  ),
  const FieldRule(
    field: DocumentFieldId.sex,
    labels: ['الجنس', 'Sex'],
    kind: FieldValueKind.choice,
    allowedValues: {'ذكر': 'M', 'أنثى': 'F', 'M': 'M', 'F': 'F'},
  ),
  const FieldRule(
    field: DocumentFieldId.expiryDate,
    labels: ['Expiry'],
    kind: FieldValueKind.date,
    dateOrder: DateOrder.yearMonthDay,
  ),
  const FieldRule(
    field: DocumentFieldId.nationalIdNumber,
    labels: ['الرقم الوطني', 'National No.'],
    kind: FieldValueKind.number,
    exactDigitCount: 10,
  ),
];

RuleBasedFieldExtractor _extractor({double confidenceFloor = 0.5}) =>
    RuleBasedFieldExtractor(
      rules: _syntheticCardRules,
      confidenceFloor: confidenceFloor,
      clock: () => DateTime.utc(2026, 9, 26),
    );

/// One OCR page with one line per entry, stacked top to bottom.
OcrPageResult _page(
  List<String> lines, {
  DocumentSide side = DocumentSide.front,
  List<double?>? confidences,
  List<NormalizedRect>? boxes,
}) {
  final ocrLines = [
    for (var i = 0; i < lines.length; i++)
      OcrLine(
        text: lines[i],
        boundingBox: boxes?[i] ??
            NormalizedRect(
              left: 0.1,
              top: 0.05 + i * 0.08,
              right: 0.9,
              bottom: 0.11 + i * 0.08,
            ),
        confidence: confidences?[i],
      ),
  ];
  return OcrPageResult(
    side: side,
    rawText: lines.join('\n'),
    blocks: [
      OcrBlock(
        text: lines.join('\n'),
        boundingBox: const NormalizedRect(left: 0, top: 0, right: 1, bottom: 1),
        lines: ocrLines,
      ),
    ],
    engine: const OcrEngineDescriptor(
      id: 'test',
      displayName: 'Test',
      isOffDevice: false,
    ),
    requestedScripts: const [OcrScript.arabic, OcrScript.latin],
  );
}

ExtractedField _field(ExtractedFieldSet set, DocumentFieldId id) => set[id]!;

void main() {
  group('RuleBasedFieldExtractor on recorded engine output', () {
    test('Apple Vision, clean card: every field recognized', () {
      // Verbatim Vision output for benchmark card00_clean.
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page([
          'SYNTHETIC TEST CARD - NOT A REAL DOCUMENT',
          'الاسم: رنا رنا الزعبي',
          'تاريخ الولادة: ١٥/٠٤/١٩٨٧',
          'مكان الولادة: العقبة',
          'الجنس: أنثى',
          'Name: Rana Rana Alzoubi',
          'Date of Birth: 15/04/1987',
          'Sex: F',
          'Expiry: 2029-11-15',
          'National No. 9994256779 الرقم الوطني',
        ]),
      );

      expect(result.hasFieldsNeedingReview, isFalse,
          reason: result.fieldsNeedingReview.toString());
      expect(_field(result, DocumentFieldId.fullNameArabic).value, 'رنا رنا الزعبي');
      expect(_field(result, DocumentFieldId.fullNameLatin).value, 'Rana Rana Alzoubi');
      expect(_field(result, DocumentFieldId.dateOfBirth).value, '1987-04-15');
      expect(_field(result, DocumentFieldId.placeOfBirth).value, 'العقبة');
      expect(_field(result, DocumentFieldId.sex).value, 'F');
      expect(_field(result, DocumentFieldId.expiryDate).value, '2029-11-15');
      expect(_field(result, DocumentFieldId.nationalIdNumber).value, '9994256779');
    });

    test('keeps the printed digits in rawValue and converts only value', () {
      final dob = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['تاريخ الولادة: ١٥/٠٤/١٩٨٧']),
        ),
        DocumentFieldId.dateOfBirth,
      );
      expect(dob.status, FieldStatus.recognized);
      expect(dob.value, '1987-04-15');
      expect(dob.rawValue, '١٥/٠٤/١٩٨٧');
      expect(dob.evidence!.matchedLabel, 'تاريخ الولادة');
      expect(dob.evidence!.sourceText, 'تاريخ الولادة: ١٥/٠٤/١٩٨٧');
    });

    test('Tesseract: value before the label and bidi marks around the line', () {
      // Verbatim Tesseract output for benchmark card03_clean.
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page([
          '\u200Fالاسم: زيد ليلى العلي\u200E',
          '01/08/1984 \u200Fتاريخ الولادة:\u200E',
          '\u200Fالجنس: ذكر\u200E',
        ]),
      );
      final name = _field(result, DocumentFieldId.fullNameArabic);
      expect(name.value, 'زيد ليلى العلي');
      expect(name.rawValue, isNot(contains('\u200E')));
      expect(_field(result, DocumentFieldId.dateOfBirth).value, '1984-08-01');
      expect(_field(result, DocumentFieldId.sex).value, 'M');
    });

    test('PaddleOCR: merged label words and a value glued to its label', () {
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page([
          'الرقمالوطني 9994256779',
          'تاريخ الولادة١٥/٠٤/١٩٨٧',
        ]),
      );
      expect(_field(result, DocumentFieldId.nationalIdNumber).value, '9994256779');
      expect(_field(result, DocumentFieldId.dateOfBirth).value, '1987-04-15');
    });

    test('PaddleOCR: a label whose digits were dropped is uncertain, not passed',
        () {
      // PaddleOCR's Arabic recognizer returned only the label, at 0.93
      // confidence, for a line that printed a date.
      final dob = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['تاريخ الولادة'], confidences: [0.93]),
        ),
        DocumentFieldId.dateOfBirth,
      );
      expect(dob.status, FieldStatus.uncertain);
      expect(dob.value, isNull);
      expect(dob.uncertaintyReasons, [FieldUncertaintyReason.labelWithoutValue]);
      expect(dob.evidence, isNotNull, reason: 'the label location is evidence');
    });

    test('a dropped Arabic date is recovered from the English copy', () {
      final dob = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['تاريخ الولادة', 'Date of Birth: 15/04/1987']),
        ),
        DocumentFieldId.dateOfBirth,
      );
      expect(dob.status, FieldStatus.recognized);
      expect(dob.value, '1987-04-15');
      expect(dob.evidence!.matchedLabel, 'Date of Birth');
    });

    test('Apple Vision: a truncated choice value ("ذك") is uncertain', () {
      final sex = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['الجنس: ذك']),
        ),
        DocumentFieldId.sex,
      );
      expect(sex.status, FieldStatus.uncertain);
      expect(sex.value, 'ذك', reason: 'shown for review, never mapped to a guess');
      expect(sex.uncertaintyReasons, [FieldUncertaintyReason.failedFormatValidation]);
    });
  });

  group('RuleBasedFieldExtractor validation', () {
    test('an undeclared-by-OCR field is missing, never omitted', () {
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page(['Name: Rana Alzoubi']),
      );
      expect(result.fields, hasLength(_syntheticCardRules.length));
      final id = _field(result, DocumentFieldId.nationalIdNumber);
      expect(id.status, FieldStatus.missing);
      expect(id.value, isNull);
      expect(id.evidence, isNull);
    });

    test('an ID number with the wrong digit count is uncertain', () {
      final id = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['National No. 99942567']),
        ),
        DocumentFieldId.nationalIdNumber,
      );
      expect(id.status, FieldStatus.uncertain);
      expect(id.value, '99942567');
      expect(id.uncertaintyReasons, [FieldUncertaintyReason.failedFormatValidation]);
    });

    test('an ID number with a letter misread into it is uncertain', () {
      final id = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['National No. 99942O6779']),
        ),
        DocumentFieldId.nationalIdNumber,
      );
      expect(id.status, FieldStatus.uncertain);
      expect(id.uncertaintyReasons, contains(FieldUncertaintyReason.failedFormatValidation));
    });

    test('a birth date in the future is implausible', () {
      final dob = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['Date of Birth: 01/01/2030']),
        ),
        DocumentFieldId.dateOfBirth,
      );
      expect(dob.status, FieldStatus.uncertain);
      expect(dob.uncertaintyReasons, [FieldUncertaintyReason.implausibleDate]);
    });

    test('an impossible calendar date (31/02) is rejected, not rolled over', () {
      final dob = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['Date of Birth: 31/02/1990']),
        ),
        DocumentFieldId.dateOfBirth,
      );
      expect(dob.status, FieldStatus.uncertain);
      expect(dob.value, isNull);
      expect(dob.uncertaintyReasons, [FieldUncertaintyReason.implausibleDate]);
    });

    test('an expiry before the birth date is flagged by the cross-check', () {
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page(['Date of Birth: 15/04/1987', 'Expiry: 1980-01-01']),
      );
      final expiry = _field(result, DocumentFieldId.expiryDate);
      expect(expiry.status, FieldStatus.uncertain);
      expect(expiry.uncertaintyReasons, [FieldUncertaintyReason.implausibleDate]);
      expect(_field(result, DocumentFieldId.dateOfBirth).status,
          FieldStatus.recognized);
    });

    test('Arabic and English copies that disagree are ambiguous', () {
      final dob = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page([
            'تاريخ الولادة: 15/04/1987',
            'Date of Birth: 16/04/1987',
          ]),
        ),
        DocumentFieldId.dateOfBirth,
      );
      expect(dob.status, FieldStatus.uncertain);
      expect(dob.uncertaintyReasons, [FieldUncertaintyReason.ambiguousCandidates]);
    });

    test('low OCR confidence makes a well-formed value uncertain', () {
      final name = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['Name: Rana Alzoubi'], confidences: [0.3]),
        ),
        DocumentFieldId.fullNameLatin,
      );
      expect(name.status, FieldStatus.uncertain);
      expect(name.uncertaintyReasons, [FieldUncertaintyReason.lowOcrConfidence]);
      expect(name.confidence, 0.3);
    });

    test('an unreported (null) confidence is not treated as low', () {
      final name = _field(
        _extractor().extract(
          profileId: 'synthetic',
          front: _page(['Name: Rana Alzoubi'], confidences: [null]),
        ),
        DocumentFieldId.fullNameLatin,
      );
      expect(name.status, FieldStatus.recognized);
      expect(name.confidence, isNull);
    });
  });

  group('RuleBasedFieldExtractor misread detection', () {
    ExtractedField extractOne(String line, DocumentFieldId id) =>
        _field(_extractor().extract(profileId: 'synthetic', front: _page([line])), id);

    test('Arabic letters inside a Latin name are flagged (PaddleOCR "Aلali")', () {
      final name = extractOne('Name: Zaid Layla Aلali', DocumentFieldId.fullNameLatin);
      expect(name.status, FieldStatus.uncertain);
      expect(name.uncertaintyReasons, [FieldUncertaintyReason.ambiguousCharacters]);
    });

    test('Latin letters or digits inside an Arabic name are flagged', () {
      expect(
        extractOne('الاسم: ليلى wa النجار', DocumentFieldId.fullNameArabic).status,
        FieldStatus.uncertain,
      );
      expect(
        extractOne('الاسم: محمد أحمد المصري 1', DocumentFieldId.fullNameArabic).status,
        FieldStatus.uncertain,
      );
    });

    test('a capital inside a mixed-case word is flagged (I/l confusion)', () {
      final name = extractOne('Name: Layla Khaled AInajjar', DocumentFieldId.fullNameLatin);
      expect(name.status, FieldStatus.uncertain);
      expect(name.uncertaintyReasons, [FieldUncertaintyReason.ambiguousCharacters]);
    });

    test('an all-caps name is not flagged', () {
      final name = extractOne('Name: LAYLA KHALED ALNAJJAR', DocumentFieldId.fullNameLatin);
      expect(name.status, FieldStatus.recognized);
    });
  });

  group('RuleBasedFieldExtractor layout tolerance', () {
    test('two labels on one line each get only their own value', () {
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page(['Sex: M Expiry: 2030-01-01']),
      );
      expect(_field(result, DocumentFieldId.sex).value, 'M');
      expect(_field(result, DocumentFieldId.expiryDate).value, '2030-01-01');
    });

    test('a value on its own line below the label is found, with both boxes',
        () {
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page(
          ['Name', 'Rana Alzoubi'],
          boxes: const [
            NormalizedRect(left: 0.1, top: 0.10, right: 0.3, bottom: 0.15),
            NormalizedRect(left: 0.1, top: 0.16, right: 0.5, bottom: 0.21),
          ],
        ),
      );
      final name = _field(result, DocumentFieldId.fullNameLatin);
      expect(name.status, FieldStatus.recognized);
      expect(name.value, 'Rana Alzoubi');
      expect(name.evidence!.boundingBoxes, hasLength(2));
    });

    test('a value split into a separate line on the same row is found', () {
      // Arabic label on the right, its value as a separate line to its left.
      final result = _extractor().extract(
        profileId: 'synthetic',
        front: _page(
          ['مكان الولادة:', 'العقبة'],
          boxes: const [
            NormalizedRect(left: 0.70, top: 0.10, right: 0.95, bottom: 0.15),
            NormalizedRect(left: 0.55, top: 0.10, right: 0.68, bottom: 0.15),
          ],
        ),
      );
      expect(_field(result, DocumentFieldId.placeOfBirth).value, 'العقبة');
    });

    test('fields restricted to one side ignore the other side', () {
      final extractor = RuleBasedFieldExtractor(
        rules: const [
          FieldRule(
            field: DocumentFieldId.fullNameLatin,
            labels: ['Name'],
            kind: FieldValueKind.text,
            sides: {DocumentSide.back},
          ),
        ],
      );
      final result = extractor.extract(
        profileId: 'synthetic',
        front: _page(['Name: Front Value']),
        back: _page(['Name: Back Value'], side: DocumentSide.back),
      );
      final name = _field(result, DocumentFieldId.fullNameLatin);
      expect(name.value, 'Back Value');
      expect(name.evidence!.side, DocumentSide.back);
    });
  });
}
