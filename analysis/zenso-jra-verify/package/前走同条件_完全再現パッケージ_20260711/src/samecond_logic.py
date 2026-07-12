from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from common import fmt_float, mean_or_none, relative_position
from data_source import Entry, HistoryRow, RaceKey


@dataclass
class HorseCalc:
    entry: Entry
    histories: list[HistoryRow]
    same: int = 0
    p1: Optional[float] = None
    p2: Optional[float] = None
    p3: Optional[float] = None
    p4: Optional[float] = None
    previous_time: Optional[float] = None
    previous_finish: Optional[int] = None
    previous_field: Optional[int] = None
    a3_3: Optional[float] = None
    a4_3: Optional[float] = None
    rr: Optional[float] = None
    waku_relative: Optional[float] = None
    in_m_raw: bool = False
    s1_pass: bool = False
    waku_pass: bool = False
    in_m_base: bool = False
    clock1: bool = False
    clock_tie: bool = False
    unique_clock1: bool = False
    adv_average_pass: Optional[bool] = None
    adv_last_pass: Optional[bool] = None
    hold_pass: Optional[bool] = None
    s_judgeable: bool = False
    final_rel: Optional[float] = None
    tier: str = ""
    subtype: str = ""
    horse_reason: str = ""


@dataclass
class RaceCalc:
    key: RaceKey
    distance: int
    field_size: int
    target_cell: bool
    race_reason: str
    same_count: int = 0
    same_rate: Optional[float] = None
    nm: int = 0
    m_raw: list[int] = field(default_factory=list)
    m_base: list[int] = field(default_factory=list)
    clock1_u: Optional[int] = None
    pick_u: Optional[int] = None
    tier: str = ""
    subtype: str = ""
    pick_reason: str = ""
    horses: list[HorseCalc] = field(default_factory=list)


def calculate_race(
    key: RaceKey,
    entries: list[Entry],
    histories: dict[tuple[str, str, int, int], list[HistoryRow]],
    cfg: dict[str, Any],
) -> RaceCalc:
    distance = entries[0].distance if entries else 0
    n = len(entries)
    cells = {(v, int(d)) for v, d in cfg["validated_cells"]}
    target_cell = (key.venue, distance) in cells
    result = RaceCalc(key=key, distance=distance, field_size=n, target_cell=target_cell, race_reason="")

    for e in entries:
        hs = histories.get(e.instance_key, [])[: int(cfg["history_runs"])]
        h = HorseCalc(entry=e, histories=hs)
        a3_values: list[Optional[float]] = []
        a4_values: list[Optional[float]] = []
        for idx, run in enumerate(hs):
            q3 = relative_position(run.c3, run.field_size)
            q4 = relative_position(run.c4, run.field_size)
            a3_values.append(q3)
            a4_values.append(q4)
            if idx == 0:
                h.same = int(run.venue == key.venue and run.distance == distance)
                h.p1 = relative_position(run.c1, run.field_size)
                h.p2 = relative_position(run.c2, run.field_size)
                h.p3 = q3
                h.p4 = q4
                h.previous_time = run.time_seconds
                h.previous_finish = run.finish
                h.previous_field = run.field_size
        h.a3_3 = mean_or_none(a3_values)
        h.a4_3 = mean_or_none(a4_values)
        h.waku_relative = ((e.horse_no - 1.0) / (n - 1.0)) if n > 1 else 0.5
        result.horses.append(h)

    if not target_cell:
        result.race_reason = "R_NOT_TARGET_CELL"
        _set_noneligible_reasons(result)
        return result
    if n < int(cfg["field_size_min"]):
        result.race_reason = "R_FIELD_LT_5"
        _set_noneligible_reasons(result)
        return result

    same_h = [h for h in result.horses if h.same == 1]
    result.same_count = len(same_h)
    result.same_rate = len(same_h) / n if n else 0.0
    if result.same_rate < float(cfg["same_rate_min"]):
        result.race_reason = "R_SAME_RATE_LOW"
        _set_noneligible_reasons(result)
        return result

    wm = sorted([h for h in same_h if h.a3_3 is not None], key=lambda h: (h.a3_3, h.entry.horse_no))
    result.nm = len(wm)
    if result.nm < int(cfg["nm_min"]):
        result.race_reason = "R_NM_LT_5"
        _set_noneligible_reasons(result)
        return result

    with_t = sorted(
        [h for h in same_h if h.previous_time is not None and h.previous_time > 0],
        key=lambda h: (h.previous_time, h.entry.horse_no),
    )
    if with_t:
        result.clock1_u = with_t[0].entry.horse_no
        min_time = with_t[0].previous_time
        tied = [h for h in with_t if h.previous_time == min_time]
        for h in tied:
            h.clock_tie = len(tied) > 1
        with_t[0].clock1 = True
        with_t[0].unique_clock1 = len(tied) == 1

    rr_min = float(cfg["middle_rr_min"])
    rr_max = float(cfg["middle_rr_max_exclusive"])
    s1_min = float(cfg["s1_min"])
    s1_max = float(cfg["s1_max"])
    waku_max = float(cfg["waku_max_exclusive"])

    for i, h in enumerate(wm):
        h.rr = (i + 0.5) / result.nm
        h.in_m_raw = rr_min <= h.rr < rr_max
        if h.in_m_raw:
            result.m_raw.append(h.entry.horse_no)
        if not h.in_m_raw:
            h.horse_reason = "M_NOT_A3_MIDDLE"
            continue
        if h.p1 is None or h.p2 is None or h.p3 is None:
            h.horse_reason = "M_S1_MISSING"
            continue
        h.s1_pass = all(s1_min <= p <= s1_max for p in (h.p1, h.p2, h.p3))
        if not h.s1_pass:
            h.horse_reason = "M_S1_FAIL"
            continue
        h.waku_pass = h.waku_relative is not None and h.waku_relative < waku_max
        if not h.waku_pass:
            h.horse_reason = "M_WAKU_OUTER"
            continue
        h.in_m_base = True
        h.horse_reason = "M_BASE"
        result.m_base.append(h.entry.horse_no)

    result.m_raw.sort()
    result.m_base.sort()
    if not result.m_base:
        result.race_reason = "M_NONE"
        result.pick_reason = "NO_MID_BASE"
        return result

    result.race_reason = "R_ELIGIBLE"
    if result.clock1_u is None:
        result.pick_reason = "NO_CLOCK_DATA"
        return result

    pick = next((h for h in result.horses if h.entry.horse_no == result.clock1_u), None)
    if pick is None or not pick.in_m_base:
        result.pick_reason = "CLOCK1_NOT_MID"
        return result

    result.pick_u = pick.entry.horse_no
    pick.tier = "A"
    result.tier = "A"

    required = [pick.a3_3, pick.a4_3, pick.p3, pick.p4, pick.previous_finish, pick.previous_field]
    pick.s_judgeable = all(x is not None for x in required) and bool(pick.previous_field and pick.previous_field > 1)
    if not pick.s_judgeable:
        pick.subtype = "A-U"
        pick.horse_reason = "PICK_A_UNKNOWN"
        result.subtype = "A-U"
        result.pick_reason = "PICK_A_UNKNOWN"
        return result

    pick.final_rel = (pick.previous_finish - 1.0) / (pick.previous_field - 1.0)
    pick.adv_average_pass = (pick.a3_3 - pick.a4_3) > 0
    pick.adv_last_pass = (pick.p3 - pick.p4) > 0
    pick.hold_pass = pick.final_rel < pick.p4
    if pick.adv_average_pass and pick.adv_last_pass and pick.hold_pass:
        pick.tier = "S"
        pick.subtype = "S"
        pick.horse_reason = "PICK_S"
        result.tier = "S"
        result.subtype = "S"
        result.pick_reason = "PICK_S"
    else:
        pick.subtype = "A-K"
        pick.horse_reason = "PICK_A_KNOWN"
        result.subtype = "A-K"
        result.pick_reason = "PICK_A_KNOWN"
    return result


def _set_noneligible_reasons(result: RaceCalc) -> None:
    for h in result.horses:
        h.horse_reason = "RACE_NOT_ELIGIBLE"


def race_summary_row(r: RaceCalc) -> dict[str, Any]:
    return {
        "date": r.key.day.isoformat(), "venue": r.key.venue, "race": r.key.race,
        "distance": r.distance, "field_size": r.field_size,
        "target_cell": int(r.target_cell), "race_reason": r.race_reason,
        "same_count": r.same_count, "same_rate": fmt_float(r.same_rate, 3), "nm": r.nm,
        "m_raw": ",".join(map(str, r.m_raw)), "m_base": ",".join(map(str, r.m_base)),
        "clock1_u": r.clock1_u or "", "pick_u": r.pick_u or "", "tier": r.tier,
        "subtype": r.subtype, "pick_reason": r.pick_reason,
    }


def horse_audit_rows(r: RaceCalc) -> list[dict[str, Any]]:
    rows = []
    for h in sorted(r.horses, key=lambda x: x.entry.horse_no):
        rows.append({
            "date": r.key.day.isoformat(), "venue": r.key.venue, "race": r.key.race,
            "distance": r.distance, "field_size": r.field_size,
            "horse_no": h.entry.horse_no, "horse_name": h.entry.horse_name,
            "lineage_id": h.entry.lineage_id,
            "history_count": len(h.histories), "same": h.same,
            "p1": fmt_float(h.p1), "p2": fmt_float(h.p2), "p3": fmt_float(h.p3), "p4": fmt_float(h.p4),
            "a3_3": fmt_float(h.a3_3), "a4_3": fmt_float(h.a4_3), "rr": fmt_float(h.rr),
            "waku_relative": fmt_float(h.waku_relative), "in_m_raw": int(h.in_m_raw),
            "s1_pass": int(h.s1_pass), "waku_pass": int(h.waku_pass), "in_m_base": int(h.in_m_base),
            "previous_time": fmt_float(h.previous_time, 3), "previous_finish": h.previous_finish or "",
            "previous_field": h.previous_field or "", "clock1": int(h.clock1),
            "clock_tie": int(h.clock_tie), "unique_clock1": int(h.unique_clock1),
            "final_rel": fmt_float(h.final_rel),
            "adv_average_pass": "" if h.adv_average_pass is None else int(h.adv_average_pass),
            "adv_last_pass": "" if h.adv_last_pass is None else int(h.adv_last_pass),
            "hold_pass": "" if h.hold_pass is None else int(h.hold_pass),
            "s_judgeable": int(h.s_judgeable), "tier": h.tier, "subtype": h.subtype,
            "horse_reason": h.horse_reason,
        })
    return rows
