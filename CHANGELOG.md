# Changelog

## 0.0.1 — unreleased

Not published. The package is in early development; see the status table in
the README for what works today.

### Added

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

- Camera capture, quality analysis, perspective correction and OCR are not
  implemented. `SmartCapture.capturePortrait` and
  `SmartCapture.captureDocument` validate their options and then throw.
- Arabic support on iOS is inferred from a macOS Vision probe and has not yet
  been confirmed on a physical device.
- No Arabic OCR accuracy has been measured on real captures.
