import 'dart:io';

import 'package:flutter/services.dart';

import '../common/errors.dart';
import '../common/geometry.dart';
import 'ocr_engine.dart';
import 'ocr_models.dart';
import 'text_normalization.dart';

/// The on-device engine this plugin ships for the current platform.
///
/// - **iOS:** Apple Vision, request revision 3 at the `.accurate` level:
///   Latin, plus Arabic on iOS 16+.
/// - **Android:** ML Kit Text Recognition v2 with the bundled Latin model.
///   Latin only: ML Kit has no Arabic model, and the Arabic engine for
///   Android (PaddleOCR, per the phase 6 benchmark) is not integrated yet.
///
/// Scripts are queried from the platform at runtime ([supportedScripts]), not
/// assumed. [recognize] throws rather than silently returning Latin-only text
/// when asked for a script the device cannot read.
class NativeOcrEngine implements OcrEngine {
  NativeOcrEngine({
    required this.descriptor,
    this.usesLanguageCorrection = false,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('smart_capture_kit');

  /// The engine for the platform this code runs on.
  factory NativeOcrEngine.forCurrentPlatform({bool usesLanguageCorrection = false}) {
    if (Platform.isIOS) {
      return NativeOcrEngine(
        descriptor: const OcrEngineDescriptor(
          id: 'apple_vision',
          displayName: 'Apple Vision',
          isOffDevice: false,
        ),
        usesLanguageCorrection: usesLanguageCorrection,
      );
    }
    if (Platform.isAndroid) {
      return NativeOcrEngine(
        descriptor: const OcrEngineDescriptor(
          id: 'mlkit_text_v2',
          displayName: 'ML Kit Text Recognition v2 (Latin)',
          isOffDevice: false,
        ),
      );
    }
    throw const SmartCaptureException(
      code: SmartCaptureErrorCode.ocrEngineUnavailable,
      message: 'On-device OCR is available on Android and iOS only.',
    );
  }

  @override
  final OcrEngineDescriptor descriptor;

  /// Apple Vision only. Off by default: correction rewrites text toward
  /// dictionary words, which conflicts with never silently repairing what
  /// was printed (see doc/benchmarks/phase6-desktop-ocr.md).
  final bool usesLanguageCorrection;

  final MethodChannel _channel;

  Set<OcrScript>? _supportedScripts;

  @override
  Future<Set<OcrScript>> supportedScripts() async {
    final cached = _supportedScripts;
    if (cached != null) return cached;
    final names = await _invoke<List<Object?>>('supportedScripts', null);
    return _supportedScripts = {
      for (final name in names ?? const [])
        for (final script in OcrScript.values)
          if (script.name == name) script,
    };
  }

  @override
  Future<OcrPageResult> recognize(OcrRequest request) async {
    final supported = await supportedScripts();
    final unsupported = request.scripts.where((s) => !supported.contains(s)).toList();
    if (unsupported.isNotEmpty) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.ocrEngineUnavailable,
        message: '${descriptor.displayName} cannot read '
            '${unsupported.map((s) => s.name).join(', ')} on this device.',
      );
    }

    final stopwatch = Stopwatch()..start();
    final response = await _invoke<Map<Object?, Object?>>('recognizeText', {
      'path': request.image.path,
      'scripts': [for (final s in request.scripts) s.name],
      'usesLanguageCorrection': usesLanguageCorrection,
    });
    stopwatch.stop();

    return parseNativeOcrResponse(
      response ?? const {},
      side: request.side,
      engine: descriptor,
      requestedScripts: request.scripts,
      elapsed: stopwatch.elapsed,
    );
  }

  Future<T?> _invoke<T>(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw SmartCaptureException(
        code: e.code == 'script_unsupported'
            ? SmartCaptureErrorCode.ocrEngineUnavailable
            : SmartCaptureErrorCode.ocrFailed,
        message: e.message ?? e.code,
        cause: e,
      );
    } on MissingPluginException catch (e) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.ocrEngineUnavailable,
        message: 'The native OCR engine is not registered on this platform.',
        cause: e,
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('disposeTextRecognizer');
    } on MissingPluginException {
      // Nothing native to release.
    }
  }
}

/// Converts the platform channel's `recognizeText` response into an
/// [OcrPageResult].
///
/// Both platforms return the same shape: a flat list of lines, each tagged
/// with the block it belongs to. Line text is kept exactly as delivered.
OcrPageResult parseNativeOcrResponse(
  Map<Object?, Object?> response, {
  required DocumentSide side,
  required OcrEngineDescriptor engine,
  required List<OcrScript> requestedScripts,
  Duration? elapsed,
}) {
  final byBlock = <int, List<OcrLine>>{};
  for (final entry in (response['lines'] as List<Object?>? ?? const [])) {
    final line = (entry! as Map<Object?, Object?>);
    final text = line['text'] as String? ?? '';
    final box = [for (final v in line['box']! as List<Object?>) (v! as num).toDouble()];
    final corners = line['corners'] as List<Object?>?;
    final rect = NormalizedRect(
      left: box[0].clamp(0.0, 1.0),
      top: box[1].clamp(0.0, 1.0),
      right: box[2].clamp(0.0, 1.0),
      bottom: box[3].clamp(0.0, 1.0),
    );
    byBlock.putIfAbsent(line['block'] as int? ?? 0, () => []).add(
          OcrLine(
            text: text,
            boundingBox: rect,
            confidence: (line['confidence'] as num?)?.toDouble(),
            cornerPoints: corners == null || corners.length != 8
                ? null
                : [
                    for (var i = 0; i < 8; i += 2)
                      NormalizedPoint(
                        (corners[i]! as num).toDouble(),
                        (corners[i + 1]! as num).toDouble(),
                      ),
                  ],
            recognizedScript: _scriptOf(text),
          ),
        );
  }

  final blockIds = byBlock.keys.toList()..sort();
  final blocks = [
    for (final id in blockIds)
      OcrBlock(
        text: byBlock[id]!.map((l) => l.text).join('\n'),
        boundingBox: byBlock[id]!.map((l) => l.boundingBox).reduce((a, b) => a.union(b)),
        lines: byBlock[id]!,
        confidence: _minConfidence(byBlock[id]!),
        recognizedScript: _scriptOf(byBlock[id]!.map((l) => l.text).join(' ')),
      ),
  ];

  return OcrPageResult(
    side: side,
    rawText: blocks.map((b) => b.text).join('\n'),
    blocks: blocks,
    engine: OcrEngineDescriptor(
      id: engine.id,
      displayName: engine.displayName,
      isOffDevice: engine.isOffDevice,
      version: response['engineVersion'] as String? ?? engine.version,
    ),
    requestedScripts: requestedScripts,
    processingDuration: elapsed,
  );
}

OcrScript? _scriptOf(String text) {
  if (containsArabic(text)) return OcrScript.arabic;
  if (containsLatin(text)) return OcrScript.latin;
  return null;
}

double? _minConfidence(List<OcrLine> lines) {
  double? min;
  for (final line in lines) {
    final c = line.confidence;
    if (c != null && (min == null || c < min)) min = c;
  }
  return min;
}
