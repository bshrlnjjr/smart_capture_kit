# ADR 0002: Document boundary detection in pure Dart

- Status: Accepted (revisit after real-device testing of the document flow)
- Date: 2026-09-26
- Deciders: project owner + engineering
- Supersedes: none

## Context

Phase 5 needs the four corners of an ID card, both live (to guide the user)
and on the full-resolution still (to perspective-correct it). Options:

1. **Pure Dart heuristic** on top of the `image` package, already a
   dependency.
2. **OpenCV** via a Flutter binding or FFI build: robust contour finding, but
   adds several MB per ABI, a native build step, and a binding that must be
   kept current on both platforms.
3. **Platform document scanners** (Apple VisionKit
   `VNDocumentCameraViewController` / `VNDetectRectanglesRequest`, ML Kit
   Document Scanner on Android): good quality, but VisionKit's scanner and
   ML Kit's scanner each own their own UI, which breaks the plugin's
   consistent guided flow and review screen; Android's scanner also depends
   on Google Play services.

## Decision

Use a pure Dart classical pipeline (`detectDocumentBoundary`):

1. Downscale to at most 480 px (320 px for live frames).
2. Sobel gradient magnitude, thresholded at 20% of its own maximum (relative,
   so exposure does not shift it), then one round of dilation.
3. Flood fill from the image border across non-edge pixels; the unreached
   region is the document interior.
4. Convex hull of the interior boundary, reduced to four corners by extreme
   distance per quadrant around the centroid.
5. Reject implausible results (area outside 5%–98% of the frame) as `null`.

Live frames are converted to a small upright luminance image off the UI
isolate (`document_live_detection.dart`): NV21's Y plane on Android, BGRA
converted to Rec. 601 luma on iOS, box-averaged, then rotated by the same
sensor/device rotation ML Kit uses for the portrait flow.

## Consequences

- No new native dependency; identical behavior on Android and iOS; fully
  unit-testable on synthetic images.
- Known weak cases: a background with no contrast against the card, a card
  touching the frame edge, and heavy clutter. All of these return `null`
  (no guess), which live guidance reports as "point the camera at the card"
  and the final report as a failed `documentCornersDetected` check.
- Aspect-ratio checks must measure in pixels, not normalized coordinates:
  `Quad.estimatedAspectRatio` takes the image's own aspect ratio for this
  reason.
- Perspective distortion is measured by comparing opposite sides in
  normalized units, which is exact for axis-aligned cards and approximate for
  rotated ones on non-square frames.

## What would justify switching

Move to OpenCV or a platform rectangle detector if real-device testing shows
the heuristic failing on ordinary backgrounds (desk, hand, fabric) often
enough that users routinely fall back to the manual shutter, or if detection
time on a mid-range Android device exceeds the analysis interval.
