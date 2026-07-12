from __future__ import annotations

import argparse
import csv
import random
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from common import parse_date
from data_source import ZipCsvDataSource


def main() -> None:
    ap = argparse.ArgumentParser(description="固定seedで検証用開催日をランダム抽出")
    ap.add_argument("--input-zip", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--count", type=int, default=5)
    ap.add_argument("--seed", type=int, default=20260711)
    ap.add_argument("--min-date", default="2023-01-01")
    ap.add_argument("--max-date", default="2026-07-09")
    ap.add_argument("--min-compi-rows", type=int, default=100)
    ap.add_argument("--min-venues", type=int, default=2)
    args = ap.parse_args()

    src = ZipCsvDataSource(args.input_zip)
    stats = src.available_compi_dates()
    dmin = parse_date(args.min_date); dmax = parse_date(args.max_date)
    eligible = sorted(d for d, s in stats.items() if dmin <= d <= dmax and s["rows"] >= args.min_compi_rows and len(s["venues"]) >= args.min_venues)
    if len(eligible) < args.count:
        raise SystemExit(f"eligible dates {len(eligible)} < requested {args.count}")
    chosen = sorted(random.Random(args.seed).sample(eligible, args.count))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["selected_date","seed","eligible_count","compi_rows","venues"])
        for d in chosen:
            s = stats[d]
            w.writerow([d.isoformat(), args.seed, len(eligible), s["rows"], ",".join(sorted(s["venues"]))])
    for d in chosen:
        print(d.isoformat())


if __name__ == "__main__":
    main()
