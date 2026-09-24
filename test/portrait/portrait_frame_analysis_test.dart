import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';
import 'package:smart_capture_kit/src/portrait/portrait_frame_analysis.dart';

Face _face({
  required Rect box,
  double? yaw,
  double? roll,
  double? leftEyeOpen,
  double? rightEyeOpen,
}) {
  return Face(
    boundingBox: box,
    landmarks: const {},
    contours: const {},
    headEulerAngleY: yaw,
    headEulerAngleZ: roll,
    leftEyeOpenProbability: leftEyeOpen,
    rightEyeOpenProbability: rightEyeOpen,
  );
}

void main() {
  const thresholds = PortraitQualityThresholds();
  const imageWidth = 1000.0;
  const imageHeight = 1000.0;

  // A face centred in frame at a height fraction comfortably inside the
  // default [0.30, 0.80] band, facing forward.
  Rect centeredFace({double heightFraction = 0.5}) {
    final height = imageHeight * heightFraction;
    final width = height * 0.75;
    final top = (imageHeight - height) / 2;
    final left = (imageWidth - width) / 2;
    return Rect.fromLTWH(left, top, width, height);
  }

  group('analyzePortraitFrame', () {
    test('no faces reports noFaceDetected', () {
      final state = analyzePortraitFrame(
        faces: const [],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.noFaceDetected);
      expect(state.isReady, isFalse);
    });

    test('more than one face reports multipleFacesDetected', () {
      final state = analyzePortraitFrame(
        faces: [
          _face(box: centeredFace()),
          _face(box: centeredFace()),
        ],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.multipleFacesDetected);
    });

    test('a small face reports moveCloser', () {
      final state = analyzePortraitFrame(
        faces: [_face(box: centeredFace(heightFraction: 0.10))],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.moveCloser);
    });

    test('a face filling the frame reports moveFarther', () {
      final state = analyzePortraitFrame(
        faces: [_face(box: centeredFace(heightFraction: 0.95))],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.moveFarther);
    });

    test('a face left of center asks the subject to move right', () {
      final box = Rect.fromLTWH(0, 350, 300, 500);
      final state = analyzePortraitFrame(
        faces: [_face(box: box)],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.moveRight);
    });

    test('a face right of center asks the subject to move left', () {
      final box = Rect.fromLTWH(700, 350, 300, 500);
      final state = analyzePortraitFrame(
        faces: [_face(box: box)],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.moveLeft);
    });

    test('a face above center asks the subject to move down', () {
      final box = Rect.fromLTWH(350, 0, 375, 500);
      final state = analyzePortraitFrame(
        faces: [_face(box: box)],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.moveDown);
    });

    test('excess yaw reports lookStraightAhead', () {
      final state = analyzePortraitFrame(
        faces: [_face(box: centeredFace(), yaw: 30)],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.lookStraightAhead);
    });

    test('excess roll reports lookStraightAhead', () {
      final state = analyzePortraitFrame(
        faces: [_face(box: centeredFace(), roll: 25)],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.lookStraightAhead);
    });

    test('closed eyes are ignored unless requireEyesOpen is set', () {
      final state = analyzePortraitFrame(
        faces: [
          _face(box: centeredFace(), leftEyeOpen: 0.1, rightEyeOpen: 0.1),
        ],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.ready);
    });

    test('closed eyes report openEyes when requireEyesOpen is set', () {
      final state = analyzePortraitFrame(
        faces: [
          _face(box: centeredFace(), leftEyeOpen: 0.1, rightEyeOpen: 0.9),
        ],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: const PortraitQualityThresholds(requireEyesOpen: true),
      );
      expect(state.guidance, CaptureGuidance.openEyes);
    });

    test('a well-framed, forward-facing face reports ready', () {
      final state = analyzePortraitFrame(
        faces: [_face(box: centeredFace(), yaw: 2, roll: 1)],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.ready);
      expect(state.isReady, isTrue);
      expect(state.faceBoxInImage, isNotNull);
    });

    test('face count problems take priority over framing', () {
      // Two faces, one of which is badly framed: the count problem must win.
      final state = analyzePortraitFrame(
        faces: [
          _face(box: centeredFace(heightFraction: 0.05)),
          _face(box: centeredFace()),
        ],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        thresholds: thresholds,
      );
      expect(state.guidance, CaptureGuidance.multipleFacesDetected);
    });
  });
}
