import 'package:flutter/material.dart';

import 'quality.dart';

/// Outcome of a capture review screen, popped via [Navigator].
sealed class CaptureReviewOutcome {
  const CaptureReviewOutcome();
}

/// The user asked to retake the photo.
class RetakeRequested extends CaptureReviewOutcome {
  const RetakeRequested();
}

/// The user accepted the capture, possibly despite failing checks.
class ReviewAccepted extends CaptureReviewOutcome {
  const ReviewAccepted({required this.continuedDespiteFailures});

  /// Whether at least one check had failed when the user chose to continue.
  final bool continuedDespiteFailures;
}

/// One row of a review screen's quality-check list.
class QualityCheckTile extends StatelessWidget {
  const QualityCheckTile({super.key, required this.check});

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
