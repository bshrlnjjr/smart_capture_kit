import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

void main() {
  group('DocumentCaptureOptions', () {
    test('resolves a registered profile', () {
      const options = DocumentCaptureOptions(documentProfile: 'jo_national_id');
      expect(options.resolveProfile().id, 'jo_national_id');
    });

    test('an unknown profile throws a typed error listing what is registered',
        () {
      const options = DocumentCaptureOptions(documentProfile: 'not_a_profile');
      expect(
        () => options.resolveProfile(),
        throwsA(
          isA<SmartCaptureException>()
              .having((e) => e.code, 'code',
                  SmartCaptureErrorCode.unknownDocumentProfile)
              .having((e) => e.message, 'message', contains('jo_national_id')),
        ),
      );
    });

    test('effectiveAspectRatio falls back to the profile ratio', () {
      const options = DocumentCaptureOptions(documentProfile: 'jo_national_id');
      expect(options.effectiveAspectRatio(), closeTo(idCardAspectRatioId1, 1e-9));
    });

    test('aspectRatioOverride wins over the profile', () {
      const options = DocumentCaptureOptions(
        documentProfile: 'jo_national_id',
        aspectRatioOverride: 1.42,
      );
      expect(options.effectiveAspectRatio(), 1.42);
    });
  });

  group('threshold validation', () {
    test('inverted brightness bounds are rejected', () {
      expect(
        () => const DocumentQualityThresholds(
          minBrightness: 0.9,
          maxBrightness: 0.2,
        ).validate(),
        throwsA(isA<SmartCaptureException>().having(
            (e) => e.code, 'code', SmartCaptureErrorCode.invalidOptions)),
      );
    });

    test('an out-of-range document area fraction is rejected', () {
      expect(
        () => const DocumentQualityThresholds(minDocumentAreaFraction: 1.5)
            .validate(),
        throwsA(isA<SmartCaptureException>()),
      );
    });

    test('inverted portrait face size bounds are rejected', () {
      expect(
        () => const PortraitQualityThresholds(
          minFaceHeightFraction: 0.9,
          maxFaceHeightFraction: 0.3,
        ).validate(),
        throwsA(isA<SmartCaptureException>().having(
            (e) => e.code, 'code', SmartCaptureErrorCode.invalidOptions)),
      );
    });

    test('defaults validate cleanly', () {
      expect(const DocumentQualityThresholds().validate, returnsNormally);
      expect(const PortraitQualityThresholds().validate, returnsNormally);
    });
  });

  group('DocumentProfileRegistry', () {
    test('ships a generic and a Jordan profile', () {
      expect(
        DocumentProfileRegistry.all.map((p) => p.id),
        containsAll(['generic_id_card', 'jo_national_id']),
      );
    });

    test('the Jordan profile declares no fields until samples are inspected',
        () {
      final profile = DocumentProfileRegistry.jordanNationalId;
      expect(profile.declaredFields, isEmpty);
      expect(profile.extractionSupport, ProfileExtractionSupport.rawTextOnly);
      expect(profile.expectedScripts, contains(OcrScript.arabic));
    });

    test('a raw-text-only profile extracts nothing rather than guessing', () {
      final profile = DocumentProfileRegistry.jordanNationalId;
      final fields = profile.extractor.extract(profileId: profile.id);
      expect(fields.fields, isEmpty);
      expect(fields.hasFieldsNeedingReview, isFalse);
    });

    test('NoFieldExtractor reports every declared field as missing', () {
      const extractor = NoFieldExtractor([
        DocumentFieldId.fullNameArabic,
        DocumentFieldId.nationalIdNumber,
      ]);
      final set = extractor.extract(profileId: 'x');
      expect(set.fields, hasLength(2));
      expect(set.fields.every((f) => f.status == FieldStatus.missing), isTrue);
    });

    test('a host can register its own profile and look it up', () {
      const custom = DocumentProfile(
        id: 'test_custom_profile',
        displayName: 'Custom',
        aspectRatio: 1.6,
        extractionSupport: ProfileExtractionSupport.rawTextOnly,
        extractor: NoFieldExtractor([]),
      );
      DocumentProfileRegistry.register(custom);
      expect(DocumentProfileRegistry.find('test_custom_profile'), same(custom));
    });
  });

  group('SmartCaptureLabels', () {
    test('ships English and Arabic with the right direction', () {
      expect(SmartCaptureLabels.english().textDirection,
          SmartCaptureTextDirection.ltr);
      expect(SmartCaptureLabels.arabic().textDirection,
          SmartCaptureTextDirection.rtl);
    });

    test('every guidance value has text in both shipped languages', () {
      for (final g in CaptureGuidance.values) {
        expect(SmartCaptureLabels.english().guidance[g], isNotNull,
            reason: 'missing English text for ${g.name}');
        expect(SmartCaptureLabels.arabic().guidance[g], isNotNull,
            reason: 'missing Arabic text for ${g.name}');
      }
    });

    test('a partial host override falls back to English, never to empty', () {
      final partial = SmartCaptureLabels.english();
      final custom = SmartCaptureLabels(
        guidance: const {CaptureGuidance.moveCloser: 'Step forward'},
        portraitTitle: partial.portraitTitle,
        documentFrontTitle: partial.documentFrontTitle,
        documentBackTitle: partial.documentBackTitle,
        reviewTitle: partial.reviewTitle,
        retake: partial.retake,
        usePhoto: partial.usePhoto,
        cancel: partial.cancel,
        confirm: partial.confirm,
        edit: partial.edit,
        continueAnyway: partial.continueAnyway,
        needsReview: partial.needsReview,
        cameraPermissionRequired: partial.cameraPermissionRequired,
        openSettings: partial.openSettings,
        textDirection: SmartCaptureTextDirection.ltr,
      );
      expect(custom.guidanceText(CaptureGuidance.moveCloser), 'Step forward');
      expect(custom.guidanceText(CaptureGuidance.avoidGlare),
          'Tilt to avoid glare');
    });
  });
}
