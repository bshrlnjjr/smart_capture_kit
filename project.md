You are my senior Flutter, Android, iOS, and computer vision engineering partner. Build a production-quality, open-source Flutter plugin that we can eventually publish on pub.dev.

## Project vision

Create a Flutter plugin for guided portrait and identity-card capture. It should help users take clear photos, scan the front and back of an ID card, extract visible text, and return structured fields to the host application.

The working name is `smart_capture_kit`. Check whether this name is available on pub.dev before treating it as final.

This is a reusable developer package, not a standalone consumer app. Include an example Flutter application that demonstrates every supported feature.

## Core principles

* Build a focused, maintainable public API that another Flutter developer can integrate easily.
* Perform capture guidance and image-quality checks on-device where practical.
* Never claim that a photo meets every government's official requirements.
* Never claim that OCR results establish a person's identity or prove a document is authentic.
* Never invent missing identity data. Return `null` or an explicit uncertainty state.
* Let the host application control whether images or extracted data are stored or uploaded.
* Do not upload identity documents to any service without an explicit application-level configuration and user-facing disclosure.
* Keep API keys and cloud credentials out of the Flutter plugin.
* Treat names, ID numbers, dates, and document images as sensitive data. Do not print them in production logs or analytics.

## Feature 1: Guided portrait capture

Provide a camera screen and a reusable controller/API. Show an overlay indicating where the user's face should appear. Analyze camera frames at a controlled rate and give concise, localized guidance, such as:

* No face detected.
* More than one face detected.
* Move closer or farther away.
* Move left or right.
* Look straight at the camera.
* Improve lighting.
* Hold still.

After capture, evaluate the final high-resolution image for face count, framing, head orientation, exposure, and sharpness. Return the image and individual check results. Allow applications to configure thresholds and the desired output aspect ratio. Keep the original image separate from an optional cropped output.

Do not automatically reject an image solely because a model produced a low-confidence result. Explain the reason and allow the host application to decide whether the user may continue.

## Feature 2: Guided ID-card capture

Support front-only and front-and-back capture flows. Show a card-shaped overlay. Detect the document boundary and guide the user to fit all four corners inside the frame.

Check for:

* Missing or cut-off corners.
* Excessive perspective distortion.
* Blur.
* Low light or overexposure.
* Glare covering important text.
* Insufficient document size within the image.

After capture, detect the four corners, correct perspective, and return both the original and cropped/rectified images. Show a review screen with Retake and Continue actions. Support configurable card aspect ratios because document dimensions vary.

Start with one documented reference profile for a Jordanian identity-card use case, but do not hard-code assumptions about field positions or layouts before inspecting legally obtained, appropriately redacted samples. Design the configuration so other document profiles can be added later.

## Feature 3: OCR and structured field extraction

Extract ALL visible text from the front and back. Return:

1. Raw text for each side.
2. Individual text lines or blocks with their bounding boxes and OCR confidence when available.
3. Structured fields when supported by a document profile.
4. A status for every field: recognized, uncertain, missing, or manually corrected.
5. Evidence linking each extracted field to the source text and document side.

Candidate structured fields include full name in Arabic and/or English, national ID number, date of birth, sex where printed, issue date, expiration date, and any other fields actually present on the supported document. Never assume a field exists.

Use a layered extraction strategy:

* First capture and rectify the document.
* Then run OCR.
* Then map recognized text to document-specific fields using labels, relative position, formatting rules, and confidence.
* Normalize Arabic and Western digits only for comparison or validated output; preserve the exact raw OCR text.
* Validate formats where appropriate, but do not silently change ambiguous characters or dates.
* Present uncertain fields for manual review and correction.

Arabic OCR is a critical requirement. Before choosing an engine, research and verify its current Arabic support on both Android and iOS using official documentation and a small working prototype. Do not assume that ML Kit Text Recognition v2 provides reliable Arabic-script OCR. Compare viable on-device solutions with an optional cloud OCR approach. Document accuracy, model size, platform support, latency, offline behavior, licensing, and privacy tradeoffs.

If cloud OCR is offered, make it an optional adapter supplied or configured by the host application through its own backend. Do not bake a cloud provider or credentials into the default capture flow. The core capture features must work without that adapter.

## AI and native architecture

Evaluate the current official capabilities of ML Kit on Android and iOS, Apple Vision on iOS, and any additional engine needed for Arabic OCR. Choose tools based on verified capabilities rather than forcing every feature into one SDK.

Separate the implementation into clear components:

* Flutter public API and UI.
* Camera and native frame handling.
* Portrait analysis.
* Card-boundary and quality analysis.
* Image rectification.
* OCR engine abstraction.
* Document-profile extraction.
* Result models and review flow.

Avoid running expensive analysis on every camera frame. Define frame throttling, backpressure, cancellation, lifecycle handling, and resource cleanup. Perform a final quality pass on the captured image rather than relying only on low-resolution preview frames.

Support Android and iOS first. Do not advertise web or desktop support unless it is implemented and tested. Explain minimum OS versions and native dependencies accurately.

## Developer-facing API

Design an API along these lines, but improve it if you find a clearer design:

```dart
final portrait = await SmartCapture.capturePortrait(
  context,
  options: const PortraitCaptureOptions(),
);

final document = await SmartCapture.captureDocument(
  context,
  options: DocumentCaptureOptions(
    documentProfile: 'jo_national_id',
    sides: DocumentSides.frontAndBack,
    ocr: true,
  ),
);
```

The result should expose images, quality checks, raw OCR, extracted fields, and errors as typed models. Use enums and structured error types rather than unstructured message strings. Allow the host app to replace UI labels and guide messages in Arabic or English.

## Privacy and security

* Do not persist images by default beyond what is necessary for capture and processing.
* Document ownership and cleanup of temporary files.
* Do not include real identity-card images or personal information in the public repository, screenshots, examples, fixtures, or logs.
* Use synthetic or fully redacted sample documents in tests.
* Clearly distinguish document capture/OCR from identity verification, face matching, fraud detection, and liveness detection. These are outside the initial scope.
* Document when an optional OCR adapter sends data off-device.

## Development phases

Work in small, reviewable phases:

1. Inspect the repository and current Flutter/Android/iOS tooling. If the repository is empty, create the plugin and example app.
2. Research the relevant native APIs and Arabic OCR options. Produce a short technical decision record with sources and unresolved risks.
3. Define the public API, result models, errors, configuration, and package structure.
4. Implement portrait capture and its example screen.
5. Implement front/back card capture, guidance, quality checks, and perspective correction.
6. Prototype OCR on representative Arabic and English samples. Report measured results before selecting the production OCR implementation.
7. Implement raw OCR results and document-profile-based field extraction.
8. Implement review and correction of uncertain fields in the example app.
9. Add meaningful unit tests for parsing and validation, plus native/integration tests for behavior that cannot be verified with unit tests.
10. Prepare the package for pub.dev: README with integration and privacy details, complete example, API documentation, CHANGELOG, LICENSE, platform setup instructions, supported-platform declarations, analysis, tests, and publish dry run.

For each phase, show what changed, how it was tested, and any known limitation. Do not jump ahead to publishing.

## Acceptance criteria

* A developer can integrate the plugin using a documented API and run the example application.
* A user can capture and review a portrait photo.
* A user can capture and review both sides of an ID card.
* The application receives original and corrected card images and explicit quality-check results.
* OCR returns the visible text and, for supported document profiles, structured fields with evidence and uncertainty states.
* Arabic text is supported only after its actual behavior has been demonstrated on both target platforms or through a clearly documented optional engine.
* A user can correct extracted fields before the host app uses them.
* No identity images or extracted personal data leave the device by default.
* Android and iOS builds, analysis, relevant tests, and `dart pub publish --dry-run` pass before any publication proposal.

## How to start now

First, inspect the workspace and tell me whether a Flutter project already exists. Then research the current platform and OCR capabilities and propose a concrete architecture, public API, and phased implementation plan. Identify the smallest working milestone and implement it. Continue making reviewable progress, but do not publish the package to pub.dev or upload any real identity documents without my explicit instruction.
