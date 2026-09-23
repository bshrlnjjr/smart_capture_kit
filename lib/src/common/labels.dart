import 'package:meta/meta.dart';

import 'guidance.dart';

/// Every user-visible string the capture UI can show.
///
/// The plugin ships English and Arabic sets. A host that needs different
/// wording, a different language, or its own tone builds its own instance and
/// passes it through the capture options — no string in the UI is hard-coded.
///
/// Deliberately a plain class rather than a generated ARB bundle: the plugin
/// should not impose a localization framework on its host.
@immutable
class SmartCaptureLabels {
  const SmartCaptureLabels({
    required this.guidance,
    required this.portraitTitle,
    required this.documentFrontTitle,
    required this.documentBackTitle,
    required this.reviewTitle,
    required this.retake,
    required this.usePhoto,
    required this.cancel,
    required this.confirm,
    required this.edit,
    required this.continueAnyway,
    required this.needsReview,
    required this.cameraPermissionRequired,
    required this.openSettings,
    required this.textDirection,
  });

  /// English defaults.
  factory SmartCaptureLabels.english() => const SmartCaptureLabels(
        guidance: {
          CaptureGuidance.ready: 'Looks good',
          CaptureGuidance.holdStill: 'Hold still',
          CaptureGuidance.tooDark: 'Find better lighting',
          CaptureGuidance.tooBright: 'Too bright — reduce glare or light',
          CaptureGuidance.outOfFocus: 'Hold steady to focus',
          CaptureGuidance.noFaceDetected: 'No face detected',
          CaptureGuidance.multipleFacesDetected:
              'More than one face detected',
          CaptureGuidance.moveCloser: 'Move closer',
          CaptureGuidance.moveFarther: 'Move farther away',
          CaptureGuidance.moveRight: 'Move right',
          CaptureGuidance.moveLeft: 'Move left',
          CaptureGuidance.moveDown: 'Move down',
          CaptureGuidance.moveUp: 'Move up',
          CaptureGuidance.lookStraightAhead: 'Look straight at the camera',
          CaptureGuidance.openEyes: 'Open your eyes',
          CaptureGuidance.noDocumentDetected: 'Point the camera at the card',
          CaptureGuidance.fitAllCornersInFrame:
              'Fit all four corners in the frame',
          CaptureGuidance.moveCloserToDocument: 'Move closer to the card',
          CaptureGuidance.holdDeviceFlat: 'Hold the phone flat over the card',
          CaptureGuidance.avoidGlare: 'Tilt to avoid glare',
          CaptureGuidance.unexpectedDocumentShape:
              'That does not look like the expected card',
        },
        portraitTitle: 'Take a portrait photo',
        documentFrontTitle: 'Scan the front of the card',
        documentBackTitle: 'Scan the back of the card',
        reviewTitle: 'Review',
        retake: 'Retake',
        usePhoto: 'Continue',
        cancel: 'Cancel',
        confirm: 'Confirm',
        edit: 'Edit',
        continueAnyway: 'Continue anyway',
        needsReview: 'Needs review',
        cameraPermissionRequired: 'Camera access is required to continue',
        openSettings: 'Open settings',
        textDirection: SmartCaptureTextDirection.ltr,
      );

  /// Arabic defaults.
  ///
  /// Provided so the Arabic path is usable out of the box rather than left as
  /// an exercise. Wording should be reviewed by a native speaker before a host
  /// ships it to users; it is a starting point, not a certified translation.
  factory SmartCaptureLabels.arabic() => const SmartCaptureLabels(
        guidance: {
          CaptureGuidance.ready: 'جيد',
          CaptureGuidance.holdStill: 'ثبّت الكاميرا',
          CaptureGuidance.tooDark: 'الإضاءة ضعيفة',
          CaptureGuidance.tooBright: 'الإضاءة قوية جدًا',
          CaptureGuidance.outOfFocus: 'ثبّت الجهاز حتى تتضح الصورة',
          CaptureGuidance.noFaceDetected: 'لم يتم العثور على وجه',
          CaptureGuidance.multipleFacesDetected: 'تم العثور على أكثر من وجه',
          CaptureGuidance.moveCloser: 'اقترب أكثر',
          CaptureGuidance.moveFarther: 'ابتعد قليلاً',
          CaptureGuidance.moveRight: 'تحرك إلى اليمين',
          CaptureGuidance.moveLeft: 'تحرك إلى اليسار',
          CaptureGuidance.moveDown: 'تحرك إلى الأسفل',
          CaptureGuidance.moveUp: 'تحرك إلى الأعلى',
          CaptureGuidance.lookStraightAhead: 'انظر مباشرة إلى الكاميرا',
          CaptureGuidance.openEyes: 'افتح عينيك',
          CaptureGuidance.noDocumentDetected: 'وجّه الكاميرا نحو البطاقة',
          CaptureGuidance.fitAllCornersInFrame:
              'اجعل زوايا البطاقة الأربع داخل الإطار',
          CaptureGuidance.moveCloserToDocument: 'اقترب من البطاقة',
          CaptureGuidance.holdDeviceFlat: 'امسك الهاتف بشكل مستوٍ فوق البطاقة',
          CaptureGuidance.avoidGlare: 'أمِل الهاتف لتجنب الانعكاس',
          CaptureGuidance.unexpectedDocumentShape:
              'شكل البطاقة لا يطابق المتوقع',
        },
        portraitTitle: 'التقط صورة شخصية',
        documentFrontTitle: 'صوّر الوجه الأمامي للبطاقة',
        documentBackTitle: 'صوّر الوجه الخلفي للبطاقة',
        reviewTitle: 'مراجعة',
        retake: 'إعادة التصوير',
        usePhoto: 'متابعة',
        cancel: 'إلغاء',
        confirm: 'تأكيد',
        edit: 'تعديل',
        continueAnyway: 'المتابعة على أي حال',
        needsReview: 'بحاجة إلى مراجعة',
        cameraPermissionRequired: 'يلزم الوصول إلى الكاميرا للمتابعة',
        openSettings: 'فتح الإعدادات',
        textDirection: SmartCaptureTextDirection.rtl,
      );

  /// Text for each guidance value.
  ///
  /// A host may supply a partial map; [guidanceText] falls back to the English
  /// wording for anything missing so a new guidance value added in a future
  /// release never renders as an empty string.
  final Map<CaptureGuidance, String> guidance;

  final String portraitTitle;
  final String documentFrontTitle;
  final String documentBackTitle;
  final String reviewTitle;
  final String retake;
  final String usePhoto;
  final String cancel;
  final String confirm;
  final String edit;
  final String continueAnyway;
  final String needsReview;
  final String cameraPermissionRequired;
  final String openSettings;

  /// Direction the capture UI should lay out in.
  final SmartCaptureTextDirection textDirection;

  /// Text for [value], falling back to the English default when the host's map
  /// has no entry.
  String guidanceText(CaptureGuidance value) =>
      guidance[value] ?? _englishGuidanceFallback[value] ?? value.name;

  static final Map<CaptureGuidance, String> _englishGuidanceFallback =
      SmartCaptureLabels.english().guidance;
}

/// Layout direction for the capture UI.
enum SmartCaptureTextDirection { ltr, rtl }
