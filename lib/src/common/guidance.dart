/// A single instruction shown to the user during live capture.
///
/// The plugin emits these as enum values, never as pre-built strings, so a
/// host can translate or reword every message. Map them to text with
/// [SmartCaptureLabels].
enum CaptureGuidance {
  // --- Shared ---

  /// Everything checks out; the capture can proceed.
  ready,

  /// The frame is acceptable but the device is moving. Wait before capturing.
  holdStill,

  /// The scene is too dark.
  tooDark,

  /// The scene is blown out.
  tooBright,

  /// The frame is out of focus.
  outOfFocus,

  // --- Portrait ---

  /// No face was found in the frame.
  noFaceDetected,

  /// More than one face was found. The plugin does not choose between them.
  multipleFacesDetected,

  /// The face is too small; the user should move closer.
  moveCloser,

  /// The face is too large or cropped; the user should move back.
  moveFarther,

  /// The face sits left of the target area.
  moveRight,

  /// The face sits right of the target area.
  moveLeft,

  /// The face sits above the target area.
  moveDown,

  /// The face sits below the target area.
  moveUp,

  /// The head is turned or tilted away from the camera.
  lookStraightAhead,

  /// One or both eyes appear closed.
  openEyes,

  // --- Document ---

  /// No document boundary was found.
  noDocumentDetected,

  /// A boundary was found but at least one corner is outside the frame.
  fitAllCornersInFrame,

  /// The document is too small within the frame for reliable text.
  moveCloserToDocument,

  /// The camera is at too steep an angle to the card.
  holdDeviceFlat,

  /// A specular highlight is covering part of the document.
  avoidGlare,

  /// A boundary was found but its shape does not match the expected card
  /// aspect ratio.
  unexpectedDocumentShape,
}
