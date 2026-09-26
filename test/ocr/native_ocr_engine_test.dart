import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';
import 'package:smart_capture_kit/src/ocr/native_ocr_engine.dart';

const _engine = OcrEngineDescriptor(
  id: 'test_engine',
  displayName: 'Test engine',
  isOffDevice: false,
);

const _image = CaptureImage(
  path: '/tmp/card.jpg',
  kind: CaptureImageKind.rectified,
  width: 1400,
  height: 882,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smart_capture_kit_test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <MethodCall>[];
  void mockPlatform(Object? Function(MethodCall call) handler) {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('parseNativeOcrResponse', () {
    test('groups lines into blocks and keeps text exactly as delivered', () {
      final page = parseNativeOcrResponse(
        {
          'engineVersion': 'rev 3',
          'lines': [
            {
              'text': '\u200Fالاسم: رنا\u200E',
              'confidence': 0.5,
              'box': [0.6, 0.1, 0.95, 0.15],
              'corners': [0.6, 0.1, 0.95, 0.1, 0.95, 0.15, 0.6, 0.15],
              'block': 0,
            },
            {
              'text': 'Name: Rana',
              'confidence': 1.0,
              'box': [0.2, 0.3, 0.5, 0.35],
              'block': 1,
            },
            {
              'text': 'Sex: F',
              'box': [0.2, 0.36, 0.3, 0.41],
              'block': 1,
            },
          ],
        },
        side: DocumentSide.front,
        engine: _engine,
        requestedScripts: const [OcrScript.arabic, OcrScript.latin],
      );

      expect(page.blocks, hasLength(2));
      expect(page.lines.first.text, '\u200Fالاسم: رنا\u200E');
      expect(page.lines.first.recognizedScript, OcrScript.arabic);
      expect(page.lines.first.cornerPoints, hasLength(4));
      expect(page.lines[1].recognizedScript, OcrScript.latin);
      expect(page.lines[2].confidence, isNull, reason: 'absent is not zero');
      expect(page.blocks[1].confidence, 1.0);
      expect(page.blocks[1].boundingBox,
          const NormalizedRect(left: 0.2, top: 0.3, right: 0.5, bottom: 0.41));
      expect(page.rawText, contains('Name: Rana\nSex: F'));
      expect(page.engine.version, 'rev 3');
    });

    test('an empty response is an empty page, not an error', () {
      final page = parseNativeOcrResponse(
        const {'lines': []},
        side: DocumentSide.back,
        engine: _engine,
        requestedScripts: const [OcrScript.latin],
      );
      expect(page.isEmpty, isTrue);
      expect(page.side, DocumentSide.back);
    });
  });

  group('NativeOcrEngine', () {
    NativeOcrEngine engine() =>
        NativeOcrEngine(descriptor: _engine, channel: channel);

    test('refuses a script the device cannot read instead of returning partial text',
        () async {
      mockPlatform((call) => call.method == 'supportedScripts' ? ['latin'] : null);
      await expectLater(
        engine().recognize(const OcrRequest(
          image: _image,
          side: DocumentSide.front,
          scripts: [OcrScript.arabic, OcrScript.latin],
        )),
        throwsA(isA<SmartCaptureException>().having(
          (e) => e.code,
          'code',
          SmartCaptureErrorCode.ocrEngineUnavailable,
        )),
      );
      expect(calls.map((c) => c.method), isNot(contains('recognizeText')));
    });

    test('sends the path, scripts and correction flag, and parses the reply', () async {
      mockPlatform((call) => switch (call.method) {
            'supportedScripts' => ['latin', 'arabic'],
            'recognizeText' => {
                'lines': [
                  {'text': 'Name: Rana', 'box': [0.1, 0.1, 0.4, 0.2], 'block': 0},
                ],
              },
            _ => null,
          });
      final page = await engine().recognize(const OcrRequest(
        image: _image,
        side: DocumentSide.front,
        scripts: [OcrScript.arabic, OcrScript.latin],
      ));
      final call = calls.firstWhere((c) => c.method == 'recognizeText');
      expect(call.arguments, {
        'path': '/tmp/card.jpg',
        'scripts': ['arabic', 'latin'],
        'usesLanguageCorrection': false,
      });
      expect(page.lines.single.text, 'Name: Rana');
      expect(page.requestedScripts, [OcrScript.arabic, OcrScript.latin]);
      expect(page.processingDuration, isNotNull);
    });

    test('maps a native failure to ocrFailed', () async {
      mockPlatform((call) => switch (call.method) {
            'supportedScripts' => ['latin'],
            _ => throw PlatformException(code: 'ocr_failed', message: 'boom'),
          });
      await expectLater(
        engine().recognize(const OcrRequest(
          image: _image,
          side: DocumentSide.front,
          scripts: [OcrScript.latin],
        )),
        throwsA(isA<SmartCaptureException>().having(
          (e) => e.code,
          'code',
          SmartCaptureErrorCode.ocrFailed,
        )),
      );
    });
  });
}
