#!/usr/bin/env python3
"""Merges an Arabic-recognizer pass and a Latin-recognizer pass over the same
detected lines into one result, for the phase 6 OCR benchmark.

Usage:
  python3 tool/ocr_benchmark/merge_passes.py arabic.json latin.json out.json

Models the "one detection, two recognizers" design: both passes must come
from the same detector on the same images (run_paddle.py with a different
--rec), so their lines correspond one to one. Per line:

- a line with Arabic keeps the Arabic pass's text, plus every token from the
  Latin pass that contains a digit (the Arabic recognizer was measured
  silently dropping digit runs from mixed lines);
- a line without Arabic takes the Latin pass's text.

When the two passes disagree on line count the image keeps the Arabic pass
unchanged, rather than guessing an alignment.
"""

import json
import re
import sys

ARABIC = re.compile("[؀-ۿ]")
DIGIT = re.compile("[0-9٠-٩۰-۹]")


def main() -> None:
    arabic_path, latin_path, out_path = sys.argv[1:4]
    with open(arabic_path, encoding="utf-8") as f:
        arabic = json.load(f)
    with open(latin_path, encoding="utf-8") as f:
        latin = json.load(f)

    merged, misaligned = {}, 0
    for name, ar in arabic.items():
        la = latin.get(name)
        if la is None or len(la["lines"]) != len(ar["lines"]):
            misaligned += 1
            merged[name] = ar
            continue
        lines = []
        for ar_line, la_line in zip(ar["lines"], la["lines"]):
            if ARABIC.search(ar_line):
                digits = [t for t in la_line.split() if DIGIT.search(t)]
                lines.append(" ".join([ar_line, *digits]))
            else:
                lines.append(la_line)
        merged[name] = {
            "lines": lines,
            "confidences": [],
            "milliseconds": ar["milliseconds"] + la["milliseconds"],
        }

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"merged {len(merged)} images ({misaligned} kept Arabic-only: line counts differed)")


if __name__ == "__main__":
    main()
