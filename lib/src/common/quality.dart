import 'package:meta/meta.dart';

/// Identifies a single, independently reported quality check.
///
/// Every check a capture flow runs is reported, including the ones that
/// passed, so a host can show a full checklist rather than only complaints.
enum QualityCheckId {
  // --- Portrait checks ---

  /// Exactly one face is present.
  faceCount,

  /// The face occupies an appropriate fraction of the frame — neither a distant
  /// speck nor cropped by being too close.
  faceSize,

  /// The face is centred horizontally and vertically within the target area.
  faceCentering,

  /// Yaw, pitch and roll are within tolerance, i.e. the subject looks straight
  /// at the camera.
  headOrientation,

  /// Both eyes appear open.
  eyesOpen,

  // --- Document checks ---

  /// All four document corners were located.
  documentCornersDetected,

  /// No corner is cut off by the frame edge.
  documentWithinFrame,

  /// Perspective distortion is low enough for reliable rectification.
  documentPerspective,

  /// The document fills enough of the frame to yield readable characters.
  documentSize,

  /// The detected aspect ratio is close to the profile's expected ratio.
  documentAspectRatio,

  /// No specular highlight covers a region likely to contain text.
  glare,

  // --- Shared image checks ---

  /// The image is neither too dark nor blown out.
  exposure,

  /// The image is sharp enough to read.
  sharpness,

  /// The camera was steady at the moment of capture.
  motion,
}

/// Outcome of one [QualityCheckId].
enum QualityCheckOutcome {
  /// The check ran and the image satisfies it.
  pass,

  /// The check ran and the image is marginal. Worth telling the user about,
  /// but not grounds for the plugin to refuse the capture.
  warn,

  /// The check ran and the image clearly does not satisfy it.
  fail,

  /// The check did not run — the platform could not evaluate it, or the host
  /// disabled it. Distinct from [pass]: absence of evidence is reported as
  /// absence, never as success.
  notEvaluated,
}

/// The result of one quality check, including the numbers behind the verdict.
///
/// [measuredValue] and [threshold] are exposed so a host can build its own UI
/// ("your photo is slightly dark") or apply a stricter policy than the default
/// without re-analysing the image.
@immutable
class QualityCheck {
  const QualityCheck({
    required this.id,
    required this.outcome,
    this.measuredValue,
    this.threshold,
    this.detail,
  });

  /// A check the current platform or configuration could not evaluate.
  const QualityCheck.notEvaluated(this.id, {this.detail})
      : outcome = QualityCheckOutcome.notEvaluated,
        measuredValue = null,
        threshold = null;

  final QualityCheckId id;
  final QualityCheckOutcome outcome;

  /// The value that was measured, in the check's own units. `null` when the
  /// check is boolean in nature or was not evaluated.
  final double? measuredValue;

  /// The threshold [measuredValue] was compared against.
  final double? threshold;

  /// Optional developer-facing note. Must not contain personal data.
  final String? detail;

  bool get passed => outcome == QualityCheckOutcome.pass;
  bool get failed => outcome == QualityCheckOutcome.fail;

  @override
  String toString() => 'QualityCheck(${id.name}: ${outcome.name}'
      '${measuredValue == null ? '' : ', measured=$measuredValue'}'
      '${threshold == null ? '' : ', threshold=$threshold'})';
}

/// The full set of checks run against one captured image.
///
/// A report is descriptive, never prescriptive. It does not decide whether the
/// capture is acceptable — that judgement belongs to the host application,
/// which may have requirements this plugin knows nothing about.
@immutable
class QualityReport {
  const QualityReport(this.checks);

  const QualityReport.empty() : checks = const [];

  final List<QualityCheck> checks;

  /// The check with the given [id], or `null` if it was not part of this run.
  QualityCheck? operator [](QualityCheckId id) {
    for (final check in checks) {
      if (check.id == id) return check;
    }
    return null;
  }

  List<QualityCheck> get failures =>
      checks.where((c) => c.outcome == QualityCheckOutcome.fail).toList();

  List<QualityCheck> get warnings =>
      checks.where((c) => c.outcome == QualityCheckOutcome.warn).toList();

  List<QualityCheck> get notEvaluated =>
      checks.where((c) => c.outcome == QualityCheckOutcome.notEvaluated).toList();

  /// Whether every check that ran passed.
  ///
  /// Checks that did not run are ignored here; consult [notEvaluated] to find
  /// out what could not be verified. A `true` value means "nothing we measured
  /// looked wrong" — it is not a statement that the image meets any external
  /// standard.
  bool get allEvaluatedChecksPassed =>
      failures.isEmpty && warnings.isEmpty;

  bool get hasFailures => failures.isNotEmpty;

  @override
  String toString() =>
      'QualityReport(${checks.length} checks, ${failures.length} failed, '
      '${warnings.length} warnings, ${notEvaluated.length} not evaluated)';
}
