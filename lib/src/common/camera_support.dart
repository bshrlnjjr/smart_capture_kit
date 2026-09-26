import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import 'errors.dart';

const Map<DeviceOrientation, int> _degreesByOrientation = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Clockwise rotation (0, 90, 180 or 270) that turns a live preview frame
/// from [controller] upright, or `null` on an unsupported platform.
///
/// The math follows the platform's own reported sensor orientation combined
/// with the current device orientation, per
/// https://developers.google.com/ml-kit/vision/face-detection/android —
/// getting this wrong is the single most common cause of on-frame detection
/// silently returning nothing on a rotated preview.
int? previewFrameRotationDegrees(CameraController controller) {
  final camera = controller.description;
  if (Platform.isIOS) return camera.sensorOrientation;
  if (Platform.isAndroid) {
    final deviceDegrees =
        _degreesByOrientation[controller.value.deviceOrientation] ?? 0;
    return camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + deviceDegrees) % 360
        : (camera.sensorOrientation - deviceDegrees + 360) % 360;
  }
  return null;
}

/// Maps a [CameraException] to a [SmartCaptureException].
///
/// The permission codes are the exact ones `camera_avfoundation` and
/// `camera_android_camerax` raise; anything else becomes [fallback].
SmartCaptureException mapCameraException(
  CameraException e, {
  SmartCaptureErrorCode fallback = SmartCaptureErrorCode.cameraFailure,
}) {
  final code = switch (e.code) {
    'CameraAccessDenied' ||
    'AudioAccessDenied' => SmartCaptureErrorCode.cameraPermissionDenied,
    'CameraAccessDeniedWithoutPrompt' || 'AudioAccessDeniedWithoutPrompt' =>
      SmartCaptureErrorCode.cameraPermissionPermanentlyDenied,
    _ => fallback,
  };
  return SmartCaptureException(
    code: code,
    message: e.description ?? e.code,
    cause: e,
  );
}
