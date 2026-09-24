import 'package:flutter/material.dart';

import '../common/labels.dart';
import '../common/quality.dart';
import 'portrait_result.dart';

/// Default review screen shown after a portrait capture.
///
/// Presents every quality check — including ones that passed — and lets the
/// user retake or continue. When [PortraitCaptureOptions.allowContinueOnFailedChecks]
/// is `false` and a check failed, only Retake is offered: that is the host's
/// explicit choice to hard-block, made through options, not a decision this
/// screen makes on its own.
class PortraitReviewScreen extends StatelessWidget {
  const PortraitReviewScreen({
    super.key,
    required this.result,
    required this.labels,
    required this.allowContinueOnFailedChecks,
  });

  final PortraitCaptureResult result;
  final SmartCaptureLabels labels;
  final bool allowContinueOnFailedChecks;

  @override
  Widget build(BuildContext context) {
    final report = result.qualityReport;
    final canContinue = allowContinueOnFailedChecks || !report.hasFailures;
    final displayImage = result.croppedImage ?? result.originalImage;

    return Directionality(
      textDirection: labels.textDirection == SmartCaptureTextDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(labels.reviewTitle)),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: displayImage.aspectRatio == 0
                      ? 1
                      : displayImage.aspectRatio,
                  child: Image.file(displayImage.file, fit: BoxFit.contain),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final check in report.checks)
                    _QualityCheckRow(check: check),
                ],
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(
                        const RetakeRequested(),
                      ),
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
                        report.hasFailures ? labels.continueAnyway : labels.usePhoto,
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

/// Outcome of the review screen, popped via [Navigator].
sealed class PortraitReviewOutcome {
  const PortraitReviewOutcome();
}

/// The user asked to retake the photo.
class RetakeRequested extends PortraitReviewOutcome {
  const RetakeRequested();
}

/// The user accepted the capture, possibly despite failing checks.
class ReviewAccepted extends PortraitReviewOutcome {
  const ReviewAccepted({required this.continuedDespiteFailures});

  /// Whether at least one check had failed when the user chose to continue.
  final bool continuedDespiteFailures;
}

class _QualityCheckRow extends StatelessWidget {
  const _QualityCheckRow({required this.check});

  final QualityCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.outcome) {
      QualityCheckOutcome.pass => (Icons.check_circle, Colors.green),
      QualityCheckOutcome.warn => (Icons.warning_amber, Colors.orange),
      QualityCheckOutcome.fail => (Icons.cancel, Colors.redAccent),
      QualityCheckOutcome.notEvaluated => (Icons.help_outline, Colors.grey),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(_titleFor(check.id)),
      subtitle: check.detail == null ? null : Text(check.detail!),
    );
  }

  String _titleFor(QualityCheckId id) {
    // Developer-facing fallback label; a host with its own labels object
    // should render this list itself using SmartCaptureLabels instead.
    final words = id.name
        .replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m.group(0)}')
        .toLowerCase();
    return words[0].toUpperCase() + words.substring(1);
  }
}
