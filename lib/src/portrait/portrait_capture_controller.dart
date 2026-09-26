import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../common/camera_support.dart';
import '../common/capture_image.dart';
import '../common/errors.dart';
import '../common/temp_files.dart';
import 'portrait_final_analysis.dart';
import 'portrait_frame_analysis.dart';
import 'portrait_image_processing.dart';
import 'portrait_options.dart';
import 'portrait_result.dart';

/// Reusable controller behind guided portrait capture.
///
/// [SmartCapture.capturePortrait] builds one of these internally to drive its
/// default screen. Build your own instance to put the camera preview and
/// guidance inside custom UI:
///
/// ```dart
/// final controller = PortraitCaptureController(options: options);
/// await controller.initialize();
/// // ...
/// CameraPreview(controller.cameraController!);
/// ValueListenableBuilder(
///   valueListenable: controller,
///   builder: (context, guidance, _) => Text(labels.guidanceText(guidance.guidance)),
/// );
/// // ...
/// final result = await controller.captureAndAnalyze();
/// await controller.dispose();
/// ```
///
/// The controller is a [ValueListenable] of [PortraitGuidanceState]: the
/// latest live-guidance instruction plus the face box that produced it, for
/// drawing an overlay.
///
/// ## Frame throttling and backpressure
///
/// Preview frames are analyzed at most once per [PortraitCaptureOptions.analysisInterval].
/// A frame that arrives while the previous analysis is still running, or
/// before the interval has elapsed, is dropped — never queued. A slow device
/// therefore degrades to a lower guidance rate rather than accumulating a
/// backlog of stale frames.
class PortraitCaptureController extends ValueNotifier<PortraitGuidanceState>
    with WidgetsBindingObserver {
  PortraitCaptureController({required this.options})
      : super(const PortraitGuidanceState.initial());

  final PortraitCaptureOptions options;

  CameraController? _cameraController;
  FaceDetector? _liveDetector;
  FaceDetector? _finalDetector;

  bool _busy = false;
  DateTime? _lastAnalysisAt;
  bool _streaming = false;
  bool _disposed = false;
  bool _wasStreamingBeforeBackground = false;

  /// The underlying camera controller, once [initialize] has completed.
  ///
  /// Exposed so a host building custom UI can wrap it in a `CameraPreview`.
  /// `null` before initialization and after [dispose].
  CameraController? get cameraController => _cameraController;

  bool get isInitialized => _cameraController?.value.isInitialized ?? false;

  /// Opens the camera and starts live guidance.
  ///
  /// Throws [SmartCaptureException] on permission denial
  /// ([SmartCaptureErrorCode.cameraPermissionDenied] or
  /// [SmartCaptureErrorCode.cameraPermissionPermanentlyDenied]), when no
  /// camera is available ([SmartCaptureErrorCode.cameraUnavailable]), or on
  /// any other camera failure ([SmartCaptureErrorCode.cameraFailure]).
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);

    _liveDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: options.thresholds.requireEyesOpen,
        enableLandmarks: false,
        enableTracking: true,
      ),
    );
    _finalDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true,
        enableLandmarks: false,
      ),
    );

    await _openCamera();
  }

  Future<void> _openCamera() async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw mapCameraException(e);
    }

    if (cameras.isEmpty) {
      throw const SmartCaptureException(
        code: SmartCaptureErrorCode.cameraUnavailable,
        message: 'No camera was reported by the platform.',
      );
    }

    final targetDirection = options.cameraFacing == CameraFacing.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == targetDirection,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      throw mapCameraException(e);
    }

    if (_disposed) {
      await controller.dispose();
      return;
    }

    _cameraController = controller;
    await _startStream();
  }

  Future<void> _startStream() async {
    final controller = _cameraController;
    if (controller == null || _streaming || _disposed) return;
    _streaming = true;
    await controller.startImageStream(_onFrame);
  }

  Future<void> _stopStream() async {
    final controller = _cameraController;
    if (controller == null || !_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } on CameraException {
      // Already stopped, e.g. the platform tore it down first. The
      // post-condition — no stream running — already holds.
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy || _disposed) return;
    final now = DateTime.now();
    final last = _lastAnalysisAt;
    if (last != null && now.difference(last) < options.analysisInterval) {
      return;
    }
    _busy = true;
    _lastAnalysisAt = now;
    unawaited(_analyzeFrame(image).whenComplete(() => _busy = false));
  }

  Future<void> _analyzeFrame(CameraImage image) async {
    final detector = _liveDetector;
    final controller = _cameraController;
    if (detector == null || controller == null || _disposed) return;

    final inputImage = _buildInputImage(image, controller);
    if (inputImage == null) return;

    List<Face> faces;
    try {
      faces = await detector.processImage(inputImage);
    } catch (_) {
      // A single bad frame must not take down live guidance; the next frame
      // gets another chance.
      return;
    }
    if (_disposed) return;

    final size = inputImage.metadata!.size;
    value = analyzePortraitFrame(
      faces: faces,
      imageWidth: size.width,
      imageHeight: size.height,
      thresholds: options.thresholds,
    );
  }

  /// Builds an ML Kit [InputImage] from a live preview frame, rotated per
  /// [previewFrameRotationDegrees].
  InputImage? _buildInputImage(CameraImage image, CameraController controller) {
    final degrees = previewFrameRotationDegrees(controller);
    final rotation =
        degrees == null ? null : InputImageRotationValue.fromRawValue(degrees);
    if (rotation == null) return null;

    // Only the two formats requested in _openCamera are handled: nv21 on
    // Android, bgra8888 on iOS, matched via the cross-platform format group
    // rather than the raw platform int. Anything else means the platform
    // ignored the requested imageFormatGroup, and this frame cannot be
    // interpreted safely.
    final InputImageFormat format;
    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
      format = InputImageFormat.nv21;
    } else if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      format = InputImageFormat.bgra8888;
    } else {
      return null;
    }
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Stops live guidance, captures a high-resolution still, and runs the
  /// final quality pass against it.
  ///
  /// The final pass re-analyzes the captured file at full resolution — it
  /// does not reuse the last preview frame's result, since preview frames are
  /// deliberately lower-resolution and lower-effort than what a host should
  /// act on.
  Future<PortraitCaptureResult> captureAndAnalyze() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw const SmartCaptureException(
        code: SmartCaptureErrorCode.cameraFailure,
        message: 'captureAndAnalyze() was called before initialize() '
            'completed.',
      );
    }

    await _stopStream();

    final XFile shot;
    try {
      shot = await controller.takePicture();
    } on CameraException catch (e) {
      throw mapCameraException(e, fallback: SmartCaptureErrorCode.captureFailed);
    }

    final originalPath =
        await SmartCaptureTempFiles.newFilePath('portrait_original');
    await File(shot.path).copy(originalPath);

    // Normalize away the iOS/Android front-camera mirroring inconsistency
    // before anything downstream reads this file — see flipHorizontalInPlace.
    final isFrontCamera =
        controller.description.lensDirection == CameraLensDirection.front;
    if (isFrontCamera) {
      final platformMirrorsByDefault = Platform.isIOS;
      final shouldFlip =
          options.mirrorFrontCameraOutput != platformMirrorsByDefault;
      if (shouldFlip) {
        await flipHorizontalInPlace(originalPath);
      }
    }

    DecodedImageInfo decoded;
    try {
      decoded = await decodeAndAnalyzeImage(originalPath);
    } catch (e) {
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.captureFailed,
        message: 'The captured portrait image could not be decoded.',
        cause: e,
      );
    }

    List<Face> finalFaces = const [];
    try {
      finalFaces = await _finalDetector!.processImage(
        InputImage.fromFilePath(originalPath),
      );
    } catch (_) {
      // Falls through with an empty face list; the resulting quality report
      // will honestly show faceCount == 0 rather than crashing the capture.
    }

    final analysis = analyzePortraitCapture(
      faces: finalFaces,
      imageWidth: decoded.width,
      imageHeight: decoded.height,
      metrics: decoded.metrics,
      thresholds: options.thresholds,
    );

    CaptureImage? cropped;
    final face = analysis.face;
    if (options.produceCroppedImage && face != null) {
      cropped = await producePortraitCrop(
        sourcePath: originalPath,
        faceBox: face.boundingBox,
        aspectRatio: options.outputAspectRatio,
        paddingFactor: options.cropPaddingFactor,
      );
    }

    return PortraitCaptureResult(
      originalImage: CaptureImage(
        path: originalPath,
        kind: CaptureImageKind.original,
        width: decoded.width,
        height: decoded.height,
      ),
      croppedImage: cropped,
      qualityReport: analysis.qualityReport,
      face: analysis.face,
      faceCount: analysis.faceCount,
    );
  }

  /// Restarts live guidance after a retake decision.
  Future<void> resumeLiveGuidance() async {
    if (_disposed) return;
    value = const PortraitGuidanceState.initial();
    await _startStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _wasStreamingBeforeBackground = _streaming;
        unawaited(_stopStream());
      case AppLifecycleState.resumed:
        if (_wasStreamingBeforeBackground && !_disposed) {
          unawaited(_startStream());
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _stopStream();
    await _cameraController?.dispose();
    await _liveDetector?.close();
    await _finalDetector?.close();
    super.dispose();
  }
}
