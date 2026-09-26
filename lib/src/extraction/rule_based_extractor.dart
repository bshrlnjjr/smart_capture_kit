import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../document/document_profile.dart';
import '../ocr/ocr_models.dart';
import '../ocr/text_normalization.dart';
import 'field_models.dart';

/// What kind of value a [FieldRule] expects after its label.
enum FieldValueKind {
  /// Free text such as a name or a place. Must contain at least one letter.
  text,

  /// A run of digits, e.g. an ID number. Spaces inside the run are ignored.
  number,

  /// A calendar date, normalized to ISO-8601 `yyyy-MM-dd`.
  date,

  /// One of a closed set of printed values, mapped through
  /// [FieldRule.allowedValues].
  choice,
}

/// How the numbers of a printed date are ordered.
enum DateOrder {
  /// `31/12/1990`
  dayMonthYear,

  /// `1990-12-31`
  yearMonthDay,
}

/// What a date field means, for plausibility checks.
enum DateMeaning {
  /// Must not be in the future.
  past,

  /// May be in the past or the future (e.g. an expiry date).
  any,
}

/// How to find and validate one field on an OCR'd document.
///
/// Rules are label-based: a field is located by the printed label next to it,
/// in any of its [labels] (typically an Arabic and a Latin form). Nothing here
/// encodes a position on the card, so a rule keeps working when the
/// recognizer splits, merges or reorders lines.
@immutable
class FieldRule {
  const FieldRule({
    required this.field,
    required this.labels,
    required this.kind,
    this.sides,
    this.exactDigitCount,
    this.dateOrder = DateOrder.dayMonthYear,
    this.dateMeaning = DateMeaning.any,
    this.allowedValues = const {},
    this.script,
  });

  final DocumentFieldId field;

  /// Every printed form of the label, e.g. `['الرقم الوطني', 'National No.']`.
  ///
  /// Matched after [normalizeForComparison] with aggressive Arabic folding,
  /// case-insensitively, ignoring punctuation and with or without the spaces
  /// between the label's words — engines drop both.
  final List<String> labels;

  final FieldValueKind kind;

  /// Sides the field may appear on; `null` means either.
  final Set<DocumentSide>? sides;

  /// For [FieldValueKind.number]: the exact digit count, when fixed.
  final int? exactDigitCount;

  /// For [FieldValueKind.date].
  final DateOrder dateOrder;

  /// For [FieldValueKind.date].
  final DateMeaning dateMeaning;

  /// For [FieldValueKind.choice]: printed value to canonical value, e.g.
  /// `{'ذكر': 'M', 'M': 'M', 'أنثى': 'F', 'F': 'F'}`. Keys are matched with the
  /// same normalization as labels.
  final Map<String, String> allowedValues;

  /// For [FieldValueKind.text]: the script the value is printed in.
  ///
  /// When set, a value containing letters of another script, or digits, is
  /// `uncertain` ([FieldUncertaintyReason.ambiguousCharacters]): recognizers
  /// mix scripts when they misread (`Aلali`), and a name has no digits.
  final OcrScript? script;
}

/// A [DocumentFieldExtractor] driven by a list of [FieldRule]s.
///
/// ## What it guarantees
///
/// - Every rule produces exactly one [ExtractedField]: `recognized`,
///   `uncertain` (with reasons) or `missing`. Nothing is omitted, nothing is
///   invented.
/// - [ExtractedField.rawValue] is the exact OCR text of the value tokens;
///   [ExtractedField.value] is the normalized form (Western digits, ISO date,
///   canonical choice). Raw OCR is never rewritten.
/// - Every non-missing field carries [FieldEvidence] pointing at the line(s)
///   it came from.
///
/// ## Engine quirks it tolerates, from the phase 6 benchmark
///
/// - The value on either side of the label: Tesseract emits mixed
///   Arabic/digit lines in visual order (`01/08/1984 تاريخ الولادة:`).
/// - Labels whose words were merged (`الرقمالوطني`) and values glued to the
///   label (`الولادة١٩٨٧`): tokens are split at letter/digit boundaries.
/// - A value on a separate line to the side of or below its label.
/// - A label found with no value next to it — PaddleOCR's Arabic recognizer
///   silently drops digit runs — which is reported as
///   [FieldUncertaintyReason.labelWithoutValue], never as a pass.
class RuleBasedFieldExtractor implements DocumentFieldExtractor {
  RuleBasedFieldExtractor({
    required this.rules,
    this.confidenceFloor = 0.5,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<FieldRule> rules;

  /// OCR confidence below which a value is `uncertain`. A `null` engine
  /// confidence is "not reported", not "low", and does not trigger this.
  final double confidenceFloor;

  final DateTime Function() _clock;

  @override
  ExtractedFieldSet extract({
    required String profileId,
    OcrPageResult? front,
    OcrPageResult? back,
  }) {
    final pages = [?front, ?back];
    final fields = [
      for (final rule in rules) _extractField(rule, pages),
    ];
    return ExtractedFieldSet(
      profileId: profileId,
      fields: _crossCheckDates(fields),
    );
  }

  ExtractedField _extractField(FieldRule rule, List<OcrPageResult> pages) {
    final candidates = <_Candidate>[];
    for (final page in pages) {
      if (rule.sides != null && !rule.sides!.contains(page.side)) continue;
      final lines = page.lines;
      for (var i = 0; i < lines.length; i++) {
        final candidate = _candidateOnLine(rule, page.side, lines, i);
        if (candidate != null) candidates.add(candidate);
      }
    }
    if (candidates.isEmpty) return ExtractedField.missing(rule.field);

    // Prefer candidates that produced a valid value; among those, a
    // disagreement is ambiguity the user must resolve.
    final parsed = [for (final c in candidates) (c, _parse(rule, c))];
    final valid = parsed.where((p) => p.$2.value != null && p.$2.reasons.isEmpty).toList();
    final distinctValues = {for (final p in valid) p.$2.value};
    final chosen = valid.isNotEmpty
        ? valid.first
        : parsed.firstWhere((p) => p.$2.value != null, orElse: () => parsed.first);

    final reasons = [...chosen.$2.reasons];
    if (distinctValues.length > 1) {
      reasons.add(FieldUncertaintyReason.ambiguousCandidates);
    }
    final confidence = chosen.$1.confidence;
    if (confidence != null && confidence < confidenceFloor) {
      reasons.add(FieldUncertaintyReason.lowOcrConfidence);
    }

    return ExtractedField(
      id: rule.field,
      status: reasons.isEmpty ? FieldStatus.recognized : FieldStatus.uncertain,
      value: chosen.$2.value,
      rawValue: chosen.$1.rawValue.isEmpty ? null : chosen.$1.rawValue,
      evidence: FieldEvidence(
        side: chosen.$1.side,
        sourceText: chosen.$1.sourceText,
        boundingBoxes: chosen.$1.boxes,
        ocrConfidence: confidence,
        matchedLabel: chosen.$1.matchedLabel,
      ),
      uncertaintyReasons: reasons,
      confidence: confidence,
    );
  }

  /// Looks for [rule]'s label on `lines[index]` and collects its value from
  /// the same line, or failing that from a neighbouring line.
  _Candidate? _candidateOnLine(
    FieldRule rule,
    DocumentSide side,
    List<OcrLine> lines,
    int index,
  ) {
    final line = lines[index];
    final tokens = _tokenize(line.text);
    final match = _findLabel(tokens, rule.labels);
    if (match == null) return null;

    final ownLabels = _labelSpans(tokens, rule.labels);
    final otherLabels = _labelSpans(tokens, _otherLabels(rule));

    List<_Token> collect(Iterable<int> indices) {
      final out = <_Token>[];
      for (final i in indices) {
        if (otherLabels.contains(i)) break;
        if (ownLabels.contains(i)) continue;
        final token = tokens[i];
        if (token.isSeparator) continue;
        out.add(token);
      }
      return out;
    }

    var value = collect([for (var i = match.end; i < tokens.length; i++) i]);
    if (value.isEmpty) {
      value = collect([for (var i = match.start - 1; i >= 0; i--) i]).reversed.toList();
    }

    final boxes = [line.boundingBox];
    var sourceText = line.text;
    var confidence = line.confidence;

    if (value.isEmpty) {
      final neighbour = _neighbourValueLine(lines, index);
      if (neighbour != null) {
        final neighbourTokens = _tokenize(neighbour.text);
        // A line carrying any label — this field's other language included —
        // is a field of its own, never this label's value.
        final neighbourLabels = _labelSpans(
          neighbourTokens,
          [...rule.labels, ..._otherLabels(rule)],
        );
        if (neighbourLabels.isEmpty) {
          value = neighbourTokens.where((t) => !t.isSeparator).toList();
          boxes.add(neighbour.boundingBox);
          sourceText = '${line.text}\n${neighbour.text}';
          confidence = _minConfidence(confidence, neighbour.confidence);
        }
      }
    }

    return _Candidate(
      side: side,
      matchedLabel: match.label,
      rawValue: value
          .map((t) => t.raw)
          .join(' ')
          .replaceAll(_edgeSeparators, ''),
      sourceText: sourceText,
      boxes: boxes,
      confidence: confidence,
    );
  }

  Iterable<String> _otherLabels(FieldRule rule) => [
        for (final other in rules)
          if (other.field != rule.field) ...other.labels,
      ];

  _Parsed _parse(FieldRule rule, _Candidate candidate) {
    final raw = candidate.rawValue.trim();
    if (raw.isEmpty) {
      return const _Parsed(null, [FieldUncertaintyReason.labelWithoutValue]);
    }
    switch (rule.kind) {
      case FieldValueKind.text:
        final hasLetter = RegExp(r'\p{L}', unicode: true).hasMatch(raw);
        if (!hasLetter) {
          return _Parsed(raw, const [FieldUncertaintyReason.failedFormatValidation]);
        }
        return _Parsed(raw, [
          if (_hasSuspiciousCharacters(raw, rule.script))
            FieldUncertaintyReason.ambiguousCharacters,
        ]);

      case FieldValueKind.number:
        final western = toWesternDigits(raw);
        final digits = western.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isEmpty) {
          return _Parsed(null, const [FieldUncertaintyReason.labelWithoutValue]);
        }
        final hasStrayLetters = RegExp(r'\p{L}', unicode: true).hasMatch(western);
        final wrongLength =
            rule.exactDigitCount != null && digits.length != rule.exactDigitCount;
        return _Parsed(digits, [
          if (wrongLength || hasStrayLetters)
            FieldUncertaintyReason.failedFormatValidation,
        ]);

      case FieldValueKind.date:
        return _parseDate(rule, raw);

      case FieldValueKind.choice:
        final key = _labelKey(raw);
        for (final entry in rule.allowedValues.entries) {
          if (_labelKey(entry.key) == key) return _Parsed(entry.value, const []);
        }
        // Keep what was read so the reviewer sees it, but flag it: a
        // truncated read ("ذك" for "ذكر") must not map to a guess.
        return _Parsed(raw, const [FieldUncertaintyReason.failedFormatValidation]);
    }
  }

  _Parsed _parseDate(FieldRule rule, String raw) {
    final western = toWesternDigits(raw);
    final match = RegExp(r'(\d{1,4})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{1,4})')
        .firstMatch(western);
    if (match == null) {
      final hasDigits = RegExp(r'\d').hasMatch(western);
      return _Parsed(
        null,
        [
          hasDigits
              ? FieldUncertaintyReason.failedFormatValidation
              : FieldUncertaintyReason.labelWithoutValue,
        ],
      );
    }
    final a = int.parse(match.group(1)!);
    final b = int.parse(match.group(2)!);
    final c = int.parse(match.group(3)!);
    final (year, month, day) = switch (rule.dateOrder) {
      DateOrder.dayMonthYear => (c, b, a),
      DateOrder.yearMonthDay => (a, b, c),
    };
    if (year < 1900 || year > 2200 || month < 1 || month > 12 || day < 1) {
      return const _Parsed(null, [FieldUncertaintyReason.failedFormatValidation]);
    }
    final date = DateTime.utc(year, month, day);
    if (date.month != month || date.day != day) {
      // e.g. 31/02: DateTime rolls it into March rather than rejecting it.
      return const _Parsed(null, [FieldUncertaintyReason.implausibleDate]);
    }
    final iso = _isoDate(date);
    if (rule.dateMeaning == DateMeaning.past) {
      final now = _clock();
      if (date.isAfter(DateTime.utc(now.year, now.month, now.day))) {
        return _Parsed(iso, const [FieldUncertaintyReason.implausibleDate]);
      }
    }
    return _Parsed(iso, const []);
  }

  /// Flags issue/expiry/birth dates whose order is impossible. Each date may
  /// be individually well formed and still wrong relative to the others.
  List<ExtractedField> _crossCheckDates(List<ExtractedField> fields) {
    DateTime? dateOf(DocumentFieldId id) {
      for (final f in fields) {
        if (f.id == id && f.value != null && f.status != FieldStatus.missing) {
          return DateTime.tryParse(f.value!);
        }
      }
      return null;
    }

    final birth = dateOf(DocumentFieldId.dateOfBirth);
    final issue = dateOf(DocumentFieldId.issueDate);
    final expiry = dateOf(DocumentFieldId.expiryDate);

    bool implausible(DocumentFieldId id) => switch (id) {
          DocumentFieldId.expiryDate => expiry != null &&
              ((issue != null && !expiry.isAfter(issue)) ||
                  (birth != null && !expiry.isAfter(birth))),
          DocumentFieldId.issueDate =>
            issue != null && birth != null && issue.isBefore(birth),
          _ => false,
        };

    return [
      for (final f in fields)
        if (implausible(f.id) &&
            !f.uncertaintyReasons.contains(FieldUncertaintyReason.implausibleDate))
          ExtractedField(
            id: f.id,
            status: FieldStatus.uncertain,
            value: f.value,
            rawValue: f.rawValue,
            evidence: f.evidence,
            uncertaintyReasons: [
              ...f.uncertaintyReasons,
              FieldUncertaintyReason.implausibleDate,
            ],
            confidence: f.confidence,
          )
        else
          f,
    ];
  }
}

final RegExp _arabicLetter = RegExp('[\u0621-\u064A\u0671-\u06D3]');
final RegExp _latinLetter = RegExp('[A-Za-z]');
final RegExp _anyDigit = RegExp('[0-9\u0660-\u0669\u06F0-\u06F9]');

/// Whether a text value shows the marks of a misread rather than of what was
/// printed:
///
/// - letters from a script other than [script], or any digit (`Aلali`,
///   `المصري 1`);
/// - an uppercase letter inside a word that also has lowercase letters
///   (`AInajjar`, `ALzoubi`): the classic `I`/`l` confusion. All-caps words
///   are not flagged, since cards often print names in capitals.
bool _hasSuspiciousCharacters(String value, OcrScript? script) {
  if (script != null) {
    if (_anyDigit.hasMatch(value)) return true;
    final foreign = script == OcrScript.arabic ? _latinLetter : _arabicLetter;
    if (foreign.hasMatch(value)) return true;
  }
  for (final word in value.split(RegExp(r'\s+'))) {
    final hasLower = word.contains(RegExp('[a-z]'));
    if (hasLower && word.length > 1 && word.substring(1).contains(RegExp('[A-Z]'))) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tokenizing and label matching
// ---------------------------------------------------------------------------

class _Token {
  _Token.of(this.raw) : key = _labelKey(raw);

  /// Exactly as the engine returned it (minus surrounding whitespace).
  final String raw;

  /// Comparison key: normalized, punctuation removed.
  final String key;

  bool get isSeparator => key.isEmpty;
}

/// Invisible direction marks engines wrap right-to-left runs in. Stripped
/// from token text so they never become part of a raw value.
final RegExp _bidiControls =
    RegExp('[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]');

/// Label/value separators left on the edges of a value (`:F`, `رنا،`).
final RegExp _edgeSeparators = RegExp(r'^[:：؛;,،\s]+|[:：؛;,،\s]+$');

final RegExp _punctuation = RegExp(r'[:：؛;,،.\-_/\\|()\[\]]');
final RegExp _letterDigitBoundary = RegExp(
  r'(?<=\p{L})(?=\p{Nd})|(?<=\p{Nd})(?=\p{L})',
  unicode: true,
);

String _labelKey(String text) => normalizeForComparison(
      text,
      folding: ArabicFoldingOptions.aggressive,
    ).replaceAll(_punctuation, '').replaceAll(' ', '');

/// Splits on whitespace and on letter/digit boundaries, so `الولادة١٩٨٧`
/// becomes a label token and a value token. Colons that engines attach to
/// either side are left in `raw` and ignored by `key`.
List<_Token> _tokenize(String text) {
  final withoutControls = text.replaceAll(_bidiControls, '');
  return [
    for (final word in withoutControls.split(RegExp(r'\s+')))
      if (word.isNotEmpty)
        for (final piece in word.split(_letterDigitBoundary))
          if (piece.isNotEmpty) _Token.of(piece),
  ];
}

class _LabelMatch {
  const _LabelMatch(this.start, this.end, this.label);
  final int start;
  final int end; // exclusive
  final String label;
}

/// Finds the first token window whose concatenated key equals a label's key.
/// Concatenation makes `الرقم الوطني` and `الرقمالوطني` match the same label.
_LabelMatch? _findLabel(List<_Token> tokens, Iterable<String> labels) {
  final keyed = [
    for (final label in labels)
      if (_labelKey(label).isNotEmpty) (label, _labelKey(label)),
  ];
  for (var start = 0; start < tokens.length; start++) {
    if (tokens[start].isSeparator) continue;
    var joined = '';
    for (var end = start; end < tokens.length; end++) {
      joined += tokens[end].key;
      for (final (label, key) in keyed) {
        if (joined == key) return _LabelMatch(start, end + 1, label);
      }
      if (keyed.every((k) => !k.$2.startsWith(joined))) break;
    }
  }
  return null;
}

/// Indices of every token belonging to any occurrence of any of [labels].
Set<int> _labelSpans(List<_Token> tokens, Iterable<String> labels) {
  final spans = <int>{};
  var offset = 0;
  while (offset < tokens.length) {
    final match = _findLabel(tokens.sublist(offset), labels);
    if (match == null) break;
    for (var i = match.start; i < match.end; i++) {
      spans.add(offset + i);
    }
    offset += match.end;
  }
  return spans;
}

/// The line most likely to hold the value for a label on `lines[index]` that
/// had nothing next to it: first a line on the same row, then the nearest
/// line directly below.
OcrLine? _neighbourValueLine(List<OcrLine> lines, int index) {
  final label = lines[index].boundingBox;
  OcrLine? best;
  var bestScore = double.infinity;
  for (var i = 0; i < lines.length; i++) {
    if (i == index) continue;
    final box = lines[i].boundingBox;
    final verticalOverlap =
        _overlap(label.top, label.bottom, box.top, box.bottom) / label.height;
    final horizontalOverlap =
        _overlap(label.left, label.right, box.left, box.right);
    double? score;
    if (verticalOverlap > 0.5) {
      // Same row: nearest horizontally.
      final gap = box.left >= label.right
          ? box.left - label.right
          : label.left - box.right;
      if (gap >= 0 && gap < 0.25) score = gap;
    } else if (box.top >= label.bottom - 0.01 && horizontalOverlap > 0) {
      final gap = box.top - label.bottom;
      if (gap < 1.5 * label.height) score = 1 + gap;
    }
    if (score != null && score < bestScore) {
      bestScore = score;
      best = lines[i];
    }
  }
  return best;
}

double _overlap(double a0, double a1, double b0, double b1) {
  final lo = a0 > b0 ? a0 : b0;
  final hi = a1 < b1 ? a1 : b1;
  return hi > lo ? hi - lo : 0;
}

double? _minConfidence(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _Candidate {
  const _Candidate({
    required this.side,
    required this.matchedLabel,
    required this.rawValue,
    required this.sourceText,
    required this.boxes,
    required this.confidence,
  });

  final DocumentSide side;
  final String matchedLabel;
  final String rawValue;
  final String sourceText;
  final List<NormalizedRect> boxes;
  final double? confidence;
}

class _Parsed {
  const _Parsed(this.value, this.reasons);
  final String? value;
  final List<FieldUncertaintyReason> reasons;
}
