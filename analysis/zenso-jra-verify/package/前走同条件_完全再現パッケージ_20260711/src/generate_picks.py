from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from common import load_json, parse_date, write_csv, write_json
from data_source import ZipCsvDataSource
from samecond_logic import calculate_race, horse_audit_rows, race_summary_row
from reference_buy import generate_reference_row


RACE_FIELDS = [
    "date","venue","race","start_time","race_name","distance","field_size",
    "main_mark","main_u","main_name","main_index",
    "second_mark","second_u","second_name","second_index",
    "third_mark","third_u","third_name","third_index",
    "fourth_mark","fourth_u","fourth_name","fourth_index",
    "tickets","samecond_m_base","samecond_pick_u","samecond_pick_name","samecond_tier","samecond_subtype",
    "axis_alignment","integration_action","display_label","purchase_status","samecond_reason",
]
SUMMARY_FIELDS = [
    "date","venue","race","distance","field_size","target_cell","race_reason","same_count",
    "same_rate","nm","m_raw","m_base","clock1_u","pick_u","tier","subtype","pick_reason",
]
AUDIT_FIELDS = [
    "date","venue","race","distance","field_size","horse_no","horse_name","lineage_id",
    "history_count","same","p1","p2","p3","p4","a3_3","a4_3","rr","waku_relative",
    "in_m_raw","s1_pass","waku_pass","in_m_base","previous_time","previous_finish","previous_field",
    "clock1","clock_tie","unique_clock1","final_rel","adv_average_pass","adv_last_pass","hold_pass",
    "s_judgeable","tier","subtype","horse_reason",
]


def generate(input_zip: Path, dates: list[str], output_dir: Path, logic_config: Path, buy_config: Path) -> None:
    target_dates = {parse_date(d) for d in dates}
    logic_cfg = load_json(logic_config)
    buy_cfg = load_json(buy_config)
    source = ZipCsvDataSource(input_zip)
    races = source.load_entries(target_dates)
    compi = source.load_compi(target_dates)
    histories, _ = source.load_last_histories(
        races, max_runs=int(logic_cfg["history_runs"]), excluded_venue=logic_cfg["exclude_history_venue"]
    )

    by_date: dict[str, dict[str, list]] = {}
    for key in sorted(races, key=lambda k: (k.day, k.venue, k.race)):
        entries = races[key]
        mid = calculate_race(key, entries, histories, logic_cfg)
        pick = generate_reference_row(key, entries, compi.get(key, []), mid, buy_cfg)
        bucket = by_date.setdefault(key.day.isoformat(), {"picks": [], "summary": [], "audit": []})
        bucket["picks"].append(pick)
        bucket["summary"].append(race_summary_row(mid))
        bucket["audit"].extend(horse_audit_rows(mid))

    for d in sorted(target_dates):
        ds = d.isoformat()
        dest = output_dir / ds
        bucket = by_date.get(ds, {"picks": [], "summary": [], "audit": []})
        write_csv(dest / "race_picks.csv", bucket["picks"], RACE_FIELDS)
        write_csv(dest / "samecond_race_summary.csv", bucket["summary"], SUMMARY_FIELDS)
        write_csv(dest / "samecond_horse_audit.csv", bucket["audit"], AUDIT_FIELDS)
        recs = [r for r in bucket["picks"] if r["display_label"] in {"確度おすすめ候補", "前走同条件A一致候補"}]
        recs.sort(key=lambda r: (0 if r["samecond_tier"] == "S" else 1, r["venue"], r["race"]))
        write_csv(dest / "recommendations.csv", recs, RACE_FIELDS)
        write_json(dest / "picks.json", {
            "date": ds,
            "logic": {"name": logic_cfg["logic_name"], "display_name": logic_cfg.get("logic_display_name", "前走同条件"), "version": logic_cfg["logic_version"]},
            "buy_logic": {"name": buy_cfg["buy_logic_name"], "version": buy_cfg["buy_logic_version"]},
            "odds_used": False,
            "purchase_mode": "candidate-display-only",
            "races": bucket["picks"],
        })

    write_json(output_dir / "run_metadata.json", {
        "input_zip_name": input_zip.name,
        "dates": sorted(d.isoformat() for d in target_dates),
        "logic_name": logic_cfg["logic_name"], "logic_display_name": logic_cfg.get("logic_display_name", "前走同条件"), "logic_version": logic_cfg["logic_version"],
        "buy_logic_name": buy_cfg["buy_logic_name"], "buy_logic_version": buy_cfg["buy_logic_version"],
        "odds_used": False,
        "note": "Generated tickets are reference candidates only; not purchase recommendations.",
    })


def main() -> None:
    ap = argparse.ArgumentParser(description="前走同条件＋参考買目をCSV ZIPから決定的に生成")
    ap.add_argument("--input-zip", required=True, type=Path)
    ap.add_argument("--date", action="append", required=True, help="YYYY-MM-DD; repeatable")
    ap.add_argument("--output-dir", required=True, type=Path)
    ap.add_argument("--logic-config", type=Path, default=HERE.parent / "config" / "samecond_v3.json")
    ap.add_argument("--buy-config", type=Path, default=HERE.parent / "config" / "reference_buy_v1.json")
    args = ap.parse_args()
    generate(args.input_zip, args.date, args.output_dir, args.logic_config, args.buy_config)


if __name__ == "__main__":
    main()
