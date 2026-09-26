import '../common/geometry.dart';
import '../common/image_metrics.dart';
import '../common/quality.dart';
import 'document_boundary_detection.dart';
import 'document_options.dart';

/// Everything the final, full-resolution document-side pass computed.
class DocumentFinalAnalysis {
  const DocumentFinalAnalysis({required this.qualityReport, this.quad});

  final QualityReport qualityReport;

  /// The detected boundary in the original (uncropped) capture, or `null`
  /// when none was found with reasonable confidence.
  final Quad? quad;
}

/// Builds the [QualityReport] for one captured, full-resolution document
/// side.
///
/// Runs against the final image rather than preview frames, for the same
/// reason the portrait pass does: live guidance may be approximate, but the
/// checks a host acts on run against what was actually captured.
///
/// [glareFraction] should be computed from the *rectified* image (or `null`
/// when rectification did not run) — see [computeGlareFraction] — so a light
/// source outside the document's edges never counts against it.
DocumentFinalAnalysis analyzeDocumentCapture({
  required DocumentBoundaryDetection? detection,
  required ImageMetrics metrics,
  required double? glareFraction,
  required double expectedAspectRatio,
  required DocumentQualityThresholds thresholds,
  required double aspectRatioTolerance,
}) {
  final checks = <QualityCheck>[];
  final quad = detection?.quad;

  checks.add(QualityCheck(
    id: QualityCheckId.documentCornersDetected,
    outcome: quad == null ? QualityCheckOutcome.fail : QualityCheckOutcome.pass,
    measuredValue: detection?.confidence,
  ));

  if (quad == null) {
    // Nothing below can be meaningfully judged without a boundary — reported
    // as notEvaluated rather than a guessed pass or fail.
    for (final id in [
      QualityCheckId.documentWithinFrame,
      QualityCheckId.documentPerspective,
      QualityCheckId.documentSize,
      QualityCheckId.documentAspectRatio,
    ]) {
      checks.add(QualityCheck.notEvaluated(
        id,
        detail: 'No document boundary was detected in the final image.',
      ));
    }
  } else {
    checks.add(QualityCheck(
      id: QualityCheckId.documentWithinFrame,
      outcome: quad.isFullyInsideImage
          ? QualityCheckOutcome.pass
          : QualityCheckOutcome.fail,
    ));

    checks.add(QualityCheck(
      id: QualityCheckId.documentPerspective,
      outcome: quad.perspectiveDistortion > thresholds.maxPerspectiveDistortion
          ? QualityCheckOutcome.fail
          : QualityCheckOutcome.pass,
      measuredValue: quad.perspectiveDistortion,
      threshold: thresholds.maxPerspectiveDistortion,
    ));

    checks.add(QualityCheck(
      id: QualityCheckId.documentSize,
      outcome: quad.areaFraction < thresholds.minDocumentAreaFraction
          ? QualityCheckOutcome.fail
          : QualityCheckOutcome.pass,
      measuredValue: quad.areaFraction,
      threshold: thresholds.minDocumentAreaFraction,
    ));

    final estimatedRatio = quad.estimatedAspectRatio;
    if (estimatedRatio == null) {
      checks.add(const QualityCheck.notEvaluated(
        QualityCheckId.documentAspectRatio,
        detail: 'The detected boundary was degenerate (zero height).',
      ));
    } else {
      final directDelta =
          (estimatedRatio - expectedAspectRatio).abs() / expectedAspectRatio;
      final invertedDelta = (estimatedRatio - 1 / expectedAspectRatio).abs() /
          (1 / expectedAspectRatio);
      final delta = directDelta < invertedDelta ? directDelta : invertedDelta;
      checks.add(QualityCheck(
        id: QualityCheckId.documentAspectRatio,
        outcome: delta > aspectRatioTolerance
            ? QualityCheckOutcome.warn
            : QualityCheckOutcome.pass,
        measuredValue: estimatedRatio,
        threshold: expectedAspectRatio,
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

  if (glareFraction == null) {
    checks.add(const QualityCheck.notEvaluated(
      QualityCheckId.glare,
      detail: 'Glare is measured on the rectified document image, which is '
          'not available without a detected boundary.',
    ));
  } else {
    checks.add(QualityCheck(
      id: QualityCheckId.glare,
      outcome: glareFraction > thresholds.maxGlareAreaFraction
          ? QualityCheckOutcome.fail
          : QualityCheckOutcome.pass,
      measuredValue: glareFraction,
      threshold: thresholds.maxGlareAreaFraction,
    ));
  }

  checks.add(const QualityCheck.notEvaluated(
    QualityCheckId.motion,
    detail: 'Motion during capture is not evaluated from a single still '
        'frame in this release.',
  ));

  return DocumentFinalAnalysis(qualityReport: QualityReport(checks), quad: quad);
}
