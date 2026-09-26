import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';
import 'package:smart_capture_kit/src/common/image_metrics.dart';
import 'package:smart_capture_kit/src/document/document_boundary_detection.dart';
import 'package:smart_capture_kit/src/document/document_final_analysis.dart';

void main() {
  const thresholds = DocumentQualityThresholds();
  const expectedRatio = idCardAspectRatioId1;
  const goodMetrics = ImageMetrics(meanBrightness: 0.5, sharpness: 0.8);

  // An ID-1 card filling ~55% of a 4:3 landscape image, fronto-parallel.
  DocumentBoundaryDetection wellFramedDetection() {
    const imageAspect = 4 / 3;
    const height = 0.7;
    const width = height * expectedRatio / imageAspect;
    const left = (1 - width) / 2, top = (1 - height) / 2;
    return const DocumentBoundaryDetection(
      quad: Quad(
        topLeft: NormalizedPoint(left, top),
        topRight: NormalizedPoint(left + width, top),
        bottomRight: NormalizedPoint(left + width, top + height),
        bottomLeft: NormalizedPoint(left, top + height),
      ),
      confidence: 0.8,
      imageAspectRatio: imageAspect,
    );
  }

  QualityCheckOutcome outcomeOf(DocumentFinalAnalysis a, QualityCheckId id) =>
      a.qualityReport.checks.firstWhere((c) => c.id == id).outcome;

  group('analyzeDocumentCapture', () {
    test(
      'a well-framed, sharp, glare-free card passes every evaluated check',
      () {
        final analysis = analyzeDocumentCapture(
          detection: wellFramedDetection(),
          metrics: goodMetrics,
          glareFraction: 0.01,
          expectedAspectRatio: expectedRatio,
          thresholds: thresholds,
          aspectRatioTolerance: 0.15,
        );
        expect(analysis.quad, isNotNull);
        expect(analysis.qualityReport.hasFailures, isFalse);
        expect(
          outcomeOf(analysis, QualityCheckId.documentAspectRatio),
          QualityCheckOutcome.pass,
        );
        expect(
          outcomeOf(analysis, QualityCheckId.motion),
          QualityCheckOutcome.notEvaluated,
        );
      },
    );

    test('no detection fails corners and leaves geometry unevaluated', () {
      final analysis = analyzeDocumentCapture(
        detection: null,
        metrics: goodMetrics,
        glareFraction: null,
        expectedAspectRatio: expectedRatio,
        thresholds: thresholds,
        aspectRatioTolerance: 0.15,
      );
      expect(
        outcomeOf(analysis, QualityCheckId.documentCornersDetected),
        QualityCheckOutcome.fail,
      );
      for (final id in [
        QualityCheckId.documentWithinFrame,
        QualityCheckId.documentPerspective,
        QualityCheckId.documentSize,
        QualityCheckId.documentAspectRatio,
        QualityCheckId.glare,
      ]) {
        expect(
          outcomeOf(analysis, id),
          QualityCheckOutcome.notEvaluated,
          reason: id.name,
        );
      }
    });

    test('glare above the threshold fails', () {
      final analysis = analyzeDocumentCapture(
        detection: wellFramedDetection(),
        metrics: goodMetrics,
        glareFraction: 0.2,
        expectedAspectRatio: expectedRatio,
        thresholds: thresholds,
        aspectRatioTolerance: 0.15,
      );
      expect(
        outcomeOf(analysis, QualityCheckId.glare),
        QualityCheckOutcome.fail,
      );
    });

    test('dark and blurry images fail exposure and sharpness', () {
      final analysis = analyzeDocumentCapture(
        detection: wellFramedDetection(),
        metrics: const ImageMetrics(meanBrightness: 0.05, sharpness: 0.1),
        glareFraction: 0,
        expectedAspectRatio: expectedRatio,
        thresholds: thresholds,
        aspectRatioTolerance: 0.15,
      );
      expect(
        outcomeOf(analysis, QualityCheckId.exposure),
        QualityCheckOutcome.fail,
      );
      expect(
        outcomeOf(analysis, QualityCheckId.sharpness),
        QualityCheckOutcome.fail,
      );
    });
  });

  group('rectificationAspectRatio', () {
    test('keeps the expected ratio for a landscape card', () {
      expect(
        rectificationAspectRatio(measured: 1.55, expected: expectedRatio),
        expectedRatio,
      );
    });

    test('inverts for a card held upright', () {
      expect(
        rectificationAspectRatio(measured: 0.64, expected: expectedRatio),
        closeTo(1 / expectedRatio, 1e-9),
      );
    });

    test('falls back to the expected ratio when nothing was measured', () {
      expect(
        rectificationAspectRatio(measured: null, expected: expectedRatio),
        expectedRatio,
      );
    });
  });
}
