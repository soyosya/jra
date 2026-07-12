from __future__ import annotations

import argparse
import csv
import io
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from common import parse_date
from data_source import COMPI, HISTORY, RACE_INFO, ZipCsvDataSource


def read_dates(path: Path) -> set:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return {parse_date(r["selected_date"]) for r in csv.DictReader(f)}


def write_member(zf: zipfile.ZipFile, name: str, rows: list[dict[str, str]], fields: list[str]) -> None:
    sio = io.StringIO(newline="")
    w = csv.DictWriter(sio, fieldnames=fields, extrasaction="ignore", lineterminator="\r\n", quoting=csv.QUOTE_ALL)
    w.writeheader(); w.writerows(rows)
    zf.writestr(name, "\ufeff" + sio.getvalue())


def main() -> None:
    ap = argparse.ArgumentParser(description="5日検証用の最小CSV ZIPを作成")
    ap.add_argument("--input-zip", required=True, type=Path)
    ap.add_argument("--dates-csv", required=True, type=Path)
    ap.add_argument("--output-zip", required=True, type=Path)
    args = ap.parse_args()
    dates = read_dates(args.dates_csv)
    src = ZipCsvDataSource(args.input_zip)
    races = src.load_entries(dates)
    _, selected_history = src.load_last_histories(races, max_runs=3, excluded_venue="帯広ば")

    race_rows = []
    race_fields = None
    for row in src.rows(RACE_INFO):
        if race_fields is None: race_fields = list(row.keys())
        try: d = parse_date(row.get("開催日", ""))
        except ValueError: continue
        if d in dates: race_rows.append(row)

    comp_rows = []
    comp_fields = None
    for row in src.rows(COMPI):
        if comp_fields is None: comp_fields = list(row.keys())
        try: d = parse_date(row.get("開催日", ""))
        except ValueError: continue
        if d in dates: comp_rows.append(row)

    hist_fields = list(selected_history[0].keys()) if selected_history else []
    selected_history.sort(key=lambda r: (r.get("開催日", ""), r.get("開催場所", ""), r.get("レース番号", ""), r.get("馬名", "")))
    args.output_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        write_member(zf, RACE_INFO, race_rows, race_fields or [])
        write_member(zf, COMPI, comp_rows, comp_fields or [])
        write_member(zf, HISTORY, selected_history, hist_fields)
    print(args.output_zip)


if __name__ == "__main__":
    main()
