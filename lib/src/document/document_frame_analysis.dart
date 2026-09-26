import '../common/geometry.dart';
import '../common/guidance.dart';
import 'document_boundary_detection.dart';
import 'document_options.dart';

/// A single instruction plus the detected boundary, for drawing the live
/// overlay and for the throttled analysis loop to compare frame to frame.
class DocumentGuidanceState {
  const DocumentGuidanceState({required this.guidance, this.quad, this.confidence});

  const DocumentGuidanceState.initial()
      : guidance = CaptureGuidance.noDocumentDetected,
        quad = null,
        confidence = null;

  final CaptureGuidance guidance;

  /// Normalized (0..1) detected boundary, when one was found at all —
  /// present even when [guidance] reports a problem with it (e.g. a corner
  /// outside the frame), so the overlay can still show what was seen.
  final Quad? quad;

  final double? confidence;

  bool get isReady => guidance == CaptureGuidance.ready;
}

/// Turns one frame's detected boundary into a single, prioritized
/// [DocumentGuidanceState].
///
/// Priority order mirrors the portrait guidance function for the same
/// reason: only one instruction is shown at a time, and a problem that makes
/// every other judgement meaningless (no boundary found at all) is reported
/// before anything about the boundary's shape or position.
DocumentGuidanceState analyzeDocumentFrame({
  required DocumentBoundaryDetection? detection,
  required DocumentQualityThresholds thresholds,
  required double expectedAspectRatio,
  required double aspectRatioTolerance,
}) {
  if (detection == null) {
    return const DocumentGuidanceState(guidance: CaptureGuidance.noDocumentDetected);
  }

  final quad = detection.quad;

  if (!quad.isFullyInsideImage) {
    return DocumentGuidanceState(
      guidance: CaptureGuidance.fitAllCornersInFrame,
      quad: quad,
      confidence: detection.confidence,
    );
  }

  if (quad.areaFraction < thresholds.minDocumentAreaFraction) {
    return DocumentGuidanceState(
      guidance: CaptureGuidance.moveCloserToDocument,
      quad: quad,
      confidence: detection.confidence,
    );
  }

  if (quad.perspectiveDistortion > thresholds.maxPerspectiveDistortion) {
    return DocumentGuidanceState(
      guidance: CaptureGuidance.holdDeviceFlat,
      quad: quad,
      confidence: detection.confidence,
    );
  }

  final estimatedRatio = quad.estimatedAspectRatio;
  if (estimatedRatio != null) {
    // Compared against the reciprocal too: a device held in the "wrong"
    // orientation relative to how the profile's ratio is expressed produces
    // a ratio that is the true one inverted, not merely off.
    final directDelta = (estimatedRatio - expectedAspectRatio).abs() / expectedAspectRatio;
    final invertedDelta =
        (estimatedRatio - 1 / expectedAspectRatio).abs() / (1 / expectedAspectRatio);
    if (directDelta > aspectRatioTolerance && invertedDelta > aspectRatioTolerance) {
      return DocumentGuidanceState(
        guidance: CaptureGuidance.unexpectedDocumentShape,
        quad: quad,
        confidence: detection.confidence,
      );
    }
  }

  return DocumentGuidanceState(
    guidance: CaptureGuidance.ready,
    quad: quad,
    confidence: detection.confidence,
  );
}
