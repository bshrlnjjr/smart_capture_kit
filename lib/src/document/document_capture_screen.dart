import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../common/capture_review.dart';
import '../common/capture_widgets.dart';
import '../common/errors.dart';
import '../common/labels.dart';
import '../ocr/ocr_models.dart';
import 'document_capture_controller.dart';
import 'document_frame_analysis.dart';
import 'document_options.dart';
import 'document_result.dart';
import 'document_review_screen.dart';

/// Default document capture screen, pushed by [SmartCapture.captureDocument].
///
/// Walks through the front and, when [DocumentCaptureOptions.sides] asks for
/// it, the back, with a review step after each side. Pops with a
/// [DocumentCaptureResult] on success, `null` on user cancel, or a
/// [SmartCaptureException] for the facade to rethrow — the same contract as
/// the portrait screen.
///
/// Files from a side that was captured but never handed to the host (a
/// retake, or a cancel after the front was accepted) are deleted here, so an
/// abandoned identity-document image never lingers in the temporary
/// directory.
class DocumentCaptureScreen extends StatefulWidget {
  const DocumentCaptureScreen({super.key, required this.options});

  final DocumentCaptureOptions options;

  @override
  State<DocumentCaptureScreen> createState() => _DocumentCaptureScreenState();
}

/// How long the frame must stay in [CaptureGuidance.ready] before the screen
/// captures automatically. The manual shutter stays available throughout.
const Duration _autoCaptureSustainDuration = Duration(milliseconds: 700);

class _DocumentCaptureScreenState extends State<DocumentCaptureScreen> {
  late final DocumentCaptureController _controller;
  late final SmartCaptureLabels _labels;

  Object? _initError;
  bool _capturing = false;
  Timer? _autoCaptureTimer;

  DocumentSide _side = DocumentSide.front;
  DocumentSideCapture? _acceptedFront;

  /// Set once a result has been handed back, after which the files belong
  /// to the host and must not be deleted on dispose.
  bool _handedOff = false;

  String get _title => _side == DocumentSide.front
      ? _labels.documentFrontTitle
      : _labels.documentBackTitle;

  @override
  void initState() {
    super.initState();
    _labels = widget.options.labels ?? SmartCaptureLabels.english();
    _controller = DocumentCaptureController(options: widget.options);
    _controller.addListener(_onGuidanceChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
      return;
    }
    if (mounted) setState(() {});
  }

  void _onGuidanceChanged() {
    if (_controller.value.isReady) {
      _autoCaptureTimer ??= Timer(_autoCaptureSustainDuration, () {
        if (mounted && !_capturing && _controller.value.isReady) {
          unawaited(_capture());
        }
      });
    } else {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
    }
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;

    try {
      final capture = await _controller.captureSide(_side);
      if (!mounted) {
        await capture.dispose();
        return;
      }

      var continuedDespiteFailures = false;
      if (widget.options.showReviewScreen) {
        final outcome = await Navigator.of(context).push<CaptureReviewOutcome>(
          MaterialPageRoute(
            builder: (_) => DocumentReviewScreen(
              capture: capture,
              title: _title,
              labels: _labels,
              allowContinueOnFailedChecks:
                  widget.options.allowContinueOnFailedChecks,
            ),
          ),
        );
        if (!mounted) {
          await capture.dispose();
          return;
        }
        switch (outcome) {
          case ReviewAccepted(continuedDespiteFailures: final continued):
            continuedDespiteFailures = continued;
          case RetakeRequested():
          case null:
            // An explicit retake or a back-swipe off the review screen: both
            // mean "try this side again".
            await capture.dispose();
            setState(() => _capturing = false);
            await _controller.resumeLiveGuidance();
            return;
        }
      }

      final accepted = DocumentSideCapture(
        side: capture.side,
        originalImage: capture.originalImage,
        rectifiedImage: capture.rectifiedImage,
        detectedCorners: capture.detectedCorners,
        qualityReport: capture.qualityReport,
        userContinuedDespiteFailures: continuedDespiteFailures,
      );

      final needsBack =
          widget.options.sides == DocumentSides.frontAndBack &&
          _side == DocumentSide.front;
      if (needsBack) {
        setState(() {
          _acceptedFront = accepted;
          _side = DocumentSide.back;
          _capturing = false;
        });
        await _controller.resumeLiveGuidance();
        return;
      }

      if (!mounted) {
        await accepted.dispose();
        return;
      }
      final front = _acceptedFront ?? accepted;
      final back = _acceptedFront == null ? null : accepted;
      _handedOff = true;
      Navigator.of(context).pop(
        DocumentCaptureResult(
          profileId: _controller.profile.id,
          front: front,
          back: back,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(
        e is SmartCaptureException
            ? e
            : SmartCaptureException(
                code: SmartCaptureErrorCode.captureFailed,
                message: 'Document capture failed.',
                cause: e,
              ),
      );
    }
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _controller.removeListener(_onGuidanceChanged);
    unawaited(_controller.dispose());
    if (!_handedOff) {
      unawaited(_acceptedFront?.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _labels.textDirection == SmartCaptureTextDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _initError;
    if (error != null) {
      return PermissionOrErrorView(error: error, labels: _labels);
    }
    if (!_controller.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final camera = _controller.cameraController!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          // CameraPreview sizes itself to the upright preview and lays its
          // child over exactly that box, which is the space the detected
          // quad is normalized against.
          child: CameraPreview(
            camera,
            child: ValueListenableBuilder<DocumentGuidanceState>(
              valueListenable: _controller,
              builder: (context, state, _) => CustomPaint(
                painter: _DocumentOverlayPainter(
                  state: state,
                  expectedAspectRatio:
                      widget.options.aspectRatioOverride ??
                      _controller.profile.aspectRatio,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 96,
          child: Center(
            child: ValueListenableBuilder<DocumentGuidanceState>(
              valueListenable: _controller,
              builder: (context, state, _) => GuidanceBanner(
                text: _labels.guidanceText(state.guidance),
                isReady: state.isReady,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: CaptureButton(enabled: !_capturing, onPressed: _capture),
          ),
        ),
        if (_capturing)
          const ColoredBox(
            color: Color(0x88000000),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// Draws a card-shaped target guide plus the boundary detected in the latest
/// analyzed frame.
///
/// The target is only a visual aim point: guidance is driven by the detected
/// quad's own size, shape and position (see [analyzeDocumentFrame]), not by
/// whether it lines up with this rectangle.
class _DocumentOverlayPainter extends CustomPainter {
  _DocumentOverlayPainter({
    required this.state,
    required this.expectedAspectRatio,
  });

  final DocumentGuidanceState state;
  final double expectedAspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    // Card laid across the preview in whichever orientation fits it best.
    final landscapeCard = expectedAspectRatio >= 1;
    final cardRatio = size.width >= size.height == landscapeCard
        ? expectedAspectRatio
        : 1 / expectedAspectRatio;
    var targetWidth = size.width * 0.88;
    var targetHeight = targetWidth / cardRatio;
    if (targetHeight > size.height * 0.88) {
      targetHeight = size.height * 0.88;
      targetWidth = targetHeight * cardRatio;
    }
    final target = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: targetWidth,
        height: targetHeight,
      ),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      target,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final quad = state.quad;
    if (quad != null) {
      QuadPainter(
        quad: quad,
        color: state.isReady ? Colors.greenAccent : Colors.amberAccent,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentOverlayPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.expectedAspectRatio != expectedAspectRatio;
}
