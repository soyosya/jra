from __future__ import annotations

import argparse
import csv
from pathlib import Path

KEYS = ["date", "venue", "race"]
DEFAULT_FIELDS = [
    "main_u", "second_u", "third_u", "fourth_u", "tickets",
    "samecond_m_base", "samecond_pick_u", "samecond_tier", "samecond_subtype",
    "axis_alignment", "integration_action", "display_label", "samecond_reason",
]


def load(path: Path) -> dict[tuple[str, str, str], dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    return {(r.get("date", ""), r.get("venue", ""), r.get("race", "")): r for r in rows}


def main() -> None:
    ap = argparse.ArgumentParser(description="race_picks.csv同士をキー・列単位で比較")
    ap.add_argument("expected", type=Path)
    ap.add_argument("actual", type=Path)
    ap.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    args = ap.parse_args()
    fields = [x.strip() for x in args.fields.split(",") if x.strip()]
    e = load(args.expected); a = load(args.actual)
    differences = []
    for key in sorted(set(e) | set(a)):
        if key not in e:
            differences.append((key, "ROW", "<missing>", "actual-only")); continue
        if key not in a:
            differences.append((key, "ROW", "expected-only", "<missing>")); continue
        for field in fields:
            if e[key].get(field, "") != a[key].get(field, ""):
                differences.append((key, field, e[key].get(field, ""), a[key].get(field, "")))
    if differences:
        print(f"FAIL: {len(differences)} differences")
        for x in differences[:100]: print(x)
        raise SystemExit(1)
    print(f"PASS: {len(e)} races, {len(fields)} fields matched.")

if __name__ == "__main__":
    main()
