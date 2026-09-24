import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../common/geometry.dart';
import '../common/image_metrics.dart';
import '../common/quality.dart';
import 'portrait_options.dart';
import 'portrait_result.dart';

/// Everything the final, full-resolution portrait pass computed.
class PortraitFinalAnalysis {
  const PortraitFinalAnalysis({
    required this.qualityReport,
    required this.faceCount,
    this.face,
  });

  final QualityReport qualityReport;
  final int faceCount;
  final FaceAnalysis? face;
}

/// Builds the [QualityReport] for a captured, full-resolution portrait.
///
/// Runs against the final image rather than preview frames — the project's
/// guiding rule is that live guidance may be approximate, but the checks a
/// host actually acts on run against what was really captured.
///
/// [motion] cannot be evaluated here: judging camera-shake from a single
/// still frame with no gyroscope trace is not implemented, so that check is
/// always reported as [QualityCheckOutcome.notEvaluated] rather than guessed
/// at from sharpness (motion blur and defocus blur are different things, and
/// conflating them would misreport the cause).
PortraitFinalAnalysis analyzePortraitCapture({
  required List<Face> faces,
  required int imageWidth,
  required int imageHeight,
  required ImageMetrics metrics,
  required PortraitQualityThresholds thresholds,
}) {
  final checks = <QualityCheck>[];

  checks.add(QualityCheck(
    id: QualityCheckId.faceCount,
    outcome: faces.length == 1
        ? QualityCheckOutcome.pass
        : QualityCheckOutcome.fail,
    measuredValue: faces.length.toDouble(),
  ));

  FaceAnalysis? faceAnalysis;
  if (faces.length == 1) {
    final face = faces.single;
    final box = NormalizedRect.fromPixels(
      left: face.boundingBox.left,
      top: face.boundingBox.top,
      right: face.boundingBox.right,
      bottom: face.boundingBox.bottom,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    faceAnalysis = FaceAnalysis(
      boundingBox: box,
      yawDegrees: face.headEulerAngleY,
      pitchDegrees: face.headEulerAngleX,
      rollDegrees: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      trackingId: face.trackingId,
    );

    final heightFraction = box.height;
    checks.add(QualityCheck(
      id: QualityCheckId.faceSize,
      outcome: heightFraction < thresholds.minFaceHeightFraction
          ? QualityCheckOutcome.fail
          : heightFraction > thresholds.maxFaceHeightFraction
              ? QualityCheckOutcome.fail
              : QualityCheckOutcome.pass,
      measuredValue: heightFraction,
      threshold: thresholds.minFaceHeightFraction,
    ));

    final horizontalOffset = (box.center.x - 0.5).abs();
    final verticalOffset = (box.center.y - 0.5).abs();
    final centeringOffset = horizontalOffset > verticalOffset
        ? horizontalOffset
        : verticalOffset;
    checks.add(QualityCheck(
      id: QualityCheckId.faceCentering,
      outcome: horizontalOffset > thresholds.maxHorizontalOffset ||
              verticalOffset > thresholds.maxVerticalOffset
          ? QualityCheckOutcome.fail
          : QualityCheckOutcome.pass,
      measuredValue: centeringOffset,
      threshold: thresholds.maxHorizontalOffset,
    ));

    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    final roll = face.headEulerAngleZ;
    if (yaw == null && pitch == null && roll == null) {
      checks.add(const QualityCheck.notEvaluated(
        QualityCheckId.headOrientation,
        detail: 'The detector reported no head-pose angles for this face.',
      ));
    } else {
      final yawOk = yaw == null || yaw.abs() <= thresholds.maxYawDegrees;
      final pitchOk = pitch == null || pitch.abs() <= thresholds.maxPitchDegrees;
      final rollOk = roll == null || roll.abs() <= thresholds.maxRollDegrees;
      checks.add(QualityCheck(
        id: QualityCheckId.headOrientation,
        outcome: yawOk && pitchOk && rollOk
            ? QualityCheckOutcome.pass
            : QualityCheckOutcome.fail,
        measuredValue: [
          yaw?.abs() ?? 0,
          pitch?.abs() ?? 0,
          roll?.abs() ?? 0,
        ].reduce((a, b) => a > b ? a : b),
        threshold: thresholds.maxYawDegrees,
      ));
    }

    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null && right == null) {
      checks.add(const QualityCheck.notEvaluated(QualityCheckId.eyesOpen));
    } else {
      final minProb = [left ?? 1.0, right ?? 1.0].reduce((a, b) => a < b ? a : b);
      final passes = minProb >= thresholds.minEyeOpenProbability;
      checks.add(QualityCheck(
        id: QualityCheckId.eyesOpen,
        outcome: passes
            ? QualityCheckOutcome.pass
            : thresholds.requireEyesOpen
                ? QualityCheckOutcome.fail
                : QualityCheckOutcome.warn,
        measuredValue: minProb,
        threshold: thresholds.minEyeOpenProbability,
      ));
    }
  } else {
    // With zero or several faces there is no single face to judge framing,
    // orientation or eyes against. Reporting these as notEvaluated is more
    // honest than reporting a pass or fail for a check that could not
    // meaningfully run.
    for (final id in [
      QualityCheckId.faceSize,
      QualityCheckId.faceCentering,
      QualityCheckId.headOrientation,
      QualityCheckId.eyesOpen,
    ]) {
      checks.add(QualityCheck.notEvaluated(
        id,
        detail: faces.isEmpty
            ? 'No face was detected in the final image.'
            : 'Multiple faces were detected; no single face to evaluate.',
      ));
    }
  }

  checks.add(QualityCheck(
    id: QualityCheckId.exposure,
    outcome: metrics.meanBrightness < thresholds.minBrightness
        ? QualityCheckOutcome.fail
        : metrics.meanBrightness > thresholds.maxBrightness
            ? QualityCheckOutcome.fail
            : QualityCheckOutcome.pass,
    measuredValue: metrics.meanBrightness,
    threshold: thresholds.minBrightness,
  ));

  checks.add(QualityCheck(
    id: QualityCheckId.sharpness,
    outcome: metrics.sharpness < thresholds.minSharpness
        ? QualityCheckOutcome.fail
        : QualityCheckOutcome.pass,
    measuredValue: metrics.sharpness,
    threshold: thresholds.minSharpness,
  ));

  checks.add(const QualityCheck.notEvaluated(
    QualityCheckId.motion,
    detail: 'Motion during capture is not evaluated from a single still '
        'frame in this release.',
  ));

  return PortraitFinalAnalysis(
    qualityReport: QualityReport(checks),
    faceCount: faces.length,
    face: faceAnalysis,
  );
}
