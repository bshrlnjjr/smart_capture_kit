import 'package:flutter/material.dart';

import 'common/errors.dart';
import 'document/document_options.dart';
import 'document/document_result.dart';
import 'portrait/portrait_capture_screen.dart';
import 'portrait/portrait_options.dart';
import 'portrait/portrait_result.dart';

/// Entry point for every capture flow.
///
/// ```dart
/// final portrait = await SmartCapture.capturePortrait(
///   context,
///   options: const PortraitCaptureOptions(),
/// );
///
/// final document = await SmartCapture.captureDocument(
///   context,
///   options: const DocumentCaptureOptions(
///     documentProfile: 'jo_national_id',
///     sides: DocumentSides.frontAndBack,
///     ocr: true,
///   ),
/// );
/// ```
///
/// Both methods return `null` when the user cancels, rather than throwing, so
/// that a cancel does not need a `try`/`catch`. Every other failure throws
/// [SmartCaptureException] with a [SmartCaptureErrorCode] to switch on.
abstract final class SmartCapture {
  /// Opens the guided portrait capture screen.
  ///
  /// Returns `null` if the user cancels.
  ///
  /// Passing the quality checks means the image satisfied the thresholds in
  /// [options]. It is not a statement that the photo meets any official photo
  /// standard, and no identity verification, face matching or liveness check
  /// is performed.
  static Future<PortraitCaptureResult?> capturePortrait(
    BuildContext context, {
    PortraitCaptureOptions options = const PortraitCaptureOptions(),
  }) async {
    options.thresholds.validate();

    final outcome = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => PortraitCaptureScreen(options: options),
        fullscreenDialog: true,
      ),
    );

    if (outcome == null) return null;
    if (outcome is SmartCaptureException) throw outcome;
    return outcome as PortraitCaptureResult;
  }

  /// Opens the guided document capture flow for the configured sides.
  ///
  /// Returns `null` if the user cancels.
  ///
  /// Reading a document is not identity verification. The plugin makes no
  /// claim that a document is authentic or that it belongs to the person
  /// presenting it.
  static Future<DocumentCaptureResult?> captureDocument(
    BuildContext context, {
    DocumentCaptureOptions options = const DocumentCaptureOptions(),
  }) async {
    options.thresholds.validate();
    // Resolves the profile eagerly so an unknown id fails immediately with a
    // useful error instead of after the camera has already opened.
    options.resolveProfile();
    throw const SmartCaptureException(
      code: SmartCaptureErrorCode.platformError,
      message: 'Document capture is not implemented yet (phase 5). The public '
          'API, models and options in this release are final enough to build '
          'against; the camera pipeline behind them is not wired up.',
    );
  }
}
