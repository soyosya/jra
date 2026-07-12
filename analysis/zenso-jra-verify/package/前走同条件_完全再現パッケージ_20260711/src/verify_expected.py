from __future__ import annotations

import argparse
import filecmp
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


FILES = ["race_picks.csv", "samecond_race_summary.csv", "samecond_horse_audit.csv", "recommendations.csv", "picks.json"]


def main() -> None:
    ap = argparse.ArgumentParser(description="fixture再生成結果とexpectedをバイト比較")
    ap.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = ap.parse_args()
    root = args.package_root.resolve()
    dates_csv = root / "validation" / "selected_dates.csv"
    dates = []
    import csv
    with dates_csv.open("r", encoding="utf-8-sig", newline="") as f:
        dates = [r["selected_date"] for r in csv.DictReader(f)]
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "actual"
        cmd = [sys.executable, str(root / "src" / "generate_picks.py"), "--input-zip", str(root / "validation" / "fixture" / "地方競馬_csv_export_前走同条件_検証5日.zip"), "--output-dir", str(out)]
        for d in dates:
            cmd.extend(["--date", d])
        subprocess.run(cmd, check=True)
        failures = []
        for d in dates:
            for name in FILES:
                exp = root / "validation" / "expected" / d / name
                act = out / d / name
                if not exp.exists() or not act.exists() or not filecmp.cmp(exp, act, shallow=False):
                    failures.append(f"{d}/{name}")
        if failures:
            print("MISMATCH:")
            for x in failures: print(" -", x)
            raise SystemExit(1)
        print(f"PASS: {len(dates)} dates, {len(dates)*len(FILES)} files matched byte-for-byte.")


if __name__ == "__main__":
    main()
