import 'package:flutter/material.dart';

import 'errors.dart';
import 'labels.dart';

/// Shown in place of the preview when the camera could not start.
class PermissionOrErrorView extends StatelessWidget {
  const PermissionOrErrorView({
    super.key,
    required this.error,
    required this.labels,
  });

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
                    SmartCaptureErrorCode
                        .cameraPermissionPermanentlyDenied) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(error as SmartCaptureException),
                child: Text(labels.openSettings),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The single live-guidance instruction shown over the preview.
class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({super.key, required this.text, required this.isReady});

  final String text;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isReady
            ? Colors.green.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

/// The always-available manual shutter.
class CaptureButton extends StatelessWidget {
  const CaptureButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

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
