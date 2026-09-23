import 'package:meta/meta.dart';

import '../common/errors.dart';
import '../common/labels.dart';

/// Which camera the portrait flow opens with.
enum CameraFacing { front, back }

/// Tunable thresholds for the portrait quality checks.
///
/// Defaults are deliberately permissive. This plugin cannot know what any
/// particular government, bank or employer requires, and it must never imply
/// that it does — see the note on [PortraitCaptureOptions]. Tighten these to
/// match a requirement you have actually verified yourself.
@immutable
class PortraitQualityThresholds {
  const PortraitQualityThresholds({
    this.minFaceHeightFraction = 0.30,
    this.maxFaceHeightFraction = 0.80,
    this.maxHorizontalOffset = 0.12,
    this.maxVerticalOffset = 0.12,
    this.maxYawDegrees = 12.0,
    this.maxPitchDegrees = 12.0,
    this.maxRollDegrees = 10.0,
    this.minBrightness = 0.25,
    this.maxBrightness = 0.85,
    this.minSharpness = 0.35,
    this.minEyeOpenProbability = 0.5,
    this.requireEyesOpen = false,
  });

  /// Face bounding-box height as a fraction of image height, below which the
  /// user is asked to move closer.
  final double minFaceHeightFraction;

  /// Face height fraction above which the user is asked to move back.
  final double maxFaceHeightFraction;

  /// Maximum distance, in normalized units, between the face centre and the
  /// target centre horizontally.
  final double maxHorizontalOffset;

  /// As [maxHorizontalOffset], vertically.
  final double maxVerticalOffset;

  /// Maximum head rotation about the vertical axis (turning left/right).
  final double maxYawDegrees;

  /// Maximum head rotation about the horizontal axis (nodding up/down).
  ///
  /// Not every platform reports pitch. Where it is unavailable the check is
  /// reported as `notEvaluated` rather than silently passed.
  final double maxPitchDegrees;

  /// Maximum head tilt within the image plane.
  final double maxRollDegrees;

  /// Mean luminance in `[0, 1]` below which the image counts as too dark.
  final double minBrightness;

  /// Mean luminance above which the image counts as blown out.
  final double maxBrightness;

  /// Normalized sharpness score below which the image counts as blurry.
  final double minSharpness;

  /// Per-eye open probability below which the eyes-open check does not pass.
  final double minEyeOpenProbability;

  /// Whether a closed-eye result should be a failure rather than a warning.
  final bool requireEyesOpen;

  /// Throws [SmartCaptureException] with [SmartCaptureErrorCode.invalidOptions]
  /// if any min/max pair is inverted.
  void validate() {
    void check(bool condition, String message) {
      if (!condition) {
        throw SmartCaptureException(
          code: SmartCaptureErrorCode.invalidOptions,
          message: message,
        );
      }
    }

    check(
      minFaceHeightFraction < maxFaceHeightFraction,
      'minFaceHeightFraction ($minFaceHeightFraction) must be less than '
      'maxFaceHeightFraction ($maxFaceHeightFraction)',
    );
    check(
      minBrightness < maxBrightness,
      'minBrightness ($minBrightness) must be less than maxBrightness '
      '($maxBrightness)',
    );
    check(
      minFaceHeightFraction > 0 && maxFaceHeightFraction <= 1,
      'Face height fractions must fall within (0, 1]',
    );
  }
}

/// Configuration for [SmartCapture.capturePortrait].
///
/// ## What this plugin does not claim
///
/// Passing every check here means the image satisfied the thresholds
/// configured in this object. It is **not** a statement that the photo meets
/// any government's passport or ID photo standard, and the plugin does not
/// perform identity verification, face matching, liveness detection or fraud
/// detection.
@immutable
class PortraitCaptureOptions {
  const PortraitCaptureOptions({
    this.cameraFacing = CameraFacing.front,
    this.thresholds = const PortraitQualityThresholds(),
    this.outputAspectRatio,
    this.produceCroppedImage = true,
    this.cropPaddingFactor = 0.6,
    this.analysisInterval = const Duration(milliseconds: 250),
    this.mirrorFrontCameraOutput = false,
    this.labels,
    this.allowContinueOnFailedChecks = true,
    this.showReviewScreen = true,
  });

  final CameraFacing cameraFacing;

  final PortraitQualityThresholds thresholds;

  /// Width / height of the optional cropped output, e.g. `3 / 4`.
  ///
  /// `null` keeps the cropped image at the camera's native ratio. The original
  /// image is never cropped regardless of this setting.
  final double? outputAspectRatio;

  /// Whether to produce a cropped image alongside the original.
  final bool produceCroppedImage;

  /// How much space to leave around the face when cropping, as a multiple of
  /// the face box height. `0.6` leaves roughly 60% of a face height as margin.
  final double cropPaddingFactor;

  /// Minimum gap between analyses of preview frames.
  ///
  /// Frames arriving while an analysis is in flight are dropped rather than
  /// queued, so a slow device degrades to a lower guidance rate instead of
  /// building an unbounded backlog.
  final Duration analysisInterval;

  /// Whether to horizontally flip the saved image from the front camera.
  ///
  /// Defaults to `false`: the unmirrored image is what the document-style
  /// convention expects, even though the preview is mirrored so the user can
  /// aim.
  final bool mirrorFrontCameraOutput;

  /// UI strings. Defaults to [SmartCaptureLabels.english] when `null`.
  final SmartCaptureLabels? labels;

  /// Whether the review screen offers "continue anyway" when checks failed.
  ///
  /// Defaults to `true`, matching the principle that a low-confidence model
  /// result explains a problem rather than vetoing the user.
  final bool allowContinueOnFailedChecks;

  /// Whether to show the built-in review screen after capture. Set `false` to
  /// return immediately and build your own review UI from the result.
  final bool showReviewScreen;

  PortraitCaptureOptions copyWith({
    CameraFacing? cameraFacing,
    PortraitQualityThresholds? thresholds,
    double? outputAspectRatio,
    bool? produceCroppedImage,
    double? cropPaddingFactor,
    Duration? analysisInterval,
    bool? mirrorFrontCameraOutput,
    SmartCaptureLabels? labels,
    bool? allowContinueOnFailedChecks,
    bool? showReviewScreen,
  }) =>
      PortraitCaptureOptions(
        cameraFacing: cameraFacing ?? this.cameraFacing,
        thresholds: thresholds ?? this.thresholds,
        outputAspectRatio: outputAspectRatio ?? this.outputAspectRatio,
        produceCroppedImage: produceCroppedImage ?? this.produceCroppedImage,
        cropPaddingFactor: cropPaddingFactor ?? this.cropPaddingFactor,
        analysisInterval: analysisInterval ?? this.analysisInterval,
        mirrorFrontCameraOutput:
            mirrorFrontCameraOutput ?? this.mirrorFrontCameraOutput,
        labels: labels ?? this.labels,
        allowContinueOnFailedChecks:
            allowContinueOnFailedChecks ?? this.allowContinueOnFailedChecks,
        showReviewScreen: showReviewScreen ?? this.showReviewScreen,
      );
}
