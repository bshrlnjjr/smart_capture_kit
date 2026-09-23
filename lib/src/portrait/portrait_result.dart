import 'package:meta/meta.dart';

import '../common/capture_image.dart';
import '../common/geometry.dart';
import '../common/quality.dart';

/// What the face detector reported about the single face in a capture.
///
/// Every angle is nullable because platforms differ in what they expose: ML
/// Kit reports yaw, pitch and roll, while some configurations report only a
/// subset. A `null` angle means "not measured", and the corresponding quality
/// check is reported as [QualityCheckOutcome.notEvaluated].
@immutable
class FaceAnalysis {
  const FaceAnalysis({
    required this.boundingBox,
    this.yawDegrees,
    this.pitchDegrees,
    this.rollDegrees,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.trackingId,
  });

  final NormalizedRect boundingBox;

  /// Rotation about the vertical axis. Negative is the subject's right.
  final double? yawDegrees;

  /// Rotation about the horizontal axis. Negative is looking down.
  final double? pitchDegrees;

  /// Tilt within the image plane.
  final double? rollDegrees;

  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  /// Detector tracking id, when frame-to-frame tracking is active.
  final int? trackingId;

  @override
  String toString() => 'FaceAnalysis(box=$boundingBox, yaw=$yawDegrees, '
      'pitch=$pitchDegrees, roll=$rollDegrees)';
}

/// Result of a completed portrait capture.
///
/// The host owns every file referenced here — see [CaptureImage] for the
/// ownership and cleanup rules. Call [dispose] to delete them all.
@immutable
class PortraitCaptureResult {
  const PortraitCaptureResult({
    required this.originalImage,
    required this.qualityReport,
    this.croppedImage,
    this.face,
    this.faceCount = 0,
    this.userContinuedDespiteFailures = false,
  });

  /// The full-resolution frame as captured, uncropped and uncorrected.
  final CaptureImage originalImage;

  /// The cropped output, when [PortraitCaptureOptions.produceCroppedImage] was
  /// on and a face was located. `null` otherwise.
  final CaptureImage? croppedImage;

  /// Checks run against [originalImage] at full resolution — not against the
  /// preview frames used for live guidance.
  final QualityReport qualityReport;

  /// Analysis of the single detected face, or `null` when [faceCount] is not
  /// exactly one. With several faces present the plugin does not pick one.
  final FaceAnalysis? face;

  /// How many faces the final analysis found.
  final int faceCount;

  /// Whether the user chose to continue from the review screen with failing
  /// checks. Surfaced so a host can apply its own policy to such a result.
  final bool userContinuedDespiteFailures;

  /// Deletes every image file this result owns.
  Future<void> dispose() async {
    await originalImage.delete();
    await croppedImage?.delete();
  }

  @override
  String toString() => 'PortraitCaptureResult(faces=$faceCount, '
      '$qualityReport, cropped=${croppedImage != null})';
}
