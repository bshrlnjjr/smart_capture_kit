#!/usr/bin/env python3
"""Runs the Tesseract CLI over every PNG in a directory for the phase 6 OCR
benchmark, writing the same JSON shape as run_vision.swift.

Usage:
  python3 tool/ocr_benchmark/run_tesseract.py <samples_dir> <out.json> \
      --tessdata <dir> [--langs ara+eng] [--psm 6] [--tesseract PATH]

Desktop Tesseract 5 is a proxy for the Android path (flutter_tesseract_ocr,
which wraps Tesseract 5 via tesseract4android): same LSTM engine and same
traineddata, but a different build and CPU, so accuracy should carry over
and latency will not.
"""

import argparse
import json
import os
import subprocess
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("samples_dir")
    parser.add_argument("out")
    parser.add_argument("--tessdata", required=True)
    parser.add_argument("--langs", default="ara+eng")
    parser.add_argument("--psm", default="6")
    parser.add_argument("--tesseract", default="tesseract")
    args = parser.parse_args()

    results = {}
    files = sorted(f for f in os.listdir(args.samples_dir) if f.endswith(".png"))
    for name in files:
        start = time.perf_counter()
        proc = subprocess.run(
            [
                args.tesseract,
                os.path.join(args.samples_dir, name),
                "stdout",
                "--tessdata-dir",
                args.tessdata,
                "-l",
                args.langs,
                "--psm",
                args.psm,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        ms = (time.perf_counter() - start) * 1000
        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        results[name] = {"lines": lines, "confidences": [], "milliseconds": ms}

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"tesseract ({args.langs}, psm {args.psm}): {len(results)} images -> {args.out}")


if __name__ == "__main__":
    main()
