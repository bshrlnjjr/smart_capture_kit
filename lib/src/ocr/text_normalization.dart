/// Text normalization helpers for comparing and validating OCR output.
///
/// Every function here is **derivation only**. The raw string an engine
/// returned is preserved verbatim on [OcrLine.text] and [OcrBlock.text]; these
/// helpers produce a *separate* value used for matching a label, validating a
/// format, or presenting a checked result. Nothing here ever writes back over
/// the original.
///
/// The distinction matters for identity documents: silently "fixing" an
/// ambiguous character is how an OCR pipeline invents data. This library makes
/// the fixed-up form available for comparison while keeping the evidence
/// intact.
library;

/// Arabic-Indic digits, U+0660..U+0669 — used across the Arab world.
const String arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

/// Extended Arabic-Indic digits, U+06F0..U+06F9 — used for Persian and Urdu.
/// Included because they occasionally appear in OCR output even on Arabic
/// documents, depending on the engine's model.
const String extendedArabicIndicDigits = '۰۱۲۳۴۵۶۷۸۹';

const String _westernDigits = '0123456789';

/// Tatweel (kashida), U+0640 — a purely decorative letter-elongation
/// character. It carries no meaning and appears inconsistently in OCR output,
/// so it is always dropped during comparison.
const String tatweel = 'ـ';

/// Arabic diacritics: the harakat range U+064B..U+0652, plus superscript alef
/// U+0670. Rarely printed on identity documents, sometimes hallucinated by
/// recognizers.
final RegExp _arabicDiacritics = RegExp('[\u064B-\u0652\u0670]');

/// Bidirectional control characters that engines may embed around
/// right-to-left runs. They are invisible, and they break naive string
/// equality. Tesseract wraps every Arabic line in RLM ... LRM; U+061C is the
/// Arabic Letter Mark.
final RegExp _bidiControls =
    RegExp('[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]');

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Converts any Arabic-Indic or extended Arabic-Indic digit in [input] to its
/// Western equivalent, leaving every other character untouched.
///
/// Use for validating a date or an ID number whose printed form uses Arabic
/// numerals.
String toWesternDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final arabicIndex = arabicIndicDigits.runes.toList().indexOf(rune);
    if (arabicIndex >= 0) {
      buffer.write(_westernDigits[arabicIndex]);
      continue;
    }
    final extendedIndex = extendedArabicIndicDigits.runes.toList().indexOf(rune);
    if (extendedIndex >= 0) {
      buffer.write(_westernDigits[extendedIndex]);
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// Converts Western digits in [input] to Arabic-Indic digits.
///
/// Provided for rendering a validated value back in the script the document
/// used. Not used anywhere in the extraction path.
String toArabicIndicDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final index = _westernDigits.runes.toList().indexOf(rune);
    if (index >= 0) {
      buffer.write(String.fromCharCode(arabicIndicDigits.runes.elementAt(index)));
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// How aggressively [normalizeForComparison] folds Arabic letter forms.
class ArabicFoldingOptions {
  const ArabicFoldingOptions({
    this.foldAlefVariants = true,
    this.foldAlefMaksura = false,
    this.foldTehMarbuta = false,
    this.stripDiacritics = true,
    this.stripTatweel = true,
  });

  /// Conservative preset: strips only what is meaningless (tatweel,
  /// diacritics, bidi controls) and folds alef variants, which OCR engines
  /// confuse constantly.
  static const ArabicFoldingOptions conservative = ArabicFoldingOptions();

  /// Aggressive preset for fuzzy *label* matching only.
  ///
  /// Folds teh marbuta and alef maksura, which changes meaning in Arabic
  /// (`ة` and `ه` are different letters). Acceptable when matching a printed
  /// field label against a known list; never acceptable for a person's name.
  static const ArabicFoldingOptions aggressive = ArabicFoldingOptions(
    foldAlefMaksura: true,
    foldTehMarbuta: true,
  );

  /// Map `أ إ آ ٱ` to bare `ا`. Engines pick hamza placement unreliably.
  final bool foldAlefVariants;

  /// Map `ى` to `ي`.
  final bool foldAlefMaksura;

  /// Map `ة` to `ه`.
  final bool foldTehMarbuta;

  final bool stripDiacritics;
  final bool stripTatweel;
}

/// Produces a comparison key for [input].
///
/// The result is for matching and validation only. It is lossy by design and
/// must never be stored as a field value or shown to a user as "the extracted
/// text".
String normalizeForComparison(
  String input, {
  ArabicFoldingOptions folding = ArabicFoldingOptions.conservative,
  bool convertDigits = true,
}) {
  var out = input;

  out = out.replaceAll(_bidiControls, '');

  if (folding.stripTatweel) {
    out = out.replaceAll(tatweel, '');
  }
  if (folding.stripDiacritics) {
    out = out.replaceAll(_arabicDiacritics, '');
  }
  if (folding.foldAlefVariants) {
    out = out.replaceAll(RegExp('[آأإٱ]'), 'ا');
  }
  if (folding.foldAlefMaksura) {
    out = out.replaceAll('ى', 'ي');
  }
  if (folding.foldTehMarbuta) {
    out = out.replaceAll('ة', 'ه');
  }
  if (convertDigits) {
    out = toWesternDigits(out);
  }

  out = out.replaceAll(_whitespaceRun, ' ').trim();
  return out.toLowerCase();
}

/// Whether [input] contains at least one character in the Arabic block.
///
/// Covers Arabic (U+0600..U+06FF), Arabic Supplement (U+0750..U+077F) and
/// Arabic Presentation Forms (U+FB50..U+FDFF, U+FE70..U+FEFF). Presentation
/// forms matter because some engines emit them instead of the canonical
/// letters.
bool containsArabic(String input) => RegExp(
        '[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFC]')
    .hasMatch(input);

/// Whether [input] contains at least one Latin letter.
bool containsLatin(String input) => RegExp('[A-Za-z]').hasMatch(input);

/// Extracts the maximal runs of digits from [input] after converting Arabic
/// numerals to Western ones.
///
/// Returns every run rather than the first, so a caller matching a national ID
/// number can pick by length instead of by position.
List<String> extractDigitRuns(String input) => RegExp(r'\d+')
    .allMatches(toWesternDigits(input))
    .map((m) => m.group(0)!)
    .toList();
