#!/usr/bin/env python3
"""Scores OCR benchmark outputs against ground_truth.json.

Usage:
  python3 tool/ocr_benchmark/score.py <samples_dir> name=results.json [...]

Metrics, per engine and per degradation variant:

- Arabic / Latin CER: character error rate of each ground-truth line against
  its best-matching recognized line (Levenshtein distance / reference
  length), pooled over all lines of that script.
- Arabic CER, order-insensitive: the same after sorting each line's tokens,
  so a correctly read line emitted in visual rather than logical run order
  is not counted as misread.
- Field accuracy: fraction of key values found verbatim in the recognized
  text. "digits-normalized" also counts a value found once Arabic-Indic and
  Western digits are mapped to the same form — how the plugin's derived
  comparison values will see it (raw text itself is never rewritten).
- Median latency.

Before comparison both sides are normalized only in ways that carry no
meaning: Unicode NFC, bidirectional control characters removed, whitespace
collapsed, spacing around ':' removed, and dash variants unified.
"""

import json
import re
import statistics
import sys
import unicodedata
from collections import defaultdict

BIDI_CONTROLS = re.compile("[\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]")
ARABIC_LETTER = re.compile("[\u0621-\u064a]")
ARABIC_INDIC = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    text = BIDI_CONTROLS.sub("", text)
    text = re.sub("[\u2013\u2014]", "-", text)
    text = re.sub(r"\s*:\s*", ":", text)
    return re.sub(r"\s+", " ", text).strip()


def levenshtein(a: str, b: str) -> int:
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(
                min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb))
            )
        previous = current
    return previous[-1]


def token_sorted(text: str) -> str:
    """The line's tokens in sorted order, with ':' as a separator.

    Used for an order-insensitive CER that separates "misread characters"
    from "right characters, different run order" — the latter being how
    engines differ on mixed Arabic/digit lines (logical vs visual order).
    """
    return " ".join(sorted(text.replace(":", " ").split()))


def best_line_distance(reference: str, candidates: list[str]) -> int:
    if not candidates:
        return len(reference)
    return min(levenshtein(reference, c) for c in candidates)


def main() -> None:
    samples_dir = sys.argv[1]
    engines = [arg.split("=", 1) for arg in sys.argv[2:]]
    with open(f"{samples_dir}/ground_truth.json", encoding="utf-8") as f:
        cards = json.load(f)

    report = {}
    for engine_name, path in engines:
        with open(path, encoding="utf-8") as f:
            outputs = json.load(f)
        by_variant = defaultdict(
            lambda: {
                "err": defaultdict(int),
                "len": defaultdict(int),
                "fields": 0,
                "fields_found": 0,
                "fields_found_digits": 0,
                "per_field": defaultdict(lambda: [0, 0]),
                "ms": [],
            }
        )
        for name, result in outputs.items():
            card_id, variant = name[:-4].split("_", 1)
            card = next(c for c in cards if c["id"] == card_id)
            stats = by_variant[variant]
            stats["ms"].append(result["milliseconds"])
            recognized = [normalize(l) for l in result["lines"]]
            full_text = " ".join(recognized)
            # An Arabic-block value is only credited when read from a line that
            # contains Arabic: otherwise a Western-digit date would be "found"
            # in the English block's copy of the same date.
            arabic_text = " ".join(l for l in recognized if ARABIC_LETTER.search(l))

            for line in card["lines"]:
                if line["script"] in ("arabic", "latin"):
                    ref = normalize(line["text"])
                    stats["err"][line["script"]] += best_line_distance(ref, recognized)
                    stats["len"][line["script"]] += len(ref)
                    sorted_ref = token_sorted(ref)
                    stats["err"][line["script"] + "_unordered"] += best_line_distance(
                        sorted_ref, [token_sorted(r) for r in recognized]
                    )
                    stats["len"][line["script"] + "_unordered"] += len(sorted_ref)
                if line.get("field"):
                    value = normalize(line["value"])
                    haystack = arabic_text if line["script"] == "arabic" else full_text
                    stats["fields"] += 1
                    found = value in haystack
                    found_digits = value.translate(ARABIC_INDIC) in haystack.translate(
                        ARABIC_INDIC
                    )
                    if line["field"] == "dob_ar":
                        # Split by how the digits were printed: the engines
                        # differ sharply on Arabic-Indic digits.
                        indic = value != value.translate(ARABIC_INDIC)
                        key = "dob_ar_indic" if indic else "dob_ar_western"
                        stats["per_field"][key][0] += found_digits
                        stats["per_field"][key][1] += 1
                    stats["fields_found"] += found
                    stats["fields_found_digits"] += found_digits
                    stats["per_field"][line["field"]][0] += found_digits
                    stats["per_field"][line["field"]][1] += 1

        report[engine_name] = {
            variant: {
                "arabic_cer": s["err"]["arabic"] / s["len"]["arabic"],
                "arabic_cer_order_insensitive": s["err"]["arabic_unordered"]
                / s["len"]["arabic_unordered"],
                "latin_cer": s["err"]["latin"] / s["len"]["latin"],
                "field_accuracy": s["fields_found"] / s["fields"],
                "field_accuracy_digits_normalized": s["fields_found_digits"] / s["fields"],
                "per_field_digits_normalized": {
                    k: v[0] / v[1] for k, v in sorted(s["per_field"].items())
                },
                "median_ms": statistics.median(s["ms"]),
            }
            for variant, s in sorted(by_variant.items())
        }

    variants = sorted(next(iter(report.values())).keys())
    for metric, fmt in [
        ("arabic_cer", "{:6.1%}"),
        ("arabic_cer_order_insensitive", "{:6.1%}"),
        ("latin_cer", "{:6.1%}"),
        ("field_accuracy", "{:6.1%}"),
        ("field_accuracy_digits_normalized", "{:6.1%}"),
        ("median_ms", "{:6.0f}"),
    ]:
        print(f"\n## {metric}")
        print("| engine | " + " | ".join(variants) + " |")
        print("|---|" + "---|" * len(variants))
        for engine_name, per_variant in report.items():
            cells = [fmt.format(per_variant[v][metric]) for v in variants]
            print(f"| {engine_name} | " + " | ".join(cells) + " |")

    print("\n## per-field accuracy (digits normalized), all variants pooled")
    fields = sorted(next(iter(next(iter(report.values())).values()))["per_field_digits_normalized"])
    print("| engine | " + " | ".join(fields) + " |")
    print("|---|" + "---|" * len(fields))
    for engine_name, per_variant in report.items():
        cells = []
        for field in fields:
            values = [per_variant[v]["per_field_digits_normalized"][field] for v in variants]
            cells.append("{:6.1%}".format(sum(values) / len(values)))
        print(f"| {engine_name} | " + " | ".join(cells) + " |")

    with open(f"{samples_dir}/report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()
