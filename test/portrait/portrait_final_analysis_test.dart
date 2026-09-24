import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';
import 'package:smart_capture_kit/src/common/image_metrics.dart';
import 'package:smart_capture_kit/src/portrait/portrait_final_analysis.dart';

Face _face({
  required Rect box,
  double? yaw,
  double? pitch,
  double? roll,
  double? leftEyeOpen,
  double? rightEyeOpen,
}) {
  return Face(
    boundingBox: box,
    landmarks: const {},
    contours: const {},
    headEulerAngleY: yaw,
    headEulerAngleX: pitch,
    headEulerAngleZ: roll,
    leftEyeOpenProbability: leftEyeOpen,
    rightEyeOpenProbability: rightEyeOpen,
  );
}

void main() {
  const thresholds = PortraitQualityThresholds();
  const goodMetrics = ImageMetrics(meanBrightness: 0.5, sharpness: 0.8);
  const width = 1000;
  const height = 1000;

  Rect wellFramedBox() => const Rect.fromLTWH(300, 250, 400, 500);

  group('analyzePortraitCapture', () {
    test('exactly one well-framed, forward-facing face passes every check',
        () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox(), yaw: 1, pitch: 1, roll: 1)],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );

      expect(analysis.faceCount, 1);
      expect(analysis.face, isNotNull);
      final report = analysis.qualityReport;
      expect(report[QualityCheckId.faceCount]!.passed, isTrue);
      expect(report[QualityCheckId.faceSize]!.passed, isTrue);
      expect(report[QualityCheckId.faceCentering]!.passed, isTrue);
      expect(report[QualityCheckId.headOrientation]!.passed, isTrue);
      expect(report[QualityCheckId.exposure]!.passed, isTrue);
      expect(report[QualityCheckId.sharpness]!.passed, isTrue);
    });

    test('zero faces fails faceCount and leaves face-specific checks '
        'notEvaluated rather than passed', () {
      final analysis = analyzePortraitCapture(
        faces: const [],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );

      expect(analysis.faceCount, 0);
      expect(analysis.face, isNull);
      final report = analysis.qualityReport;
      expect(report[QualityCheckId.faceCount]!.failed, isTrue);
      for (final id in [
        QualityCheckId.faceSize,
        QualityCheckId.faceCentering,
        QualityCheckId.headOrientation,
        QualityCheckId.eyesOpen,
      ]) {
        expect(report[id]!.outcome, QualityCheckOutcome.notEvaluated,
            reason: '${id.name} should not be silently passed with no face');
      }
    });

    test('two faces fails faceCount and evaluates nothing face-specific', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox()), _face(box: wellFramedBox())],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(analysis.qualityReport[QualityCheckId.faceCount]!.failed, isTrue);
      expect(analysis.face, isNull);
    });

    test('a face too small in frame fails faceSize', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: const Rect.fromLTWH(450, 450, 100, 100))],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(analysis.qualityReport[QualityCheckId.faceSize]!.failed, isTrue);
    });

    test('a face off-center fails faceCentering', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: const Rect.fromLTWH(0, 250, 400, 500))],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(
        analysis.qualityReport[QualityCheckId.faceCentering]!.failed,
        isTrue,
      );
    });

    test('excess yaw fails headOrientation', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox(), yaw: 45)],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(
        analysis.qualityReport[QualityCheckId.headOrientation]!.failed,
        isTrue,
      );
    });

    test('missing head-pose angles report headOrientation as notEvaluated, '
        'not passed', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox())],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(
        analysis.qualityReport[QualityCheckId.headOrientation]!.outcome,
        QualityCheckOutcome.notEvaluated,
      );
    });

    test('closed eyes warn rather than fail when requireEyesOpen is false',
        () {
      final analysis = analyzePortraitCapture(
        faces: [
          _face(box: wellFramedBox(), leftEyeOpen: 0.05, rightEyeOpen: 0.05),
        ],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(
        analysis.qualityReport[QualityCheckId.eyesOpen]!.outcome,
        QualityCheckOutcome.warn,
      );
    });

    test('closed eyes fail when requireEyesOpen is true', () {
      final analysis = analyzePortraitCapture(
        faces: [
          _face(box: wellFramedBox(), leftEyeOpen: 0.05, rightEyeOpen: 0.05),
        ],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: const PortraitQualityThresholds(requireEyesOpen: true),
      );
      expect(
        analysis.qualityReport[QualityCheckId.eyesOpen]!.failed,
        isTrue,
      );
    });

    test('missing eye-open probabilities report notEvaluated', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox())],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(
        analysis.qualityReport[QualityCheckId.eyesOpen]!.outcome,
        QualityCheckOutcome.notEvaluated,
      );
    });

    test('dark image fails exposure', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox(), yaw: 0, pitch: 0, roll: 0)],
        imageWidth: width,
        imageHeight: height,
        metrics: const ImageMetrics(meanBrightness: 0.05, sharpness: 0.8),
        thresholds: thresholds,
      );
      expect(analysis.qualityReport[QualityCheckId.exposure]!.failed, isTrue);
    });

    test('blurry image fails sharpness', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox(), yaw: 0, pitch: 0, roll: 0)],
        imageWidth: width,
        imageHeight: height,
        metrics: const ImageMetrics(meanBrightness: 0.5, sharpness: 0.02),
        thresholds: thresholds,
      );
      expect(analysis.qualityReport[QualityCheckId.sharpness]!.failed, isTrue);
    });

    test('motion is always reported as notEvaluated in this release', () {
      final analysis = analyzePortraitCapture(
        faces: [_face(box: wellFramedBox())],
        imageWidth: width,
        imageHeight: height,
        metrics: goodMetrics,
        thresholds: thresholds,
      );
      expect(
        analysis.qualityReport[QualityCheckId.motion]!.outcome,
        QualityCheckOutcome.notEvaluated,
      );
    });
  });
}
