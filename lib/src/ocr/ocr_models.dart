import 'package:meta/meta.dart';

import '../common/geometry.dart';

/// Which side of a document a piece of text came from.
enum DocumentSide { front, back }

/// Script a recognition request targets.
///
/// Script rather than language, because engine selection turns on script: ML
/// Kit ships one model per script, and Apple Vision exposes Arabic only in a
/// specific request revision.
enum OcrScript {
  latin,
  arabic,
}

/// Identifies the engine that produced a result.
///
/// Recorded per page so a host can apply a stricter confidence floor where the
/// engine is known to be weaker. See `doc/benchmarks/phase6-desktop-ocr.md`
/// for measured differences between engines.
@immutable
class OcrEngineDescriptor {
  const OcrEngineDescriptor({
    required this.id,
    required this.displayName,
    required this.isOffDevice,
    this.version,
  });

  /// Stable identifier, e.g. `apple_vision`, `mlkit_v2`, `tesseract`.
  final String id;

  final String displayName;

  /// Whether this engine sends image data off the device.
  ///
  /// Always `false` for the engines the plugin ships. A host-supplied cloud
  /// adapter must report `true` so the application can present its own
  /// disclosure before any image leaves the device.
  final bool isOffDevice;

  final String? version;

  @override
  String toString() =>
      'OcrEngineDescriptor($id${version == null ? '' : ' $version'}, '
      'offDevice=$isOffDevice)';
}

/// One recognized line of text with its position and confidence.
@immutable
class OcrLine {
  const OcrLine({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.cornerPoints,
    this.recognizedScript,
  });

  /// The recognized text, exactly as the engine returned it.
  ///
  /// Never normalized, never trimmed, never digit-converted. Derived values
  /// belong in [normalizedTextForComparison] at the call site, not here.
  final String text;

  final NormalizedRect boundingBox;

  /// Engine confidence in `[0, 1]`, or `null` when the engine does not report
  /// one. ML Kit does not expose a per-line confidence for all scripts, so
  /// `null` is common and must not be treated as zero.
  final double? confidence;

  /// The four corners of the line, when the engine reports a rotated box.
  ///
  /// Present for Arabic more often than for Latin, because cursive
  /// right-to-left text is frequently detected at a slight angle.
  final List<NormalizedPoint>? cornerPoints;

  final OcrScript? recognizedScript;

  @override
  String toString() => 'OcrLine(${text.length} chars, conf=$confidence)';
}

/// A block of text — typically a paragraph or a visually grouped cluster of
/// lines — as reported by the engine.
@immutable
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.boundingBox,
    required this.lines,
    this.confidence,
    this.recognizedScript,
  });

  /// Raw block text, exactly as the engine returned it.
  final String text;

  final NormalizedRect boundingBox;

  final List<OcrLine> lines;

  final double? confidence;

  final OcrScript? recognizedScript;

  @override
  String toString() => 'OcrBlock(${lines.length} lines, conf=$confidence)';
}

/// Everything one engine read from one side of a document.
@immutable
class OcrPageResult {
  const OcrPageResult({
    required this.side,
    required this.rawText,
    required this.blocks,
    required this.engine,
    required this.requestedScripts,
    this.processingDuration,
  });

  final DocumentSide side;

  /// The complete text of this side, exactly as the engine returned it,
  /// including its own line breaks and ordering.
  ///
  /// For right-to-left content the visual and logical order may differ. The
  /// string is preserved as delivered; no bidirectional reordering is applied.
  final String rawText;

  final List<OcrBlock> blocks;

  final OcrEngineDescriptor engine;

  /// Scripts this request asked the engine to look for.
  ///
  /// Recorded because a missing field may mean "the text was not there" or
  /// "we never asked the engine to read that script", and those are different
  /// facts.
  final List<OcrScript> requestedScripts;

  final Duration? processingDuration;

  /// Every line across every block, in block order.
  List<OcrLine> get lines => [for (final b in blocks) ...b.lines];

  bool get isEmpty => blocks.isEmpty;

  @override
  String toString() => 'OcrPageResult(${side.name}, ${blocks.length} blocks, '
      'engine=${engine.id})';
}
