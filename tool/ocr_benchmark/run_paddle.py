#!/usr/bin/env python3
"""Runs PaddleOCR over every PNG in a directory for the phase 6 OCR
benchmark, writing the same JSON shape as run_vision.swift.

Usage (needs a Python 3.12 venv with `pip install paddlepaddle paddleocr`):
  python tool/ocr_benchmark/run_paddle.py <samples_dir> <out.json> \
      [--det PP-OCRv5_mobile_det] [--rec arabic_PP-OCRv5_mobile_rec] [--limit N]

Uses the mobile detection and Arabic recognition models by default, with
document orientation, unwarping and text-line orientation turned off: the
plugin hands OCR an already rectified, upright card, so those stages would
only add latency. The model names actually used are printed, so results can
be tied to a specific model rather than to "PaddleOCR" in general.
"""

import argparse
import json
import os
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("samples_dir")
    parser.add_argument("out")
    parser.add_argument("--limit", type=int, default=0)
    # The mobile detector is what an on-device build would ship; PaddleOCR's
    # default is the far heavier server detector.
    parser.add_argument("--det", default="PP-OCRv5_mobile_det")
    # Pinned explicitly: naming a detector makes PaddleOCR ignore `lang` and
    # fall back to its general (non-Arabic) recognizer.
    parser.add_argument("--rec", default="arabic_PP-OCRv5_mobile_rec")
    parser.add_argument("--dump-boxes", action="store_true")
    args = parser.parse_args()

    from paddleocr import PaddleOCR

    ocr = PaddleOCR(
        text_detection_model_name=args.det,
        text_recognition_model_name=args.rec,
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
    )

    files = sorted(f for f in os.listdir(args.samples_dir) if f.endswith(".png"))
    if args.limit:
        files = files[: args.limit]

    # Warm-up so model loading is not counted against the first image.
    ocr.predict(os.path.join(args.samples_dir, files[0]))

    results = {}
    for name in files:
        start = time.perf_counter()
        page = ocr.predict(os.path.join(args.samples_dir, name))[0]
        ms = (time.perf_counter() - start) * 1000

        texts = page["rec_texts"]
        scores = page["rec_scores"]
        polys = page["rec_polys"]
        if args.dump_boxes:
            for text, score, poly in zip(texts, scores, polys):
                print(name, f"{float(score):.2f}", [int(v) for v in poly[0]], repr(text))
        # Group boxes into lines by vertical center, then order each line
        # right-to-left if it contains Arabic, left-to-right otherwise.
        boxes = []
        for text, score, poly in zip(texts, scores, polys):
            ys = [p[1] for p in poly]
            xs = [p[0] for p in poly]
            boxes.append((sum(ys) / len(ys), min(xs), max(ys) - min(ys), text, float(score)))
        boxes.sort()
        lines, confidences = [], []
        current, current_y, current_h = [], None, None
        for cy, x, h, text, score in boxes:
            if current and abs(cy - current_y) > 0.5 * current_h:
                lines.append(current)
                current = []
            if not current:
                current_y, current_h = cy, max(h, 1)
            current.append((x, text, score))
        if current:
            lines.append(current)

        out_lines = []
        for line in lines:
            has_arabic = any("؀" <= ch <= "ۿ" for _, t, _ in line for ch in t)
            line.sort(key=lambda b: -b[0] if has_arabic else b[0])
            out_lines.append(" ".join(t for _, t, _ in line))
            confidences.append(min(s for _, _, s in line))
        results[name] = {"lines": out_lines, "confidences": confidences, "milliseconds": ms}

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"paddle ({args.det} + {args.rec}): {len(results)} images -> {args.out}")


if __name__ == "__main__":
    main()
