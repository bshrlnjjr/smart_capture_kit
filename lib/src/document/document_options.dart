import 'package:meta/meta.dart';

import '../common/errors.dart';
import '../common/labels.dart';
import '../ocr/ocr_engine.dart';
import 'document_profile.dart';

/// Which sides of a document to capture.
enum DocumentSides {
  /// Capture the front only.
  frontOnly,

  /// Capture the front, then the back.
  frontAndBack,
}

/// Tunable thresholds for the document quality checks.
///
/// As with portrait capture, defaults are permissive starting points, not
/// certified requirements.
@immutable
class DocumentQualityThresholds {
  const DocumentQualityThresholds({
    this.minDocumentAreaFraction = 0.35,
    this.maxPerspectiveDistortion = 0.20,
    this.minBrightness = 0.20,
    this.maxBrightness = 0.88,
    this.minSharpness = 0.40,
    this.maxGlareAreaFraction = 0.05,
    this.glareLuminanceThreshold = 0.97,
  });

  /// Fraction of the frame the card must occupy before capture is encouraged.
  ///
  /// Drives characters-per-pixel, which is the single biggest lever on OCR
  /// accuracy for a small card.
  final double minDocumentAreaFraction;

  /// Maximum [Quad.perspectiveDistortion] tolerated before the user is asked
  /// to hold the device flatter.
  final double maxPerspectiveDistortion;

  final double minBrightness;
  final double maxBrightness;
  final double minSharpness;

  /// Fraction of the document area allowed to be specular highlight before the
  /// glare check fails.
  final double maxGlareAreaFraction;

  /// Normalized luminance above which a pixel counts as glare.
  final double glareLuminanceThreshold;

  /// Throws [SmartCaptureException] with
  /// [SmartCaptureErrorCode.invalidOptions] if any pair is inverted.
  void validate() {
    if (minBrightness >= maxBrightness) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.invalidOptions,
        message: 'minBrightness ($minBrightness) must be less than '
            'maxBrightness ($maxBrightness)',
      );
    }
    if (minDocumentAreaFraction <= 0 || minDocumentAreaFraction > 1) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.invalidOptions,
        message: 'minDocumentAreaFraction ($minDocumentAreaFraction) must fall '
            'within (0, 1]',
      );
    }
  }
}

/// Configuration for [SmartCapture.captureDocument].
///
/// ## What this plugin does not claim
///
/// Capturing and reading a document is not identity verification. The plugin
/// does not check whether a document is authentic, whether it belongs to the
/// person presenting it, or whether the data on it is true.
@immutable
class DocumentCaptureOptions {
  const DocumentCaptureOptions({
    this.documentProfile = 'generic_id_card',
    this.sides = DocumentSides.frontAndBack,
    this.ocr = true,
    this.thresholds = const DocumentQualityThresholds(),
    this.produceRectifiedImage = true,
    this.analysisInterval = const Duration(milliseconds: 300),
    this.labels,
    this.allowContinueOnFailedChecks = true,
    this.showReviewScreen = true,
    this.ocrEngineOverride,
    this.aspectRatioOverride,
  });

  /// Id of a profile in [DocumentProfileRegistry].
  final String documentProfile;

  final DocumentSides sides;

  /// Whether to run OCR after capture. When `false` the result carries images
  /// and quality checks only.
  final bool ocr;

  final DocumentQualityThresholds thresholds;

  /// Whether to produce a perspective-corrected image alongside the original.
  final bool produceRectifiedImage;

  /// Minimum gap between analyses of preview frames. Frames arriving during an
  /// analysis are dropped, not queued.
  final Duration analysisInterval;

  final SmartCaptureLabels? labels;

  final bool allowContinueOnFailedChecks;

  final bool showReviewScreen;

  /// Replaces the default per-platform engine selection.
  ///
  /// This is the hook for a host-supplied cloud adapter. When it sends data
  /// off the device, its descriptor reports `isOffDevice: true` and the host
  /// is responsible for disclosing that to the user.
  final OcrEngine? ocrEngineOverride;

  /// Overrides the profile's expected aspect ratio.
  ///
  /// Document dimensions vary by issuer and by revision; this lets a host
  /// correct the ratio without forking the profile.
  final double? aspectRatioOverride;

  /// Resolves [documentProfile] against the registry.
  ///
  /// Throws [SmartCaptureException] with
  /// [SmartCaptureErrorCode.unknownDocumentProfile] when no such profile is
  /// registered.
  DocumentProfile resolveProfile() {
    final profile = DocumentProfileRegistry.find(documentProfile);
    if (profile == null) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.unknownDocumentProfile,
        message: 'No document profile registered with id "$documentProfile". '
            'Registered ids: '
            '${DocumentProfileRegistry.all.map((p) => p.id).join(', ')}',
      );
    }
    return profile;
  }

  /// The aspect ratio the capture overlay and checks should use.
  double effectiveAspectRatio() =>
      aspectRatioOverride ?? resolveProfile().aspectRatio;
}
