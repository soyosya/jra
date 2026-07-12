from __future__ import annotations

import copy
import sys
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from common import load_json
from data_source import Entry, HistoryRow, RaceKey
from samecond_logic import calculate_race


def history(day: date, venue: str, race: int, distance: int, finish: int, t: float | None,
            n: int, c1: float | None, c2: float | None, c3: float | None, c4: float | None,
            name: str) -> HistoryRow:
    return HistoryRow(day, venue, race, distance, finish, t, n, c1, c2, c3, c4, name, "", {})


def make_case() -> tuple[RaceKey, list[Entry], dict, dict]:
    cfg = load_json(HERE.parent / "config" / "samecond_v3.json")
    d = date(2026, 1, 10); key = RaceKey(d, "園田", 1)
    entries = [Entry(key, u, f"馬{u}", "", 1400) for u in range(1, 7)]
    histories = {}
    # a3の順序は u1,u2,u3,u4,u5,u6。中位1/3はu3,u4。
    c3_ranks = [2, 3, 4, 5, 6, 7]
    for e, c3 in zip(entries, c3_ranks):
        # 前走S1は全馬0.30～0.70内。u3だけ時計最速かつADV/HOLD通過。
        prev_c3 = 5 if e.horse_no in (3, 4) else c3
        prev_c4 = 3 if e.horse_no == 3 else prev_c3
        finish = 2 if e.horse_no == 3 else prev_c4
        pt = 80.0 if e.horse_no == 3 else 90.0 + e.horse_no
        runs = [
            history(d-timedelta(days=10), "園田", 1, 1400, finish, pt, 10, 4, 5, prev_c3, prev_c4, e.horse_name),
            history(d-timedelta(days=20), "園田", 2, 1400, 4, 95+e.horse_no, 10, 4, 5, c3, max(1,c3-1) if e.horse_no==3 else c3, e.horse_name),
            history(d-timedelta(days=30), "園田", 3, 1400, 4, 96+e.horse_no, 10, 4, 5, c3, max(1,c3-1) if e.horse_no==3 else c3, e.horse_name),
        ]
        histories[e.instance_key] = runs
    return key, entries, histories, cfg


def assert_eq(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected={expected!r}, actual={actual!r}")


def main() -> None:
    key, entries, histories, cfg = make_case()
    r = calculate_race(key, entries, histories, cfg)
    assert_eq(r.m_base, [3, 4], "T-base M_base")
    assert_eq(r.clock1_u, 3, "T-clock1")
    assert_eq((r.pick_u, r.tier, r.subtype), (3, "S", "S"), "T-S strict passes")

    # HOLD同値は不通過。
    h2 = copy.deepcopy(histories)
    p = h2[entries[2].instance_key][0]
    p.finish = p.c4  # 同一頭数なので final_rel == p4
    r2 = calculate_race(key, entries, h2, cfg)
    assert_eq((r2.pick_u, r2.tier, r2.subtype), (3, "A", "A-K"), "T-HOLD equality fails")

    # 前走4角欠損はA-U。欠損補完・除外をしない。
    h3 = copy.deepcopy(histories)
    h3[entries[2].instance_key][0].c4 = None
    r3 = calculate_race(key, entries, h3, cfg)
    assert_eq((r3.pick_u, r3.tier, r3.subtype), (3, "A", "A-U"), "T-missing is A-U")

    # 時計1位がM_base外なら繰り上げなし。
    h4 = copy.deepcopy(histories)
    h4[entries[0].instance_key][0].time_seconds = 70.0
    r4 = calculate_race(key, entries, h4, cfg)
    assert_eq((r4.clock1_u, r4.pick_u, r4.pick_reason), (1, None, "CLOCK1_NOT_MID"), "T-no rollover")

    # 時計同率は馬番小を採用。
    h5 = copy.deepcopy(histories)
    h5[entries[3].instance_key][0].time_seconds = 80.0
    r5 = calculate_race(key, entries, h5, cfg)
    assert_eq(r5.clock1_u, 3, "T-clock tie lower horse number")

    # waku=0.80は不通過（N=6, u=5）。u5を中位へ移して確認。
    h6 = copy.deepcopy(histories)
    # u5のa3をu3相当、u3を後方へ。時計1位もu5。
    for run in h6[entries[4].instance_key]: run.c3 = 4
    for run in h6[entries[2].instance_key]: run.c3 = 8
    h6[entries[4].instance_key][0].time_seconds = 60.0
    r6 = calculate_race(key, entries, h6, cfg)
    u5 = next(h for h in r6.horses if h.entry.horse_no == 5)
    assert_eq((round(u5.waku_relative, 6), u5.in_m_base), (0.8, False), "T-waku strict")

    print("PASS: 6 synthetic acceptance cases")


if __name__ == "__main__":
    main()
