import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../common/camera_support.dart';
import '../common/capture_image.dart';
import '../common/errors.dart';
import '../common/temp_files.dart';
import '../ocr/ocr_models.dart';
import 'document_final_analysis.dart';
import 'document_frame_analysis.dart';
import 'document_image_processing.dart';
import 'document_live_detection.dart';
import 'document_options.dart';
import 'document_profile.dart';
import 'document_result.dart';

/// Reusable controller behind guided document capture.
///
/// [SmartCapture.captureDocument] builds one of these internally to drive its
/// default screen. Build your own instance to put the camera preview and
/// guidance inside custom UI:
///
/// ```dart
/// final controller = DocumentCaptureController(options: options);
/// await controller.initialize();
/// // ...
/// CameraPreview(controller.cameraController!);
/// ValueListenableBuilder(
///   valueListenable: controller,
///   builder: (context, state, _) => Text(labels.guidanceText(state.guidance)),
/// );
/// // ...
/// final front = await controller.captureSide(DocumentSide.front);
/// await controller.resumeLiveGuidance();
/// final back = await controller.captureSide(DocumentSide.back);
/// await controller.dispose();
/// ```
///
/// The controller is a [ValueListenable] of [DocumentGuidanceState]: the
/// latest live-guidance instruction plus the detected boundary, normalized
/// against the upright preview so it can be drawn straight over it.
///
/// ## Frame throttling and backpressure
///
/// Identical to portrait capture: preview frames are analyzed at most once
/// per [DocumentCaptureOptions.analysisInterval], and a frame arriving while
/// the previous analysis is still running, or before the interval has
/// elapsed, is dropped — never queued.
class DocumentCaptureController extends ValueNotifier<DocumentGuidanceState>
    with WidgetsBindingObserver {
  DocumentCaptureController({required this.options})
    : profile = options.resolveProfile(),
      super(const DocumentGuidanceState.initial());

  final DocumentCaptureOptions options;

  /// The profile [options] resolved to.
  final DocumentProfile profile;

  CameraController? _cameraController;

  bool _busy = false;
  DateTime? _lastAnalysisAt;
  bool _streaming = false;
  bool _disposed = false;
  bool _wasStreamingBeforeBackground = false;

  double get _expectedAspectRatio =>
      options.aspectRatioOverride ?? profile.aspectRatio;

  /// The underlying camera controller, once [initialize] has completed.
  ///
  /// `null` before initialization and after [dispose].
  CameraController? get cameraController => _cameraController;

  bool get isInitialized => _cameraController?.value.isInitialized ?? false;

  /// Opens the rear camera and starts live guidance.
  ///
  /// Throws [SmartCaptureException] with the same codes as
  /// [PortraitCaptureController.initialize].
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);

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

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // veryHigh (1080p) rather than the portrait flow's high (720p): the
    // resolution preset also governs the still capture, and characters per
    // pixel on a small card is the biggest single lever on OCR accuracy.
    final controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
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
      // Already stopped; the post-condition — no stream running — holds.
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
    final controller = _cameraController;
    if (controller == null || _disposed) return;

    final plane = _livePlaneFrom(image, controller);
    if (plane == null) return;

    final detection = await detectDocumentInLivePlane(plane);
    // A frame analyzed after the stream stopped (capture started, app
    // backgrounded) must not overwrite the state the capture flow set.
    if (_disposed || !_streaming) return;

    value = analyzeDocumentFrame(
      detection: detection,
      thresholds: options.thresholds,
      expectedAspectRatio: _expectedAspectRatio,
      aspectRatioTolerance: profile.aspectRatioTolerance,
    );
  }

  /// Wraps the luminance-bearing plane of [image], or returns `null` when
  /// the platform delivered a format other than the one requested in
  /// [initialize] — such a frame cannot be interpreted safely.
  LivePlane? _livePlaneFrom(CameraImage image, CameraController controller) {
    final rotation = previewFrameRotationDegrees(controller);
    if (rotation == null || image.planes.isEmpty) return null;

    // NV21's first plane starts with the full-resolution Y (luma) data, which
    // is all boundary detection reads.
    final LivePlaneFormat format;
    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
      format = LivePlaneFormat.luma8;
    } else if (Platform.isIOS &&
        image.format.group == ImageFormatGroup.bgra8888) {
      format = LivePlaneFormat.bgra8888;
    } else {
      return null;
    }

    final plane = image.planes.first;
    return LivePlane(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      format: format,
      rotationDegrees: rotation,
    );
  }

  /// Stops live guidance, captures a high-resolution still of [side], and
  /// runs the final pass against it: boundary detection, perspective
  /// correction and every quality check.
  ///
  /// As with portrait capture, the final pass re-analyzes the captured file
  /// at full resolution rather than reusing the last preview frame's result.
  ///
  /// OCR is not run here; see [SmartCapture.captureDocument].
  Future<DocumentSideCapture> captureSide(DocumentSide side) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw const SmartCaptureException(
        code: SmartCaptureErrorCode.cameraFailure,
        message: 'captureSide() was called before initialize() completed.',
      );
    }

    await _stopStream();

    final XFile shot;
    try {
      shot = await controller.takePicture();
    } on CameraException catch (e) {
      throw mapCameraException(
        e,
        fallback: SmartCaptureErrorCode.captureFailed,
      );
    }

    final originalPath = await SmartCaptureTempFiles.newFilePath(
      'document_${side.name}_original',
    );
    await File(shot.path).copy(originalPath);
    // The camera plugin's own file holds a copy of an identity document; it
    // must not outlive the one the host owns and knows how to delete.
    await _deleteQuietly(shot.path);

    try {
      return await _analyzeCapturedSide(side, originalPath);
    } catch (e) {
      await _deleteQuietly(originalPath);
      if (e is SmartCaptureException) rethrow;
      throw SmartCaptureException(
        code: SmartCaptureErrorCode.captureFailed,
        message: 'The captured document image could not be processed.',
        cause: e,
      );
    }
  }

  Future<DocumentSideCapture> _analyzeCapturedSide(
    DocumentSide side,
    String originalPath,
  ) async {
    final decoded = await decodeAndAnalyzeDocument(originalPath);
    final detection = decoded.detection;

    // Rectification needs all four corners in the image: warping a clipped
    // card would silently produce a partial document that looks complete.
    DocumentRectificationResult? rectification;
    if (detection != null && detection.quad.isFullyInsideImage) {
      rectification = await produceDocumentRectification(
        sourcePath: originalPath,
        quad: detection.quad,
        aspectRatio: rectificationAspectRatio(
          measured: detection.estimatedAspectRatio,
          expected: _expectedAspectRatio,
        ),
        glareLuminanceThreshold: options.thresholds.glareLuminanceThreshold,
      );
    }

    final analysis = analyzeDocumentCapture(
      detection: detection,
      metrics: decoded.metrics,
      glareFraction: rectification?.glareFraction,
      expectedAspectRatio: _expectedAspectRatio,
      thresholds: options.thresholds,
      aspectRatioTolerance: profile.aspectRatioTolerance,
    );

    // The rectified image is always produced when possible, because glare is
    // measured on it; the file is dropped afterwards if the host opted out.
    var rectified = rectification?.image;
    if (!options.produceRectifiedImage && rectified != null) {
      await rectified.delete();
      rectified = null;
    }

    return DocumentSideCapture(
      side: side,
      originalImage: CaptureImage(
        path: originalPath,
        kind: CaptureImageKind.original,
        width: decoded.width,
        height: decoded.height,
      ),
      rectifiedImage: rectified,
      detectedCorners: analysis.quad,
      qualityReport: analysis.qualityReport,
    );
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone; nothing to clean up.
    }
  }

  /// Restarts live guidance, e.g. after a retake or before the next side.
  Future<void> resumeLiveGuidance() async {
    if (_disposed) return;
    value = const DocumentGuidanceState.initial();
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
    super.dispose();
  }
}
