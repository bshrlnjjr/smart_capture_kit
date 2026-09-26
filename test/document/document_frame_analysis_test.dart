import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';
import 'package:smart_capture_kit/src/document/document_boundary_detection.dart';
import 'package:smart_capture_kit/src/document/document_frame_analysis.dart';

void main() {
  const thresholds = DocumentQualityThresholds();
  const expectedRatio = idCardAspectRatioId1;

  DocumentBoundaryDetection detectionFor(Quad quad, {double confidence = 0.8}) =>
      DocumentBoundaryDetection(
        quad: quad,
        confidence: confidence,
        imageAspectRatio: 1,
      );

  // A well-framed card matching the ID-1 ratio, comfortably sized, centered,
  // with no perspective distortion.
  Quad wellFramedQuad() {
    const height = 0.6;
    final width = height * expectedRatio;
    final left = (1 - width) / 2;
    final top = (1 - height) / 2;
    return Quad(
      topLeft: NormalizedPoint(left, top),
      topRight: NormalizedPoint(left + width, top),
      bottomRight: NormalizedPoint(left + width, top + height),
      bottomLeft: NormalizedPoint(left, top + height),
    );
  }

  group('analyzeDocumentFrame', () {
    test('no detection reports noDocumentDetected', () {
      final state = analyzeDocumentFrame(
        detection: null,
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.noDocumentDetected);
      expect(state.isReady, isFalse);
    });

    test('a corner outside the frame reports fitAllCornersInFrame', () {
      const quad = Quad(
        topLeft: NormalizedPoint(-0.05, 0.2),
        topRight: NormalizedPoint(0.8, 0.2),
        bottomRight: NormalizedPoint(0.8, 0.8),
        bottomLeft: NormalizedPoint(0.1, 0.8),
      );
      final state = analyzeDocumentFrame(
        detection: detectionFor(quad),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.fitAllCornersInFrame);
      expect(state.quad, quad); // shown on the overlay despite the problem
    });

    test('a small document reports moveCloserToDocument', () {
      const quad = Quad(
        topLeft: NormalizedPoint(0.45, 0.45),
        topRight: NormalizedPoint(0.55, 0.45),
        bottomRight: NormalizedPoint(0.55, 0.55),
        bottomLeft: NormalizedPoint(0.45, 0.55),
      );
      final state = analyzeDocumentFrame(
        detection: detectionFor(quad),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.moveCloserToDocument);
    });

    test('excess perspective distortion reports holdDeviceFlat', () {
      // Large enough to pass the size check (area ~0.42) but with the top
      // edge much narrower than the bottom edge, as a card tilted away from
      // the camera would appear.
      const quad = Quad(
        topLeft: NormalizedPoint(0.35, 0.15),
        topRight: NormalizedPoint(0.65, 0.15),
        bottomRight: NormalizedPoint(0.95, 0.85),
        bottomLeft: NormalizedPoint(0.05, 0.85),
      );
      final state = analyzeDocumentFrame(
        detection: detectionFor(quad),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.holdDeviceFlat);
    });

    test('a shape far from the expected aspect ratio reports '
        'unexpectedDocumentShape', () {
      // A large, axis-aligned, but near-square quad — nothing like an ID-1
      // card's ~1.586 ratio in either orientation.
      const quad = Quad(
        topLeft: NormalizedPoint(0.175, 0.175),
        topRight: NormalizedPoint(0.825, 0.175),
        bottomRight: NormalizedPoint(0.825, 0.825),
        bottomLeft: NormalizedPoint(0.175, 0.825),
      );
      final state = analyzeDocumentFrame(
        detection: detectionFor(quad),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.unexpectedDocumentShape);
    });

    test('a card held portrait-orientation (rotated 90 degrees) is accepted '
        'via the inverted ratio check', () {
      // height/width = expectedRatio when the card is turned on its side;
      // area comfortably above the minimum.
      const height = 0.75;
      const width = height / expectedRatio; // ~0.4725
      const quad = Quad(
        topLeft: NormalizedPoint((1 - width) / 2, (1 - height) / 2),
        topRight: NormalizedPoint((1 - width) / 2 + width, (1 - height) / 2),
        bottomRight:
            NormalizedPoint((1 - width) / 2 + width, (1 - height) / 2 + height),
        bottomLeft: NormalizedPoint((1 - width) / 2, (1 - height) / 2 + height),
      );
      final state = analyzeDocumentFrame(
        detection: detectionFor(quad),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.ready);
    });

    test('a well-framed card reports ready', () {
      final state = analyzeDocumentFrame(
        detection: detectionFor(wellFramedQuad()),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.ready);
      expect(state.isReady, isTrue);
      expect(state.confidence, greaterThan(0));
    });

    test('corner-in-frame and size problems take priority over shape', () {
      // Small AND badly shaped: size should win since nothing about shape
      // can be trusted from a document this small anyway.
      const quad = Quad(
        topLeft: NormalizedPoint(0.48, 0.48),
        topRight: NormalizedPoint(0.52, 0.48),
        bottomRight: NormalizedPoint(0.52, 0.52),
        bottomLeft: NormalizedPoint(0.48, 0.52),
      );
      final state = analyzeDocumentFrame(
        detection: detectionFor(quad),
        thresholds: thresholds,
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.moveCloserToDocument);
    });

    test('an ID-1 card in a non-square (3:4 portrait) frame reads as ready',
        () {
      // 900x567 px card (ID-1) centered in a 1200x1600 px frame. Normalized
      // width 0.75 vs height ~0.354 would read as ~2.1 if the frame's own
      // aspect ratio were ignored, and fail the shape check.
      const frameWidth = 1200.0, frameHeight = 1600.0;
      const cardWidth = 900.0, cardHeight = 900.0 / expectedRatio;
      const left = (frameWidth - cardWidth) / 2 / frameWidth;
      const right = (frameWidth + cardWidth) / 2 / frameWidth;
      const top = (frameHeight - cardHeight) / 2 / frameHeight;
      const bottom = (frameHeight + cardHeight) / 2 / frameHeight;
      const quad = Quad(
        topLeft: NormalizedPoint(left, top),
        topRight: NormalizedPoint(right, top),
        bottomRight: NormalizedPoint(right, bottom),
        bottomLeft: NormalizedPoint(left, bottom),
      );
      final state = analyzeDocumentFrame(
        detection: const DocumentBoundaryDetection(
          quad: quad,
          confidence: 0.8,
          imageAspectRatio: frameWidth / frameHeight,
        ),
        thresholds: const DocumentQualityThresholds(
          minDocumentAreaFraction: 0.2,
        ),
        expectedAspectRatio: expectedRatio,
        aspectRatioTolerance: 0.15,
      );
      expect(state.guidance, CaptureGuidance.ready);
    });
  });
}
