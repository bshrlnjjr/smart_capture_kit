import 'package:flutter/material.dart';

import '../common/capture_image.dart';
import '../common/capture_review.dart';
import '../common/geometry.dart';
import '../common/labels.dart';
import 'document_result.dart';

/// Default review screen shown after each document side is captured.
///
/// Shows the rectified card when one was produced, with a toggle to the
/// original capture and the boundary that was detected in it — so a user can
/// see *why* a rectified image looks wrong, not just that it does. Every
/// quality check is listed, including passes.
///
/// Continue-despite-failures is gated by
/// [DocumentCaptureOptions.allowContinueOnFailedChecks], exactly as in the
/// portrait review screen.
class DocumentReviewScreen extends StatefulWidget {
  const DocumentReviewScreen({
    super.key,
    required this.capture,
    required this.title,
    required this.labels,
    required this.allowContinueOnFailedChecks,
  });

  final DocumentSideCapture capture;
  final String title;
  final SmartCaptureLabels labels;
  final bool allowContinueOnFailedChecks;

  @override
  State<DocumentReviewScreen> createState() => _DocumentReviewScreenState();
}

class _DocumentReviewScreenState extends State<DocumentReviewScreen> {
  late bool _showRectified = widget.capture.rectifiedImage != null;

  @override
  Widget build(BuildContext context) {
    final capture = widget.capture;
    final labels = widget.labels;
    final report = capture.qualityReport;
    final canContinue =
        widget.allowContinueOnFailedChecks || !report.hasFailures;
    final rectified = capture.rectifiedImage;

    return Directionality(
      textDirection: labels.textDirection == SmartCaptureTextDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: _showRectified && rectified != null
                      ? _ImageView(image: rectified)
                      : _ImageView(
                          image: capture.originalImage,
                          quad: capture.detectedCorners,
                        ),
                ),
              ),
            ),
            if (rectified != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.crop_free),
                      label: Text(labels.correctedImage),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.photo),
                      label: Text(labels.originalImage),
                    ),
                  ],
                  selected: {_showRectified},
                  onSelectionChanged: (s) =>
                      setState(() => _showRectified = s.first),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final check in report.checks)
                    QualityCheckTile(check: check),
                ],
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(const RetakeRequested()),
                      child: Text(labels.retake),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canContinue
                          ? () => Navigator.of(context).pop(
                              ReviewAccepted(
                                continuedDespiteFailures: report.hasFailures,
                              ),
                            )
                          : null,
                      child: Text(
                        report.hasFailures
                            ? labels.continueAnyway
                            : labels.usePhoto,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.image, this.quad});

  final CaptureImage image;
  final Quad? quad;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: image.aspectRatio == 0 ? 1 : image.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(image.file, fit: BoxFit.fill),
          if (quad != null)
            CustomPaint(
              painter: QuadPainter(quad: quad!, color: Colors.greenAccent),
            ),
        ],
      ),
    );
  }
}

/// Draws a normalized [Quad] over whatever box it is painted into.
class QuadPainter extends CustomPainter {
  QuadPainter({required this.quad, required this.color});

  final Quad quad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(NormalizedPoint p) => Offset(p.x * size.width, p.y * size.height);
    final path = Path()
      ..moveTo(at(quad.topLeft).dx, at(quad.topLeft).dy)
      ..lineTo(at(quad.topRight).dx, at(quad.topRight).dy)
      ..lineTo(at(quad.bottomRight).dx, at(quad.bottomRight).dy)
      ..lineTo(at(quad.bottomLeft).dx, at(quad.bottomLeft).dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant QuadPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.color != color;
}
