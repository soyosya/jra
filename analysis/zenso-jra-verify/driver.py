import sys, csv, io, zipfile
from pathlib import Path
from datetime import date

PKG = Path(r"C:\jra\analysis\zenso-jra-verify\package\前走同条件_完全再現パッケージ_20260711\src")
sys.path.insert(0, str(PKG))
from common import load_json, parse_date
from data_source import ZipCsvDataSource
from samecond_logic import calculate_race

ZIP = Path(r"C:\jra\analysis\zenso-jra-verify\jra_input.zip")
CFG = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\jra\analysis\zenso-jra-verify\jra_csv\samecond_jra.json")
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"C:\jra\analysis\zenso-jra-verify\jra_picks.csv")

cfg = load_json(CFG)
src = ZipCsvDataSource(ZIP)

# all target dates from entries CSV
dates = set()
with zipfile.ZipFile(ZIP) as zf:
    with zf.open("レース情報.csv") as raw:
        for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")):
            try:
                dates.add(parse_date(row["開催日"]))
            except Exception:
                pass
print("target dates:", len(dates))

races = src.load_entries(dates)
print("races:", len(races))
histories, _ = src.load_last_histories(races, max_runs=int(cfg["history_runs"]), excluded_venue=cfg["exclude_history_venue"])
print("history keys:", len(histories))

rows = []
for key in sorted(races, key=lambda k: (k.day, k.venue, k.race)):
    r = calculate_race(key, races[key], histories, cfg)
    rows.append({
        "date": key.day.isoformat(), "venue": key.venue, "race": key.race,
        "distance": r.distance, "field_size": r.field_size,
        "same_rate": (round(r.same_rate,4) if r.same_rate is not None else ""),
        "nm": r.nm, "race_reason": r.race_reason,
        "tier": r.tier, "subtype": r.subtype, "pick_u": (r.pick_u or ""),
        "clock1_u": (r.clock1_u or ""), "m_base_n": len(r.m_base), "pick_reason": r.pick_reason,
    })

with OUT.open("w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

# quick summary
from collections import Counter
tc = Counter(x["tier"] for x in rows)
elig = [x for x in rows if x["race_reason"]=="R_ELIGIBLE"]
picks = [x for x in rows if x["tier"] in ("S","A")]
print("total races:", len(rows))
print("tier counts:", dict(tc))
print("R_ELIGIBLE:", len(elig), " picks(S/A):", len(picks),
      " S:", sum(1 for x in picks if x['tier']=='S'), " A:", sum(1 for x in picks if x['tier']=='A'))
print("wrote", OUT)
