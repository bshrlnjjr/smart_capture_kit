import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../common/errors.dart';
import '../common/guidance.dart';
import '../common/labels.dart';
import 'portrait_capture_controller.dart';
import 'portrait_frame_analysis.dart';
import 'portrait_options.dart';
import 'portrait_result.dart';
import 'portrait_review_screen.dart';

/// Default portrait capture screen, pushed by [SmartCapture.capturePortrait].
///
/// Pops with a [PortraitCaptureResult] on success, `null` on user cancel, or
/// a [SmartCaptureException] wrapped so the facade can rethrow it — a
/// [StatefulWidget] has no `try`/`catch` boundary the caller can see through,
/// so the error crosses the [Navigator] as data instead.
class PortraitCaptureScreen extends StatefulWidget {
  const PortraitCaptureScreen({super.key, required this.options});

  final PortraitCaptureOptions options;

  @override
  State<PortraitCaptureScreen> createState() => _PortraitCaptureScreenState();
}

/// How long the frame must stay in [CaptureGuidance.ready] before the screen
/// captures automatically. A fixed manual capture button remains available at
/// every moment, so a user who cannot hold the pose for this long is never
/// stuck waiting on auto-capture.
const Duration _autoCaptureSustainDuration = Duration(milliseconds: 700);

class _PortraitCaptureScreenState extends State<PortraitCaptureScreen> {
  late final PortraitCaptureController _controller;
  late final SmartCaptureLabels _labels;

  Object? _initError;
  bool _capturing = false;
  DateTime? _readySince;
  Timer? _autoCaptureTimer;

  @override
  void initState() {
    super.initState();
    _labels = widget.options.labels ?? SmartCaptureLabels.english();
    _controller = PortraitCaptureController(options: widget.options);
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
    final state = _controller.value;
    if (state.isReady) {
      _readySince ??= DateTime.now();
      _autoCaptureTimer ??= Timer(_autoCaptureSustainDuration, () {
        if (mounted && !_capturing && _controller.value.isReady) {
          unawaited(_capture());
        }
      });
    } else {
      _readySince = null;
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;

    try {
      final result = await _controller.captureAndAnalyze();
      if (!mounted) return;

      if (!widget.options.showReviewScreen) {
        Navigator.of(context).pop(result);
        return;
      }

      final outcome = await Navigator.of(context).push<PortraitReviewOutcome>(
        MaterialPageRoute(
          builder: (_) => PortraitReviewScreen(
            result: result,
            labels: _labels,
            allowContinueOnFailedChecks:
                widget.options.allowContinueOnFailedChecks,
          ),
        ),
      );

      if (!mounted) return;
      switch (outcome) {
        case ReviewAccepted(continuedDespiteFailures: final continued):
          Navigator.of(context).pop(
            PortraitCaptureResult(
              originalImage: result.originalImage,
              croppedImage: result.croppedImage,
              qualityReport: result.qualityReport,
              face: result.face,
              faceCount: result.faceCount,
              userContinuedDespiteFailures: continued,
            ),
          );
        case RetakeRequested():
        case null:
          // Either an explicit retake or a back-swipe off the review screen:
          // both mean "keep going", so discard this attempt's files and
          // resume live guidance rather than leaving stale ones around.
          await result.dispose();
          setState(() => _capturing = false);
          await _controller.resumeLiveGuidance();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(e is SmartCaptureException ? e : SmartCaptureException(
        code: SmartCaptureErrorCode.captureFailed,
        message: 'Portrait capture failed.',
        cause: e,
      ));
    }
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _controller.removeListener(_onGuidanceChanged);
    unawaited(_controller.dispose());
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
          title: Text(_labels.portraitTitle),
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
      return _PermissionOrErrorView(error: error, labels: _labels);
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
          child: AspectRatio(
            aspectRatio: camera.value.aspectRatio,
            child: CameraPreview(camera),
          ),
        ),
        Positioned.fill(
          child: ValueListenableBuilder<PortraitGuidanceState>(
            valueListenable: _controller,
            builder: (context, state, _) => CustomPaint(
              painter: _PortraitOverlayPainter(
                isReady: state.isReady,
                aspectRatio: widget.options.outputAspectRatio,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 96,
          child: Center(
            child: ValueListenableBuilder<PortraitGuidanceState>(
              valueListenable: _controller,
              builder: (context, state, _) => _GuidanceBanner(
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
            child: _CaptureButton(
              enabled: !_capturing,
              onPressed: _capture,
            ),
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

class _PermissionOrErrorView extends StatelessWidget {
  const _PermissionOrErrorView({required this.error, required this.labels});

  final Object error;
  final SmartCaptureLabels labels;

  @override
  Widget build(BuildContext context) {
    final message = error is SmartCaptureException
        ? (error as SmartCaptureException).code ==
                    SmartCaptureErrorCode.cameraPermissionDenied ||
                (error as SmartCaptureException).code ==
                    SmartCaptureErrorCode.cameraPermissionPermanentlyDenied
            ? labels.cameraPermissionRequired
            : (error as SmartCaptureException).message
        : 'Camera failed to start.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            if (error is SmartCaptureException &&
                (error as SmartCaptureException).code ==
                    SmartCaptureErrorCode.cameraPermissionPermanentlyDenied) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(
                  error as SmartCaptureException,
                ),
                child: Text(labels.openSettings),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner({required this.text, required this.isReady});

  final String text;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isReady ? Colors.green.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: enabled ? 1 : 0.4),
          border: Border.all(color: Colors.black26, width: 3),
        ),
      ),
    );
  }
}

/// Draws the face-target guide over the camera preview.
///
/// Purely visual: the guide's shape does not feed back into the analysis in
/// [analyzePortraitFrame], which works from image fractions rather than
/// screen pixels. Keeping them separate means the overlay can be restyled
/// freely without touching guidance behaviour.
class _PortraitOverlayPainter extends CustomPainter {
  _PortraitOverlayPainter({required this.isReady, this.aspectRatio});

  final bool isReady;
  final double? aspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isReady ? Colors.greenAccent : Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final targetHeight = size.height * 0.55;
    final targetWidth = aspectRatio != null
        ? targetHeight * aspectRatio!
        : targetHeight * 0.72;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: targetWidth,
      height: targetHeight,
    );
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _PortraitOverlayPainter oldDelegate) =>
      oldDelegate.isReady != isReady || oldDelegate.aspectRatio != aspectRatio;
}
