import 'package:flutter_test/flutter_test.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

void main() {
  group('QualityReport', () {
    const report = QualityReport([
      QualityCheck(
        id: QualityCheckId.faceCount,
        outcome: QualityCheckOutcome.pass,
        measuredValue: 1,
      ),
      QualityCheck(
        id: QualityCheckId.sharpness,
        outcome: QualityCheckOutcome.fail,
        measuredValue: 0.12,
        threshold: 0.35,
      ),
      QualityCheck(
        id: QualityCheckId.exposure,
        outcome: QualityCheckOutcome.warn,
        measuredValue: 0.22,
        threshold: 0.25,
      ),
      QualityCheck.notEvaluated(
        QualityCheckId.headOrientation,
        detail: 'pitch not reported by this platform',
      ),
    ]);

    test('lookup by id returns the check, or null when absent', () {
      expect(report[QualityCheckId.sharpness]?.outcome,
          QualityCheckOutcome.fail);
      expect(report[QualityCheckId.glare], isNull);
    });

    test('partitions checks by outcome', () {
      expect(report.failures.single.id, QualityCheckId.sharpness);
      expect(report.warnings.single.id, QualityCheckId.exposure);
      expect(report.notEvaluated.single.id, QualityCheckId.headOrientation);
    });

    test('a not-evaluated check is never reported as passed', () {
      final check = report[QualityCheckId.headOrientation]!;
      expect(check.outcome, QualityCheckOutcome.notEvaluated);
      expect(check.passed, isFalse);
      expect(check.failed, isFalse);
    });

    test('allEvaluatedChecksPassed is false while a failure or warning exists',
        () {
      expect(report.allEvaluatedChecksPassed, isFalse);
      expect(report.hasFailures, isTrue);
    });

    test('a report of passes plus unevaluated checks counts as passing', () {
      const partial = QualityReport([
        QualityCheck(
          id: QualityCheckId.faceCount,
          outcome: QualityCheckOutcome.pass,
        ),
        QualityCheck.notEvaluated(QualityCheckId.eyesOpen),
      ]);
      expect(partial.allEvaluatedChecksPassed, isTrue);
      // ...but the caller can still see what went unverified.
      expect(partial.notEvaluated, hasLength(1));
    });

    test('an empty report has nothing to report', () {
      const empty = QualityReport.empty();
      expect(empty.checks, isEmpty);
      expect(empty.hasFailures, isFalse);
    });
  });

  group('SmartCaptureException', () {
    test('transient failures are retryable', () {
      for (final code in [
        SmartCaptureErrorCode.cameraFailure,
        SmartCaptureErrorCode.captureFailed,
        SmartCaptureErrorCode.rectificationFailed,
        SmartCaptureErrorCode.ocrFailed,
      ]) {
        expect(
          SmartCaptureException(code: code, message: 'x').isRetryable,
          isTrue,
          reason: '${code.name} should be retryable',
        );
      }
    });

    test('configuration and permission failures are not retryable', () {
      for (final code in [
        SmartCaptureErrorCode.cancelled,
        SmartCaptureErrorCode.cameraPermissionDenied,
        SmartCaptureErrorCode.cameraPermissionPermanentlyDenied,
        SmartCaptureErrorCode.unknownDocumentProfile,
        SmartCaptureErrorCode.invalidOptions,
        SmartCaptureErrorCode.ocrEngineUnavailable,
      ]) {
        expect(
          SmartCaptureException(code: code, message: 'x').isRetryable,
          isFalse,
          reason: '${code.name} should not be retryable',
        );
      }
    });
  });
}
