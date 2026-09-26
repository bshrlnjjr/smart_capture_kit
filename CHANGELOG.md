# Changelog

## 0.0.1 — unreleased

Not published. The package is in early development; see the status table in
the README for what works today.

### Added (phase 6 — OCR prototype, in progress)

- Synthetic-card OCR benchmark (`tool/ocr_benchmark/`) and first desktop
  results (`doc/benchmarks/phase6-desktop-ocr.md`): Apple Vision reads the
  set almost perfectly; Tesseract `ara` misses every Arabic-Indic date and
  drops Arabic lines under glare. PaddleOCR's Arabic mobile model reads
  Arabic words best and holds up under glare, but silently drops digits
  unless paired with a Latin recognizer (90–94% field accuracy when
  paired). No Android-capable engine read Arabic-Indic digits. No
  production OCR engine is chosen yet.

### Fixed

- `normalizeForComparison` now also strips U+061C (Arabic Letter Mark).

### Added (phase 5 — document capture)

- `SmartCapture.captureDocument` is implemented end to end: guided live
  capture of the front and (optionally) the back, a review screen per side
  showing the perspective-corrected card and the original with its detected
  boundary, and a `DocumentCaptureResult` with both images per side.
- `DocumentCaptureController`, the reusable
  `ValueListenable<DocumentGuidanceState>` behind the default screen, with
  the same throttled, drop-not-queue frame analysis as portrait capture.
- Pure Dart document boundary detection, perspective correction, and
  full-resolution quality checks: corners detected, within frame,
  perspective, size, aspect ratio, exposure, sharpness and glare (glare is
  measured on the rectified card only). See
  `doc/decisions/0002-document-boundary-detection.md`.
- Abandoned captures (retake, cancel after the front) and the camera
  plugin's own temporary file are deleted, so no document image lingers.
- OCR is not run yet: `ocr` and `fields` are always `null` in this release.

### Changed

- `Quad.estimatedAspectRatio` is now a method taking the image's aspect
  ratio. It previously measured in normalized coordinates, which reported an
  ID-1 card in a 3:4 photo as about 2.1 instead of 1.59.
- `RetakeRequested` / `ReviewAccepted` now extend `CaptureReviewOutcome`,
  shared by the portrait and document flows; `PortraitReviewOutcome`
  remains as an alias.
- `SmartCaptureLabels` gains `correctedImage` and `originalImage`.

### Added (phase 4 — portrait capture)

- `PortraitCaptureController`, a reusable, `ValueListenable<PortraitGuidanceState>`
  controller wrapping `camera` + on-device ML Kit face detection: live guidance
  at a throttled, drop-not-queue frame rate, app-lifecycle-aware camera
  teardown/reopen, and a full-resolution post-capture quality pass.
- `SmartCapture.capturePortrait` is implemented end to end: guided live
  capture, review screen (retake / continue, including "continue anyway" past
  failed checks), optional face-centered crop at a requested aspect ratio, and
  typed results.
- Camera permission denial maps to `SmartCaptureErrorCode.cameraPermissionDenied`
  / `cameraPermissionPermanentlyDenied`, verified against the exact error codes
  `camera_avfoundation` and `camera_android_camerax` raise.
- Brightness (mean luminance) and sharpness (Laplacian variance) computed
  off the UI isolate via `compute()`.
- Normalizes a real iOS/Android platform inconsistency: `camera_avfoundation`
  leaves AVFoundation's front-camera photo mirroring on by default;
  `camera_android_camerax`'s `ImageCapture` never mirrors. Both now honor
  `PortraitCaptureOptions.mirrorFrontCameraOutput` the same way.

### Added (phase 1-3)

- Public API surface: `SmartCapture`, `PortraitCaptureOptions`,
  `DocumentCaptureOptions`, and the result, quality-check, OCR and field
  models they return.
- Structured errors via `SmartCaptureException` and `SmartCaptureErrorCode`,
  with a `isRetryable` classification.
- `QualityCheck` / `QualityReport`, including an explicit `notEvaluated`
  outcome so an unverifiable check is never reported as a passing one.
- `ExtractedField` with `recognized` / `uncertain` / `missing` /
  `manuallyCorrected` states, uncertainty reasons, and `FieldEvidence` tying
  every value back to its source text, bounding boxes and document side.
- Arabic and Western text normalization helpers, applied only to derived
  comparison values. Raw OCR text is preserved verbatim.
- `DocumentProfileRegistry` with `generic_id_card` and `jo_national_id`
  reference profiles, both raw-text-only. Neither declares field positions.
- Localizable UI strings via `SmartCaptureLabels`, shipped in English and
  Arabic, with guidance emitted as enum values rather than strings.
- ADR `doc/decisions/0001-ocr-engine-selection.md` recording the OCR engine
  comparison, with the Apple Vision language probe checked in at
  `tool/probe_vision_languages.swift`.

### Known limitations

- Document capture, perspective correction and OCR are not implemented.
  `SmartCapture.captureDocument` validates its options and then throws.
- Portrait capture's `motion` quality check always reports `notEvaluated`:
  judging camera shake from a single still frame with no gyroscope trace is
  not implemented.
- Camera permission is only requested/checked implicitly by opening the
  camera; "permanently denied" is detected from the platform's own error code
  but the review screen's "open settings" affordance does not yet deep-link
  into system settings.
- iOS: `google_mlkit_face_detection`/`google_mlkit_commons` require iOS 15.5+
  (bumped from this package's earlier 15.0 minimum) and ship no arm64 iOS
  Simulator slice — the example app's simulator build runs under Rosetta
  (x86_64); real devices are unaffected.
- Arabic support on iOS is inferred from a macOS Vision probe and has not yet
  been confirmed on a physical device.
- No Arabic OCR accuracy has been measured on real captures.
