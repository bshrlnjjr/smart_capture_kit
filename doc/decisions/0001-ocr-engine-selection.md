# ADR 0001: OCR engine selection, with emphasis on Arabic script

- Status: Accepted (revisit after Phase 6 prototype measurements on real devices)
- Date: 2026-09-23
- Deciders: project owner + engineering
- Supersedes: none

## Context

`smart_capture_kit` must extract **all visible text** from both sides of an identity
card, and Arabic script is a hard requirement rather than a nice-to-have. The initial
reference profile is a Jordanian national ID, whose front carries Arabic text and
whose fields we cannot assume until legally obtained, redacted samples are inspected.

The project constraints that bind this decision:

- Capture and OCR must work **offline by default**. No cloud provider or credential
  may be baked into the default flow.
- The plugin targets Android and iOS only.
- We must not claim Arabic support that has not been demonstrated.

## Evidence gathered

### Apple Vision — measured, not assumed

Ran a probe against the Vision framework on the development machine
(macOS 27, Xcode 27) rather than relying on documentation. Source is checked in at
`tool/probe_vision_languages.swift`; reproduce with `swift tool/probe_vision_languages.swift`.

Result:

```
=== Legacy VNRecognizeTextRequest ===
rev 1 accurate: count=1  arabic=[]
rev 1 fast:     count=1  arabic=[]
rev 2 accurate: count=8  arabic=[]
rev 2 fast:     count=6  arabic=[]
rev 3 accurate: count=30 arabic=["ar-SA", "ars-SA"]
rev 3 fast:     count=6  arabic=[]

=== New Vision RecognizeTextRequest (Swift) ===
count=30 arabic=["ar-Arab-SA", "ars-Arab-SA"]
```

Two findings matter and neither is obvious from the prose documentation:

1. Apple Vision **does** recognise Arabic script (`ar-SA`, and `ars-SA` for
   Najdi Arabic).
2. Arabic exists **only at revision 3 with `.accurate` recognition level**. The
   `.fast` level supports 6 Latin languages and silently drops Arabic — a request
   configured with `.fast` and `recognitionLanguages = ["ar-SA"]` does not error, it
   simply returns no Arabic. Any Arabic path in this plugin must therefore pin
   `.accurate`, and must never use `.fast` as a "preview frame" optimisation for
   Arabic documents.

Caveat, stated plainly: this probe ran against **macOS** Vision. The revision-3 model
family is shared with iOS 16+, but the numbers above are not yet confirmed on an iOS
device. Phase 6 must re-run the equivalent query on a physical iPhone and record the
result here before the README claims iOS Arabic support.

### Google ML Kit Text Recognition v2 — no Arabic

Per the official supported-languages page, v2 recognises Latin, Chinese (Hans/Hant),
Devanagari, Japanese and Korean script models. Arabic appears in none of the three
support tiers (supported, experimental, or mapped). There is no Arabic model to
download and no experimental flag to enable.

This is the decisive constraint: **Android has no first-party offline Arabic OCR.**

### Candidate comparison

| Engine | Android Arabic | iOS Arabic | Model size | Licence | Offline | Credentials |
|---|---|---|---|---|---|---|
| ML Kit Text Recognition v2 | No | No | ~4 MB bundled or on-demand | Apache-2.0 (binary ToS) | Yes | None |
| Apple Vision | N/A | Yes (rev 3, `.accurate`) | 0 — OS-resident | System framework | Yes | None |
| Tesseract 5 (LSTM) + `ara.traineddata` | Yes | Yes | ~15 MB for `ara`+`eng` | Apache-2.0 | Yes | None |
| PaddleOCR (Paddle Lite) | Yes | Yes | ~10 MB | Apache-2.0 | Yes | None |
| Cloud (Google Cloud Vision, Azure AI Vision, etc.) | Yes | Yes | 0 | Commercial | **No** | Required |

Accuracy note, held deliberately loose: no accuracy figures are asserted here because
none have been measured yet on representative samples. Phase 6 exists to produce
those numbers. Published third-party benchmarks are not a substitute, because they
are run on clean scanned pages rather than on a hand-held phone capture of a laminated
card under glare.

### Why not PaddleOCR

Technically credible and Arabic-capable, but the only Flutter binding on pub.dev
(`flutter_paddle_ocr`) sits at version `0.0.2`. Taking a `0.0.x` transitive dependency
on the critical path of a package we intend to publish is a maintenance liability.
Reconsider if the binding matures or if Phase 6 shows Tesseract accuracy is
unacceptable.

## Decision

Adopt a **per-platform, per-script engine strategy behind a single abstraction**.

```
OcrEngine (abstract)
├── VisionOcrEngine        iOS      — Apple Vision, revision 3, .accurate
├── MlKitOcrEngine         Android  — Latin script only
├── TesseractOcrEngine     both     — Arabic script, bundled `ara` + `eng` traineddata
└── <host-supplied>        both     — optional cloud adapter, see below
```

Default engine resolution:

| Platform | Latin / English | Arabic |
|---|---|---|
| iOS | Apple Vision | Apple Vision |
| Android | ML Kit v2 | Tesseract (`ara`) |

Rationale for each leg:

- **iOS uses Vision for both scripts.** Zero model download, no licence question,
  and it is the only engine here that ships already trained inside the OS. Pinned to
  revision 3 and `.accurate` because the probe proves Arabic exists nowhere else.
- **Android uses ML Kit for Latin.** It is faster and more accurate than Tesseract on
  Latin text and is already a dependency for face detection.
- **Android uses Tesseract for Arabic** because nothing first-party exists. Chosen
  over PaddleOCR on dependency-maturity grounds, not on accuracy grounds.

### Consequences we accept

- The package carries roughly 15 MB of `traineddata` for Android Arabic. This is a
  real cost and it is documented in the README rather than hidden.
- **Arabic results on Android will be measurably worse than on iOS**, particularly
  under glare, perspective skew and lamination reflections. This asymmetry must not
  be papered over. Two mitigations follow directly from it:
  - Field extraction reports per-field confidence and an explicit `uncertain` status,
    and the review screen surfaces uncertain fields for manual correction. A weaker
    engine produces more `uncertain` fields — it does not produce silent wrong answers.
  - `OcrResult` records which engine produced each block, so a host application can
    apply a stricter confidence floor on Android if it chooses.
- Two code paths for Arabic means two sets of quirks to maintain. Accepted as the
  cost of offline-by-default.

### Cloud OCR

Offered strictly as an **optional adapter implemented by the host application**:

```dart
abstract class OcrEngine {
  Future<OcrPageResult> recognize(OcrRequest request);
}
```

The plugin ships **no** cloud implementation, no provider SDK, and no credential
storage. A host that wants cloud OCR implements `OcrEngine` against its own backend
and passes it in through options. The core capture and quality-check features work
with the adapter absent. When an adapter is supplied, the plugin surfaces
`OcrEngineDescriptor.isOffDevice == true` so the host can render its own disclosure.

## Preserving raw text

Independent of engine choice: the exact OCR string is preserved verbatim on every
block. Arabic-Indic to Western digit normalisation, whitespace collapsing and
bidirectional-text reordering happen **only** in derived comparison values, never in
place. Ambiguous characters are never silently repaired. This is what makes the
`uncertain` status honest.

## Open risks

1. iOS Arabic support is inferred from a macOS probe. Confirm on device (Phase 6).
2. Tesseract Arabic accuracy on real ID-card captures is unmeasured (Phase 6).
3. Tesseract binding `flutter_tesseract_ocr` is community-maintained; evaluate
   vendoring the native layer if it goes unmaintained.
4. Arabic is a cursive, right-to-left script with contextual letter forms and optional
   diacritics. Bounding boxes for logical text ranges may not be contiguous. The
   evidence model must tolerate a field mapping to multiple disjoint boxes.
5. Jordanian ID field layout is **not** encoded anywhere yet, by design. No layout
   assumption may be committed before redacted samples are inspected.

## Addendum (phase 4): iOS toolchain constraints discovered while wiring portrait capture

Two facts surfaced while integrating `google_mlkit_face_detection` for live
portrait guidance, neither about OCR directly but both affecting the platform
floor this package can declare:

1. **`google_mlkit_commons` 0.13.0 requires iOS 15.5+**, not 15.0. `pod install`
   refuses to build below it. The package's iOS deployment target is raised
   to 15.5 accordingly (`ios/smart_capture_kit.podspec`,
   `ios/smart_capture_kit/Package.swift`, and the example's Xcode project).
2. **The ML Kit iOS pods ship no arm64 Simulator slice.** Confirmed by Xcode's
   own build output: `GoogleMLKit`, `MLImage`, `MLKitCommon`,
   `MLKitFaceDetection` and `MLKitVision` are flagged as x86_64-only for
   simulator, and Xcode responds by building the entire Runner target
   x86_64-only for that destination. It still runs, under Rosetta, so this is
   a performance and CI-runner-architecture footnote rather than a capability
   gap — but it means a future CI job building the example for the simulator
   needs an x86_64-capable (or Rosetta-enabled) runner, and it does not affect
   physical-device builds, which link the pods' arm64 device slice normally.

## Addendum (phase 6): first measurements, desktop proxy

Full method and tables: `doc/benchmarks/phase6-desktop-ocr.md`. These are
120 synthetic card images run on macOS, not phones, so they bound the
problem rather than settle it.

- Apple Vision (revision 3, `.accurate`) read the synthetic set almost
  perfectly: Arabic CER at or below 0.6% and 94–100% key-field accuracy in
  every variant, including Arabic-Indic digits. Open risk 1 (iOS Arabic) is
  reduced but still needs one iPhone run.
- Tesseract `ara` did markedly worse: 10–31% Arabic CER, and 66–89%
  key-field accuracy. It read **0 of 60 Arabic-Indic dates**, even with the
  Arabic model alone. The Android Arabic leg of this decision is therefore
  **downgraded to provisional**. It stands only if the target document does
  not rely on Arabic-Indic digits, and only after a stronger on-device Arabic
  engine has been measured on the same set.
- If Tesseract is kept, the model is `tessdata_fast` `ara` (1.4 MB), not
  `best`. The two were within noise on accuracy, and `best` is 2x slower
  and 9x larger. That replaces the ~15 MB estimate above: Latin is ML
  Kit's job on Android, so `eng` need not ship.
- Language correction on Vision stays off by default. It rewrites text
  toward dictionary words, which conflicts with the rule that raw text is
  never silently repaired.
