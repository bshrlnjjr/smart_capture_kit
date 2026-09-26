import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';
import 'package:smart_capture_kit/src/document/document_ocr.dart';

/// Returns canned lines per side and records every request.
class _FakeEngine implements OcrEngine {
  _FakeEngine({required this.scripts, this.linesBySide = const {}, this.fail = false});

  final Set<OcrScript> scripts;
  final Map<DocumentSide, List<String>> linesBySide;
  final bool fail;
  final requests = <OcrRequest>[];

  @override
  OcrEngineDescriptor get descriptor =>
      const OcrEngineDescriptor(id: 'fake', displayName: 'Fake', isOffDevice: false);

  @override
  Future<Set<OcrScript>> supportedScripts() async => scripts;

  @override
  Future<OcrPageResult> recognize(OcrRequest request) async {
    requests.add(request);
    if (fail) throw StateError('native crash');
    final lines = linesBySide[request.side] ?? const [];
    return OcrPageResult(
      side: request.side,
      rawText: lines.join('\n'),
      blocks: [
        OcrBlock(
          text: lines.join('\n'),
          boundingBox: const NormalizedRect(left: 0, top: 0, right: 1, bottom: 1),
          lines: [
            for (var i = 0; i < lines.length; i++)
              OcrLine(
                text: lines[i],
                boundingBox: NormalizedRect(
                  left: 0.1,
                  top: i * 0.1,
                  right: 0.9,
                  bottom: i * 0.1 + 0.08,
                ),
              ),
          ],
        ),
      ],
      engine: descriptor,
      requestedScripts: request.scripts,
    );
  }

  @override
  Future<void> dispose() async {}
}

CaptureImage _image(String path, CaptureImageKind kind) =>
    CaptureImage(path: path, kind: kind, width: 1400, height: 882);

DocumentSideCapture _side(DocumentSide side, {bool rectified = true}) =>
    DocumentSideCapture(
      side: side,
      originalImage: _image('/tmp/${side.name}_original.jpg', CaptureImageKind.original),
      rectifiedImage: rectified
          ? _image('/tmp/${side.name}_rectified.jpg', CaptureImageKind.rectified)
          : null,
      qualityReport: const QualityReport([]),
    );

final _profile = DocumentProfile(
  id: 'test_card',
  displayName: 'Test card',
  aspectRatio: idCardAspectRatioId1,
  expectedScripts: const [OcrScript.arabic, OcrScript.latin],
  extractionSupport: ProfileExtractionSupport.partialFieldMapping,
  declaredFields: const [DocumentFieldId.fullNameLatin, DocumentFieldId.nationalIdNumber],
  extractor: RuleBasedFieldExtractor(rules: const [
    FieldRule(
      field: DocumentFieldId.fullNameLatin,
      labels: ['Name'],
      kind: FieldValueKind.text,
      sides: {DocumentSide.front},
    ),
    FieldRule(
      field: DocumentFieldId.nationalIdNumber,
      labels: ['National No.'],
      kind: FieldValueKind.number,
      exactDigitCount: 10,
      sides: {DocumentSide.back},
    ),
  ]),
);

void main() {
  final capture = DocumentCaptureResult(
    profileId: 'test_card',
    front: _side(DocumentSide.front),
    back: _side(DocumentSide.back, rectified: false),
  );

  test('reads each side, preferring the rectified image, then extracts fields',
      () async {
    final engine = _FakeEngine(
      scripts: {OcrScript.latin, OcrScript.arabic},
      linesBySide: {
        DocumentSide.front: ['Name: Rana Alzoubi'],
        DocumentSide.back: ['National No. 9994256779'],
      },
    );
    final result = await runDocumentOcr(capture: capture, profile: _profile, engine: engine);

    expect(engine.requests.map((r) => r.image.path), [
      '/tmp/front_rectified.jpg',
      '/tmp/back_original.jpg', // no rectified image for the back
    ]);
    expect(result.ocrError, isNull);
    expect(result.front.ocr!.rawText, 'Name: Rana Alzoubi');
    expect(result.back!.ocr, isNotNull);
    expect(result.fields![DocumentFieldId.fullNameLatin]!.value, 'Rana Alzoubi');
    expect(result.fields![DocumentFieldId.nationalIdNumber]!.value, '9994256779');
    expect(result.front.originalImage, capture.front.originalImage,
        reason: 'OCR never replaces the captured images');
  });

  test('asks only for scripts the engine can read, and records that', () async {
    // ML Kit on Android: Latin only.
    final engine = _FakeEngine(scripts: {OcrScript.latin});
    final result = await runDocumentOcr(capture: capture, profile: _profile, engine: engine);

    expect(engine.requests.first.scripts, [OcrScript.latin]);
    expect(result.front.ocr!.requestedScripts, [OcrScript.latin],
        reason: 'lets a host tell "Arabic never read" from "not printed"');
  });

  test('no readable script at all: capture kept, ocrError set', () async {
    final latinOnlyProfile = DocumentProfile(
      id: 'arabic_only',
      displayName: 'Arabic only',
      aspectRatio: idCardAspectRatioId1,
      expectedScripts: const [OcrScript.arabic],
      extractionSupport: ProfileExtractionSupport.rawTextOnly,
      extractor: const NoFieldExtractor([]),
    );
    final engine = _FakeEngine(scripts: {OcrScript.latin});
    final result =
        await runDocumentOcr(capture: capture, profile: latinOnlyProfile, engine: engine);

    expect(engine.requests, isEmpty);
    expect(result.ocrError!.code, SmartCaptureErrorCode.ocrEngineUnavailable);
    expect(result.fields, isNull);
    expect(result.front.originalImage, capture.front.originalImage);
    expect(result.back, isNotNull);
  });

  test('an engine crash becomes ocrFailed, capture kept', () async {
    final engine = _FakeEngine(scripts: {OcrScript.latin}, fail: true);
    final result = await runDocumentOcr(capture: capture, profile: _profile, engine: engine);

    expect(result.ocrError!.code, SmartCaptureErrorCode.ocrFailed);
    expect(result.ocrError!.cause, isA<StateError>());
    expect(result.front.ocr, isNull);
    expect(result.fields, isNull);
  });
}
