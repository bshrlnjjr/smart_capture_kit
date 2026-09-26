# smart_capture_kit

Guided portrait and identity-card capture for Flutter, with on-device quality
checks and OCR field extraction.

> **Early development.** Portrait and document capture are implemented end
> to end. OCR is not yet. See [Status](#status) before integrating.

## What this package is, and is not

It helps a user take a usable photo of their face or their ID card, tells the
application what is wrong with the image when something is, reads the text on
the document, and hands back structured fields with an explicit confidence
state for each one.

It is **not** an identity verification product. Specifically, it does not and
will not:

- decide whether a document is authentic,
- decide whether a document belongs to the person presenting it,
- match a face against a document photo,
- detect liveness, spoofing or fraud,
- assert that a portrait meets any government's official photo requirements.

Passing every quality check means the image satisfied the thresholds *you*
configured. Nothing more.

## Status

| Capability | State |
|---|---|
| Public API, options, result models, structured errors | Implemented, unit tested |
| Quality-check and field-extraction model with evidence and uncertainty | Implemented, unit tested |
| Arabic / Western text normalization | Implemented, unit tested |
| Document profile registry | Implemented, unit tested |
| English + Arabic UI strings | Implemented |
| Guided portrait capture: live guidance, quality pass, crop | **Implemented**, unit tested |
| Guided document capture, corner detection, rectification | **Implemented**, unit tested; not yet verified on real devices |
| OCR engines (Apple Vision / ML Kit / Tesseract) | Not implemented |
| Field mapping for any document profile | Not implemented, by design — see below |

`SmartCapture.capturePortrait` opens a real camera screen backed by on-device
face detection and returns a fully analyzed result. `SmartCapture.captureDocument`
guides the user through the front and back of a card, detects its corners,
returns the original and a perspective-corrected image per side, and reports
quality checks. It does not run OCR yet: `ocr` and `fields` on its result are
always `null`. Corner detection is a pure Dart heuristic; its limits are in
`doc/decisions/0002-document-boundary-detection.md`.

## Install

```yaml
dependencies:
  smart_capture_kit: ^0.0.1
```

## Usage

```dart
import 'package:smart_capture_kit/smart_capture_kit.dart';

final portrait = await SmartCapture.capturePortrait(
  context,
  options: const PortraitCaptureOptions(),
);
if (portrait == null) return; // the user cancelled

for (final check in portrait.qualityReport.checks) {
  print('${check.id.name}: ${check.outcome.name}');
}
await portrait.dispose(); // deletes the temporary image files
```

```dart
final document = await SmartCapture.captureDocument(
  context,
  options: const DocumentCaptureOptions(
    documentProfile: 'jo_national_id',
    sides: DocumentSides.frontAndBack,
    ocr: true,
  ),
);

print(document?.front.ocr?.rawText);

for (final field in document?.fields?.fieldsNeedingReview ?? const []) {
  // field.value may be null; field.evidence shows where it came from.
}
```

Cancellation returns `null` rather than throwing, so it needs no `try`/`catch`.
Everything else throws `SmartCaptureException` carrying a
`SmartCaptureErrorCode` you can switch on.

### Portrait capture

`capturePortrait` opens a full-screen camera flow: a live overlay guides
framing while on-device ML Kit face detection throttles analysis to
`analysisInterval` (frames arriving faster than that, or while an analysis is
still running, are dropped — never queued, so a slow device degrades to a
lower guidance rate instead of falling behind). It auto-captures once the
frame holds `CaptureGuidance.ready` for ~700ms, and a manual shutter button is
always available. The captured still is then re-analyzed at full resolution —
face count, framing, head orientation, exposure, sharpness — independently of
whatever the last preview frame showed, and a review screen offers Retake /
Continue (and "Continue anyway" when a check failed, if
`allowContinueOnFailedChecks` is on).

Build your own UI instead of the default screen with the underlying
`PortraitCaptureController`, a `ValueListenable<PortraitGuidanceState>`:

```dart
final controller = PortraitCaptureController(options: options);
await controller.initialize();
// CameraPreview(controller.cameraController!), your own overlay driven by
// `controller.value.guidance`, then:
final result = await controller.captureAndAnalyze();
await controller.dispose();
```

The one check the final pass cannot make is camera shake from a single still
frame — `QualityCheckId.motion` always reports `notEvaluated` in this release
rather than guessing at it from blur, which motion and defocus are not the
same thing.

### Nothing is invented

A field that was not found is reported as `FieldStatus.missing` with a `null`
value. A field the pipeline is unsure about is `FieldStatus.uncertain`, carries
the reasons why, and is meant to be shown to a human before use. There is no
code path that fills a gap with a plausible-looking value.

Every extracted value carries `FieldEvidence`: the exact source text, the
bounding boxes it came from, which side of the document, and the OCR
confidence where the engine reported one.

### Raw text is preserved

`OcrLine.text` and `OcrBlock.text` hold exactly what the engine returned — no
trimming, no digit conversion, no bidirectional reordering. Normalization
helpers such as `toWesternDigits` and `normalizeForComparison` produce
*separate* derived values for matching and validation. Ambiguous characters are
never silently repaired.

## Localization

Guidance is emitted as `CaptureGuidance` enum values, never as strings. Map
them with `SmartCaptureLabels`:

```dart
options: PortraitCaptureOptions(labels: SmartCaptureLabels.arabic())
```

A partial override falls back to the English wording, so a guidance value added
in a later release never renders blank. The shipped Arabic strings are a
starting point and should be reviewed by a native speaker before you ship them.

## Arabic OCR

Arabic support is the constraint that shapes this package. The measured
situation, as of September 2026:

| Engine | Android | iOS |
|---|---|---|
| Apple Vision | n/a | **Yes** — `ar-SA`, `ars-SA`, revision 3, `.accurate` only |
| ML Kit Text Recognition v2 | **No Arabic model exists** | No |
| Tesseract 5 + `ara.traineddata` | Yes | Yes |

Apple Vision's `.fast` recognition level supports six Latin languages and
silently drops Arabic — a request configured with `.fast` and Arabic does not
error, it simply returns nothing. Reproduce the language matrix yourself:

```
swift tool/probe_vision_languages.swift
```

Because Android has no first-party Arabic OCR, the planned default routes
Android Arabic through Tesseract. **Arabic results on Android will be weaker
than on iOS**, particularly under glare and perspective skew. That asymmetry is
surfaced rather than hidden: `OcrPageResult.engine` records which engine read
each page, and weaker recognition produces more `uncertain` fields for review
rather than confident wrong answers.

Full comparison, with sources and open risks:
[`doc/decisions/0001-ocr-engine-selection.md`](doc/decisions/0001-ocr-engine-selection.md).

### Optional cloud OCR

The package ships no cloud provider, no SDK and no credentials. To use one,
implement `OcrEngine` against your own backend and pass it in:

```dart
DocumentCaptureOptions(ocrEngineOverride: MyBackendOcrEngine())
```

Your descriptor must report `isOffDevice: true`. Disclosing the transfer to the
user, and its legal basis, is the host application's responsibility. Core
capture and quality checks work with no adapter present.

## Document profiles

A profile describes one kind of document: its aspect ratio, the scripts to
expect, the fields it carries, and how to map OCR onto them.

Two profiles ship, `generic_id_card` and `jo_national_id`. **Both declare zero
fields.** The Jordanian profile states the card's physical format and scripts,
which are safe to know from the format alone, and stops there. Which fields are
printed, where they sit and how they are labelled cannot be encoded
responsibly before legally obtained, redacted samples have been inspected —
guessing a layout is how a pipeline starts reading the wrong number into the
wrong field. Until then the profile guides capture, rectifies the card and
returns complete raw OCR.

Register your own:

```dart
DocumentProfileRegistry.register(
  const DocumentProfile(
    id: 'my_document',
    displayName: 'My document',
    aspectRatio: idCardAspectRatioId1,
    expectedScripts: [OcrScript.latin],
    extractionSupport: ProfileExtractionSupport.partialFieldMapping,
    extractor: MyExtractor(),
    declaredFields: [DocumentFieldId.documentNumber],
  ),
);
```

## Privacy

- **Nothing leaves the device.** No image, no extracted text, no analytics. The
  only exception is an OCR adapter you supply yourself, which reports
  `isOffDevice: true`.
- **Images are temporary.** Captures are written to a plugin-owned temporary
  directory. Ownership passes to your application with the result: copy what
  you want to keep, and call `dispose()` on the result to delete the rest. The
  plugin makes no promise about how long its temporary directory survives.
- **Sensitive values are never logged.** Names, ID numbers, dates and document
  images do not appear in any log or error message the package produces.
  `SmartCaptureException.message` is developer-facing and free of personal data.
- **The repository contains no real documents.** Tests use synthetic strings.
  No real identity-card image or personal data may be added to this repository,
  its fixtures, its screenshots or its example app.

## Platform support

| Platform | Minimum |
|---|---|
| Android | `minSdk 24` |
| iOS | 15.5 (raised from 15.0 by `google_mlkit_commons`; Arabic OCR needs iOS 16+) |

Web, macOS, Windows and Linux are not supported and are not declared.

### Permissions your app must declare

- **Android:** `android.permission.CAMERA` is merged in automatically by the
  `camera` plugin — no action needed in your app's manifest.
- **iOS:** add `NSCameraUsageDescription` to your `Info.plist` yourself; unlike
  Android, this is not injected automatically. Capture will fail with
  `SmartCaptureErrorCode.cameraPermissionDenied` without it.

### A known iOS Simulator limitation

The ML Kit iOS pods (`GoogleMLKit`, `MLKitCommon`, `MLKitFaceDetection`,
`MLKitVision`) ship no arm64 Simulator slice, only x86_64. Xcode handles this
by building the whole app x86_64-only for the simulator, which then runs under
Rosetta — slower, but functional. Real devices build and run arm64 natively
and are unaffected; this is a simulator-only wrinkle in the upstream pods, not
something this package can fix.

## Example

```
cd example && flutter run
```

The example app exercises the implemented surface: profile registry, guidance
localization in English and Arabic, live text normalization, and the structured
error the unimplemented capture flows raise.

## Development

```
flutter analyze
flutter test
```

Phases and their acceptance criteria are tracked in `project.md`.

## License

MIT — see [LICENSE](LICENSE).
