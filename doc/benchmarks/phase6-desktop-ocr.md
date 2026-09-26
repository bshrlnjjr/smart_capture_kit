# Phase 6 OCR benchmark — desktop proxy run

- Date: 2026-09-26
- Machine: Apple M1, macOS 26.6
- Status: **Desktop proxy only.** No phone was used and no real document was
  used. Read the limits section before quoting any number.

## What was measured

20 synthetic ID-1 cards, each rendered in 6 variants (120 images), with known
ground truth. Every card carries only made-up values, is stamped "SYNTHETIC
TEST CARD — NOT A REAL DOCUMENT", and copies no real document design.

Each card has:

- 4 Arabic lines (name, date of birth, place of birth, sex), right-aligned.
- 4 English lines (name, date of birth, sex, expiry).
- 1 mixed line: `الرقم الوطني National No. 999xxxxxxx`.
- Arabic fonts rotating through Geeza Pro, Al Nile, Arial and SF Arabic.
  English fonts rotating through Helvetica, Arial and Menlo.
- The Arabic date printed in Arabic-Indic digits on half the cards
  (`١٥/٠٤/١٩٨٧`) and in Western digits on the other half.
- A light wavy background pattern, standing in for card security printing.

The variants approximate what the capture pipeline hands to OCR. OCR runs
on the rectified image, so these are flat, not perspective-skewed.

| Variant | Meaning |
|---|---|
| clean | 1400 px wide, which is the rectified output size |
| lowres | 700 px wide: roughly a card filling 35% of a 1080p frame, the smallest the capture guidance accepts |
| blur | Gaussian blur, sigma 1.6 |
| glare | strong specular highlight over part of the Arabic block |
| rotated | 3° rotation, standing in for a slightly-off rectification |
| noisy_jpeg | sensor-like noise plus JPEG quality 0.35 |

Engines:

- **Vision**: Apple Vision `VNRecognizeTextRequest`, revision 3,
  `.accurate`, languages `ar-SA` + `en-US`. Run once without language
  correction and once with it ("+ LC").
- **Tesseract 5.5.3**: `-l ara+eng`, with either the `tessdata_fast` or the
  `tessdata_best` models, page segmentation mode 6 (one uniform block of
  text) or 3 (automatic).

Reproduce with the scripts in `tool/ocr_benchmark/` (see its README).

## Results

CER is the character error rate: each ground-truth line is scored against
its best-matching recognized line, after stripping only meaningless
differences (invisible direction marks, whitespace, dash variants).

### Arabic CER

| engine | blur | clean | glare | lowres | noisy_jpeg | rotated |
|---|---|---|---|---|---|---|
| Vision | 0.0% | 0.3% | 0.6% | 0.1% | 0.0% | 0.3% |
| Vision + LC | 0.0% | 0.1% | 0.4% | 0.0% | 0.0% | 0.3% |
| Tess fast psm6 | 13.6% | 17.5% | 31.3% | 17.2% | 17.2% | 24.9% |
| Tess best psm6 | 11.0% | 17.5% | 28.2% | 17.2% | 15.3% | 27.4% |
| Tess best psm3 | 8.0% | 10.4% | 26.7% | 15.7% | 12.5% | 14.4% |

The order-insensitive CER sorts each line's words before comparing. It is
within a few points of the table above, so Tesseract's errors are real
misreads and dropped lines, not just word order.

### Latin CER

Every engine is at or below 2.6% in every variant. Vision stays at or below
0.2%.

### Key-field accuracy

A field counts as correct when its exact value (digits compared in either
form) appears in the recognized text. Arabic fields only count when read
from a line that actually contains Arabic.

| engine | blur | clean | glare | lowres | noisy_jpeg | rotated |
|---|---|---|---|---|---|---|
| Vision | 100.0% | 96.9% | 94.4% | 99.4% | 100.0% | 99.4% |
| Vision + LC | 100.0% | 98.1% | 96.2% | 100.0% | 100.0% | 99.4% |
| Tess fast psm6 | 88.1% | 85.6% | 66.2% | 88.8% | 85.0% | 81.2% |
| Tess best psm6 | 87.5% | 86.9% | 68.1% | 89.4% | 88.8% | 77.5% |
| Tess best psm3 | 88.1% | 85.0% | 66.2% | 81.2% | 84.4% | 73.8% |

Per field, all variants pooled:

| engine | dob_ar (Arabic-Indic) | dob_ar (Western) | name_ar | place_ar | sex_ar | name_en | dob_en | expiry | national_no |
|---|---|---|---|---|---|---|---|---|---|
| Vision | 100% | 100% | 100% | 95.0% | 94.2% | 97.5% | 100% | 100% | 100% |
| Vision + LC | 100% | 100% | 100% | 95.0% | 100% | 96.7% | 100% | 100% | 100% |
| Tess fast psm6 | **0%** | 83.3% | 80.8% | 74.2% | 76.7% | 94.2% | 96.7% | 98.3% | 97.5% |
| Tess best psm6 | **0%** | 81.7% | 86.7% | 78.3% | 83.3% | 83.3% | 97.5% | 97.5% | 96.7% |
| Tess best psm3 | **0%** | 81.7% | 88.3% | 75.8% | 64.2% | 84.2% | 95.8% | 90.0% | 99.2% |

### Latency

Median time for one clean image, with each engine run on its own. The
Tesseract figures include starting the command-line program and loading its
model for every image, which a persistent in-app engine would do only once.

| engine | median ms |
|---|---|
| Vision | 114 |
| Vision + LC | 136 |
| Tesseract fast | 349 |
| Tesseract best | 735 |

## Findings

1. **Apple Vision is close to perfect on this set, Arabic included.** Its
   only repeated error drops the last letter of a short Arabic value at the
   end of a line ("ذكر" → "ذك", "العقبة" → "العقب"), mostly under glare.
   Language correction fixed the sex field without hurting the others.
2. **Tesseract cannot read Arabic-Indic digits: 0 of 60 dates.** This is
   not the English model interfering; with `-l ara` alone the output is
   still a mix of Arabic-Indic and Western digit shapes, e.g.
   `١٠١/١ /١56/1` for `١٥/٠٤/١٩٨٧`. If a supported document prints dates or
   numbers in Arabic-Indic digits, Tesseract on Android will not extract
   them.
3. **Tesseract drops whole Arabic lines under glare**, taking field accuracy
   to about 66–68%. Vision stays at 94–96% on the same images.
4. **Tesseract writes mixed Arabic-and-digit lines in visual order**:
   `01/08/1984 تاريخ الولادة:` rather than label first, value second.
   Field extraction (phase 7) must not assume the label comes first in the
   raw string.
5. **Tesseract wraps every Arabic line in invisible direction marks**
   (U+200F at the start, U+200E at the end). `normalizeForComparison` already
   stripped these; this run also added U+061C (the Arabic Letter Mark),
   which it had missed.
6. **The `best` models do not justify their cost.** They are within noise of
   `fast` on accuracy, at about twice the latency and a 12.6 MB instead of
   1.4 MB Arabic model. psm 3 was not consistently better than psm 6.
7. Tesseract reads blurred cards slightly better than clean ones.
   Presumably the blur hides the wavy background pattern. This suggests
   denoising before Tesseract is worth trying.

## What this does not tell us

- **No phone numbers.** Vision was measured on macOS, not an iPhone.
  Tesseract was measured as the desktop command-line program, not
  `flutter_tesseract_ocr` on Android. ML Kit (the Android Latin engine)
  cannot run here at all and is **not measured**.
- **Synthetic cards are easier than real ones.** They have no lamination
  texture, no worn edges, clean system fonts, and no real security
  printing. Real error rates will be higher for every engine.
- **Language correction is flattered here.** The synthetic names are common
  dictionary words. On rare family names, correction may "fix" a correct
  reading into a wrong one, which this set cannot show.
- **Real card fonts and layout are unknown.** Nothing is known yet about
  the target card's actual fonts, layout, or which digits it prints.

## Recommendation (provisional, pending device runs)

- **iOS:** keep Apple Vision (revision 3, `.accurate`) as ADR 0001 decided.
  Leave language correction **off** by default: it rewrites text toward
  dictionary words, which conflicts with the rule that raw text is never
  silently repaired. Expose it as an option. Make a short Arabic value at
  the end of a line more likely to be flagged uncertain in phase 7.
- **Android, Arabic:** Tesseract is usable only as a weak fallback. If
  adopted, use `tessdata_fast` `ara` (1.4 MB) with psm 6, and treat every
  Arabic field it produces as more likely to be uncertain. Tesseract should
  not be the final choice until two things are checked:
  1. Whether the target document prints Arabic-Indic digits. If it does,
     Tesseract cannot be used for those fields.
  2. How a stronger on-device Arabic engine (PaddleOCR's Arabic model, or a
     TFLite text recognizer) compares on this same set. ADR 0001 rejected
     PaddleOCR on binding maturity, not accuracy. These numbers make its
     accuracy worth measuring.
- **Android, update after the PaddleOCR run below:** PaddleOCR's Arabic
  mobile model, paired with a Latin recognizer on the same detected lines,
  beat Tesseract in every variant (90–94% vs 66–89%). It is now the
  preferred Android candidate, with ML Kit as the Latin half. Arabic-Indic
  digits remain unread on Android either way.
- **Android, Latin:** ML Kit is unmeasured. Measure it on a device before
  relying on it.

## PaddleOCR (added the same day)

Engine setup: PaddleOCR 3.7 with PaddlePaddle 3.3 on the M1 CPU, using the
**mobile** models an on-device build would ship: `PP-OCRv5_mobile_det`
(4.8 MB) for detection and `arabic_PP-OCRv5_mobile_rec` (7.8 MB) for
recognition. Two setup traps:

- By default PaddleOCR picks the server-size detector, which is 84 MB and
  took about 10.8 s per image.
- Naming a detection model makes PaddleOCR ignore `lang` and switch to its
  general recognizer, which cannot read Arabic, so the Arabic recognizer has
  to be named explicitly. `run_paddle.py` does both.

Three configurations were scored. All use the same detector.

- **Paddle ar**: the Arabic recognizer alone.
- **Paddle en**: `en_PP-OCRv5_mobile_rec` alone.
- **Paddle ar+en**: one detection pass read by both recognizers, merged by
  `merge_passes.py`. Arabic words come from the Arabic pass; digits and
  Latin text come from the English pass.

| engine | blur | clean | glare | lowres | noisy_jpeg | rotated |
|---|---|---|---|---|---|---|
| Key-field accuracy, Paddle ar | 73.8% | 74.4% | 72.5% | 70.6% | 73.1% | 73.8% |
| Key-field accuracy, Paddle ar+en | 93.1% | 93.8% | 91.9% | 90.0% | 92.5% | 93.1% |
| (Tess fast psm6, for reference) | 88.1% | 85.6% | 66.2% | 88.8% | 85.0% | 81.2% |

Per field, all variants pooled:

| engine | dob_ar (Arabic-Indic) | dob_ar (Western) | name_ar | place_ar | sex_ar | name_en | national_no |
|---|---|---|---|---|---|---|---|
| Paddle ar | 0% | **0%** | 98.3% | 99.2% | 94.2% | 92.5% | **0%** |
| Paddle ar+en | **0%** | 100% | 98.3% | 99.2% | 94.2% | 99.2% | 98.3% |

Findings:

1. **The Arabic recognizer silently drops digit runs from mixed lines.** The
   detection box covers the whole line, digits included, yet the output is
   only the Arabic words, at 0.89–0.93 confidence. Examples:
   `تاريخ الولادة` with the date missing, and `الرقم الوطني` with
   "National No. 999…" missing. This is the most dangerous failure seen in
   this benchmark: a confident, incomplete answer that an uncertainty flag
   will not catch. PaddleOCR's Arabic model must never be used alone for
   fields containing numbers.
2. **Arabic words are the strongest on Android and hold up under glare.**
   Arabic names 98%, places 99%, and no collapse under glare (Tesseract lost
   up to a third of the lines there).
3. **Arabic-Indic digits are still unread: 0%.** Neither recognizer handles
   them. The English pass produces junk such as `10/./V` for them, but at
   low confidence (~0.6), so that junk would at least be flagged.
4. **It dropped colons in Arabic lines.** This accounts for most of Paddle's
   12–20% Arabic CER. It does not affect field values.
5. **Latency here (2–3 s per pass on the CPU) says little about phones.**
   Phones would run Paddle Lite with mobile-optimized kernels. The ar+en
   figure also counts detection twice. Speed has to be measured on a
   device.

## Field extraction on the recorded output (phase 7)

`tool/ocr_benchmark/extract_eval.dart` runs `RuleBasedFieldExtractor` over
each engine's recorded output, with label rules for the synthetic card, and
sorts every field into one of four outcomes. **WRONG** means the field was
marked `recognized` with a wrong value. That is the outcome the extractor
exists to prevent: everything else is either correct or visibly flagged for
review.

| engine | correct | WRONG | uncertain | missing |
|---|---|---|---|---|
| Vision | 94.0% | 1.0% | 5.0% | 0.0% |
| Tesseract fast | 91.2% | 2.5% | 4.0% | 2.3% |
| Paddle ar | 78.7% | 0.1% | 11.0% | 10.2% |
| Paddle ar+en | 84.4% | 0.1% | 5.2% | 10.2% |

Two checks added during this evaluation catch most wrong values that
otherwise look well formed:

- A text field declared as one script, but containing letters of the other
  script or any digit (`Aلali`, `المصري 1`).
- An uppercase letter inside a mixed-case word (`AInajjar`, `ALzoubi`), the
  classic `I`/`l` confusion.

Together they cut Tesseract's WRONG rate from 4.5% to 2.5%, and PaddleOCR
Arabic + English from 0.6% to 0.1%.

What is left is misread Arabic in free text: a dropped last letter
(`العقب`) or a misplaced dot (`إريد` for `إربد`, `ماديا` for `مادبا`).
Nothing about the format gives these away. Vision's confidence cannot catch
them either: it gives almost every line the same score (0.3, 0.5 or 1.0),
and raising the floor to 0.75 flags 92% of all fields. So the review step,
not the extractor, must catch these: free-text fields should be shown next
to their source image crop in phase 8.

## Next measurements needed

1. Run the same 120 images through Vision on an iPhone and through ML Kit
   and `flutter_tesseract_ocr` on an Android phone, using an on-device
   harness in the example app.
2. ~~Run the same images through a PaddleOCR Arabic model on the desktop.~~
   Done; see the PaddleOCR section above.
3. Photograph printed, laminated synthetic cards with the real capture
   flow, so OCR is scored on real rectification output.
4. Once legally obtained, redacted samples of the target document exist,
   record their fonts, layout and digit style only; do not commit them.
