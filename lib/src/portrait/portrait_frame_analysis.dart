import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../common/guidance.dart';
import 'portrait_options.dart';

/// A single instruction plus the face box it was computed from, for drawing
/// the live overlay.
class PortraitGuidanceState {
  const PortraitGuidanceState({
    required this.guidance,
    this.faceBoxInImage,
    this.imageSize,
  });

  const PortraitGuidanceState.initial()
      : guidance = CaptureGuidance.noFaceDetected,
        faceBoxInImage = null,
        imageSize = null;

  final CaptureGuidance guidance;

  /// The detected face's bounding box in the coordinate space of the analyzed
  /// frame — not yet normalized, because the caller needs [imageSize] to do
  /// that against the correct (possibly rotated) frame dimensions.
  final Rect? faceBoxInImage;

  final Size? imageSize;

  bool get isReady => guidance == CaptureGuidance.ready;
}

/// Turns one frame's detected faces into a single, prioritized
/// [PortraitGuidanceState].
///
/// Only one instruction is surfaced at a time — showing "move closer" and
/// "look straight ahead" simultaneously is not actionable. Priority order:
/// face count problems first (nothing else can be judged without exactly one
/// face), then framing, then orientation, then stillness/readiness.
PortraitGuidanceState analyzePortraitFrame({
  required List<Face> faces,
  required double imageWidth,
  required double imageHeight,
  required PortraitQualityThresholds thresholds,
}) {
  if (faces.isEmpty) {
    return const PortraitGuidanceState(guidance: CaptureGuidance.noFaceDetected);
  }
  if (faces.length > 1) {
    return const PortraitGuidanceState(
      guidance: CaptureGuidance.multipleFacesDetected,
    );
  }

  final face = faces.single;
  final box = face.boundingBox;
  final size = Size(imageWidth, imageHeight);

  final faceHeightFraction = box.height / imageHeight;
  if (faceHeightFraction < thresholds.minFaceHeightFraction) {
    return PortraitGuidanceState(
      guidance: CaptureGuidance.moveCloser,
      faceBoxInImage: box,
      imageSize: size,
    );
  }
  if (faceHeightFraction > thresholds.maxFaceHeightFraction) {
    return PortraitGuidanceState(
      guidance: CaptureGuidance.moveFarther,
      faceBoxInImage: box,
      imageSize: size,
    );
  }

  final centerXFraction = box.center.dx / imageWidth;
  final centerYFraction = box.center.dy / imageHeight;
  final horizontalOffset = centerXFraction - 0.5;
  final verticalOffset = centerYFraction - 0.5;

  if (horizontalOffset.abs() > thresholds.maxHorizontalOffset) {
    return PortraitGuidanceState(
      // The face's on-screen position and the guidance direction are
      // opposite: if the face sits left of center, the subject must move
      // right to recenter it.
      guidance:
          horizontalOffset < 0 ? CaptureGuidance.moveRight : CaptureGuidance.moveLeft,
      faceBoxInImage: box,
      imageSize: size,
    );
  }
  if (verticalOffset.abs() > thresholds.maxVerticalOffset) {
    return PortraitGuidanceState(
      guidance:
          verticalOffset < 0 ? CaptureGuidance.moveDown : CaptureGuidance.moveUp,
      faceBoxInImage: box,
      imageSize: size,
    );
  }

  final yaw = face.headEulerAngleY;
  final roll = face.headEulerAngleZ;
  if ((yaw != null && yaw.abs() > thresholds.maxYawDegrees) ||
      (roll != null && roll.abs() > thresholds.maxRollDegrees)) {
    return PortraitGuidanceState(
      guidance: CaptureGuidance.lookStraightAhead,
      faceBoxInImage: box,
      imageSize: size,
    );
  }

  if (thresholds.requireEyesOpen) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    final eitherClosed = (left != null && left < thresholds.minEyeOpenProbability) ||
        (right != null && right < thresholds.minEyeOpenProbability);
    if (eitherClosed) {
      return PortraitGuidanceState(
        guidance: CaptureGuidance.openEyes,
        faceBoxInImage: box,
        imageSize: size,
      );
    }
  }

  return PortraitGuidanceState(
    guidance: CaptureGuidance.ready,
    faceBoxInImage: box,
    imageSize: size,
  );
}
