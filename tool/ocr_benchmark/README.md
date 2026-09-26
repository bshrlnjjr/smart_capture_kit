# OCR benchmark (phase 6)

Scripts behind `doc/benchmarks/phase6-desktop-ocr.md`. Everything runs on a
Mac and uses only synthetic cards. No real document goes in, and generated
images are not committed.

```sh
OUT=/tmp/ocr_bench   # anywhere outside the repo

# 1. Synthetic cards + ground truth (20 cards x 6 variants)
swift tool/ocr_benchmark/generate_samples.swift $OUT/samples 20

# 2. Apple Vision (revision 3, .accurate, ar-SA + en-US); add "1" for language correction
swift tool/ocr_benchmark/run_vision.swift $OUT/samples $OUT/vision.json

# 3. Tesseract (brew install tesseract; models from github.com/tesseract-ocr/tessdata_fast)
python3 tool/ocr_benchmark/run_tesseract.py $OUT/samples $OUT/tess.json \
    --tessdata /path/to/tessdata_fast --langs ara+eng --psm 6

# 4. Score
python3 tool/ocr_benchmark/score.py $OUT/samples vision=$OUT/vision.json tess=$OUT/tess.json
```

The generator is deterministic (fixed seed), so the same command always
produces the same cards.

Measure latency with one engine at a time. Running engines in parallel
distorts the timings.
