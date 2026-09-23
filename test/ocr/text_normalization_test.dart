import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

void main() {
  group('digit conversion', () {
    test('converts Arabic-Indic digits to Western', () {
      expect(toWesternDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    });

    test('converts extended Arabic-Indic (Persian/Urdu) digits', () {
      expect(toWesternDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });

    test('leaves non-digit characters untouched', () {
      expect(toWesternDigits('رقم ١٢٣ ABC'), 'رقم 123 ABC');
    });

    test('round-trips Western to Arabic-Indic and back', () {
      const original = '9901234567';
      expect(toWesternDigits(toArabicIndicDigits(original)), original);
    });

    test('is a no-op on text with no digits', () {
      expect(toWesternDigits('إبراهيم'), 'إبراهيم');
    });
  });

  group('normalizeForComparison', () {
    test('does not modify the input string', () {
      const raw = 'ﺇﺑﺮﺍﻫﻴﻢ ١٢٣';
      final before = raw;
      normalizeForComparison(raw);
      expect(raw, before);
    });

    test('folds alef variants under the conservative preset', () {
      expect(
        normalizeForComparison('أحمد'),
        normalizeForComparison('احمد'),
      );
      expect(
        normalizeForComparison('إبراهيم'),
        normalizeForComparison('ابراهيم'),
      );
    });

    test('conservative folding preserves teh marbuta, which changes meaning',
        () {
      expect(
        normalizeForComparison('مدينة'),
        isNot(normalizeForComparison('مدينه')),
      );
    });

    test('aggressive folding collapses teh marbuta for label matching', () {
      expect(
        normalizeForComparison('مدينة',
            folding: ArabicFoldingOptions.aggressive),
        normalizeForComparison('مدينه',
            folding: ArabicFoldingOptions.aggressive),
      );
    });

    test('strips tatweel', () {
      expect(normalizeForComparison('محـــمد'), normalizeForComparison('محمد'));
    });

    test('strips diacritics', () {
      expect(
        normalizeForComparison('مُحَمَّد'),
        normalizeForComparison('محمد'),
      );
    });

    test('strips invisible bidi control characters', () {
      const withControls = '\u202Bالاسم\u202C';
      expect(normalizeForComparison(withControls), normalizeForComparison('الاسم'));
    });

    test('collapses whitespace runs and trims', () {
      expect(normalizeForComparison('  a   b \n c '), 'a b c');
    });

    test('converts digits by default and can be told not to', () {
      expect(normalizeForComparison('١٢٣'), '123');
      expect(normalizeForComparison('١٢٣', convertDigits: false), '١٢٣');
    });
  });

  group('script detection', () {
    test('detects Arabic letters', () {
      expect(containsArabic('محمد'), isTrue);
      expect(containsArabic('Mohammad'), isFalse);
    });

    test('detects Arabic presentation forms, which some engines emit', () {
      // U+FEDF ARABIC LETTER LAM INITIAL FORM.
      expect(containsArabic('ﻟ'), isTrue);
    });

    test('does not mistake Western digits for Arabic script', () {
      expect(containsArabic('123456'), isFalse);
    });

    test('detects Latin letters', () {
      expect(containsLatin('Jordan'), isTrue);
      expect(containsLatin('الأردن'), isFalse);
    });

    test('mixed-script text reports both', () {
      const mixed = 'الأردن Jordan';
      expect(containsArabic(mixed), isTrue);
      expect(containsLatin(mixed), isTrue);
    });
  });

  group('extractDigitRuns', () {
    test('returns every run, not just the first', () {
      expect(extractDigitRuns('abc 12 def 3456'), ['12', '3456']);
    });

    test('converts Arabic numerals before extracting', () {
      expect(extractDigitRuns('رقم ٩٩٠١٢٣٤٥٦٧'), ['9901234567']);
    });

    test('returns an empty list when there are no digits', () {
      expect(extractDigitRuns('لا أرقام هنا'), isEmpty);
    });
  });
}
