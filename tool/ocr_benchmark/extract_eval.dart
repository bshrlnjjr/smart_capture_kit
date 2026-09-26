// Runs RuleBasedFieldExtractor over recorded benchmark OCR output and
// counts, per engine, how each field ended up:
//
//   correct   recognized with the right value
//   WRONG     recognized with a wrong value — the outcome that must not happen
//   uncertain flagged for review (right or wrong value)
//   missing   not found
//
// Usage:
//   dart run tool/ocr_benchmark/extract_eval.dart <samples_dir> name=results.json ...
//
// The rules describe the synthetic benchmark card only (a made-up layout).

import 'dart:convert';
import 'dart:io';

import 'package:smart_capture_kit/src/common/geometry.dart';
import 'package:smart_capture_kit/src/extraction/field_models.dart';
import 'package:smart_capture_kit/src/extraction/rule_based_extractor.dart';
import 'package:smart_capture_kit/src/ocr/ocr_models.dart';

const rules = [
  FieldRule(
    field: DocumentFieldId.fullNameArabic,
    labels: ['الاسم'],
    kind: FieldValueKind.text,
    script: OcrScript.arabic,
  ),
  FieldRule(
    field: DocumentFieldId.fullNameLatin,
    labels: ['Name'],
    kind: FieldValueKind.text,
    script: OcrScript.latin,
  ),
  FieldRule(
    field: DocumentFieldId.dateOfBirth,
    labels: ['تاريخ الولادة', 'Date of Birth'],
    kind: FieldValueKind.date,
    dateMeaning: DateMeaning.past,
  ),
  FieldRule(
    field: DocumentFieldId.placeOfBirth,
    labels: ['مكان الولادة'],
    kind: FieldValueKind.text,
    script: OcrScript.arabic,
  ),
  FieldRule(
    field: DocumentFieldId.sex,
    labels: ['الجنس', 'Sex'],
    kind: FieldValueKind.choice,
    allowedValues: {'ذكر': 'M', 'أنثى': 'F', 'M': 'M', 'F': 'F'},
  ),
  FieldRule(
    field: DocumentFieldId.expiryDate,
    labels: ['Expiry'],
    kind: FieldValueKind.date,
    dateOrder: DateOrder.yearMonthDay,
  ),
  FieldRule(
    field: DocumentFieldId.nationalIdNumber,
    labels: ['الرقم الوطني', 'National No.'],
    kind: FieldValueKind.number,
    exactDigitCount: 10,
  ),
];

/// Ground-truth value per field, derived from ground_truth.json.
Map<DocumentFieldId, String> expectedFor(Map<String, dynamic> card) {
  String valueOf(String field) =>
      (card['lines'] as List).firstWhere((l) => l['field'] == field)['value'] as String;
  String isoFromDmy(String dmy) {
    final western = dmy.split('').map((c) {
      final i = '٠١٢٣٤٥٦٧٨٩'.indexOf(c);
      return i >= 0 ? '$i' : c;
    }).join();
    final p = western.split('/');
    return '${p[2]}-${p[1]}-${p[0]}';
  }

  final sexLine = (card['lines'] as List).firstWhere(
    (l) => (l['text'] as String).startsWith('Sex:'),
  )['text'] as String;
  return {
    DocumentFieldId.fullNameArabic: valueOf('name_ar'),
    DocumentFieldId.fullNameLatin: valueOf('name_en'),
    DocumentFieldId.dateOfBirth: isoFromDmy(valueOf('dob_en')),
    DocumentFieldId.placeOfBirth: valueOf('place_ar'),
    DocumentFieldId.sex: sexLine.substring(5).trim(),
    DocumentFieldId.expiryDate: valueOf('expiry'),
    DocumentFieldId.nationalIdNumber: valueOf('national_no'),
  };
}

OcrPageResult pageFrom(List<String> lines, List<double?> confidences) {
  // The runners record text and confidence only, so lines are stacked as
  // separate rows; label/value pairing within a line is what is exercised.
  final ocrLines = [
    for (var i = 0; i < lines.length; i++)
      OcrLine(
        text: lines[i],
        boundingBox: NormalizedRect(
          left: 0.05,
          top: i / lines.length,
          right: 0.95,
          bottom: (i + 0.8) / lines.length,
        ),
        confidence: i < confidences.length ? confidences[i] : null,
      ),
  ];
  return OcrPageResult(
    side: DocumentSide.front,
    rawText: lines.join('\n'),
    blocks: [
      OcrBlock(
        text: lines.join('\n'),
        boundingBox: const NormalizedRect(left: 0, top: 0, right: 1, bottom: 1),
        lines: ocrLines,
      ),
    ],
    engine: const OcrEngineDescriptor(
      id: 'recorded',
      displayName: 'Recorded benchmark output',
      isOffDevice: false,
    ),
    requestedScripts: const [OcrScript.arabic, OcrScript.latin],
  );
}

void main(List<String> args) {
  final samplesDir = args.first;
  final cards = (jsonDecode(File('$samplesDir/ground_truth.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  // FLOOR=0.75 dart run ... to try a stricter confidence floor.
  final floor = double.tryParse(Platform.environment['FLOOR'] ?? '') ?? 0.5;
  final extractor = RuleBasedFieldExtractor(
    rules: rules,
    confidenceFloor: floor,
    clock: () => DateTime.utc(2026, 9, 26),
  );

  stdout.writeln('| engine | correct | WRONG | uncertain | missing |');
  stdout.writeln('|---|---|---|---|---|');
  for (final arg in args.skip(1)) {
    final [name, path] = arg.split('=');
    final outputs = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    var correct = 0, wrong = 0, uncertain = 0, missing = 0;
    final wrongExamples = <String>[];
    for (final entry in outputs.entries) {
      final cardId = entry.key.split('_').first;
      final card = cards.firstWhere((c) => c['id'] == cardId);
      final expected = expectedFor(card);
      final result = entry.value as Map<String, dynamic>;
      final lines = (result['lines'] as List).cast<String>();
      final confidences = [
        for (final c in (result['confidences'] as List)) (c as num?)?.toDouble(),
      ];
      final set = extractor.extract(
        profileId: 'synthetic',
        front: pageFrom(lines, confidences),
      );
      for (final field in set.fields) {
        switch (field.status) {
          case FieldStatus.missing:
            missing++;
          case FieldStatus.uncertain:
            uncertain++;
          case FieldStatus.recognized:
          case FieldStatus.manuallyCorrected:
            if (field.value == expected[field.id]) {
              correct++;
            } else {
              wrong++;
              if (wrongExamples.length < 8) {
                wrongExamples.add('${entry.key} ${field.id.name}: '
                    'got "${field.value}" want "${expected[field.id]}"');
              }
            }
        }
      }
    }
    final total = correct + wrong + uncertain + missing;
    String pct(int n) => '${(100 * n / total).toStringAsFixed(1)}%';
    stdout.writeln('| $name | ${pct(correct)} | ${pct(wrong)} | ${pct(uncertain)} | ${pct(missing)} |');
    for (final example in wrongExamples) {
      stderr.writeln('  WRONG $name $example');
    }
  }
}
