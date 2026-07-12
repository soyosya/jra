from __future__ import annotations

from typing import Any, Optional

from data_source import Entry, RaceKey
from samecond_logic import RaceCalc


ROLES = ["main", "second", "third", "fourth"]
MARK_LABELS = {"main": "◎", "second": "○", "third": "▲", "fourth": "△"}


def generate_reference_row(
    key: RaceKey,
    entries: list[Entry],
    compi_rows: list[dict[str, Any]],
    mid: RaceCalc,
    buy_cfg: dict[str, Any],
) -> dict[str, Any]:
    current_by_u = {e.horse_no: e for e in entries}
    ranked = [r for r in compi_rows if r["horse_no"] in current_by_u]
    role_map: dict[str, Optional[dict[str, Any]]] = {role: None for role in ROLES}
    for role, row in zip(ROLES, ranked[:4]):
        role_map[role] = row

    main_u = role_map["main"]["horse_no"] if role_map["main"] else None
    alignment = "NONE"
    action = "NO_CHANGE"
    display_label = "通常候補"
    if mid.pick_u is not None:
        alignment = "SAME" if mid.pick_u == main_u else "OTHER"
        if alignment == "SAME" and mid.tier == "S":
            action = "UPGRADE_LABEL_ONLY"
            display_label = "確度おすすめ候補"
        elif alignment == "SAME" and mid.tier == "A":
            action = "ADD_A_MATCH_NOTE_ONLY"
            display_label = "前走同条件A一致候補"
        elif alignment == "OTHER" and mid.tier == "S":
            action = "REVIEW_ONLY_NO_AUTO_CHANGE"
            display_label = "前走同条件S別軸・要確認"
        elif alignment == "OTHER" and mid.tier == "A":
            action = "NOTE_ONLY_NO_AUTO_CHANGE"
            display_label = "前走同条件A別馬・参考"

    ticket_strings: list[str] = []
    for spec in buy_cfg["tickets"]:
        selected = [role_map[role] for role in spec["roles"]]
        if any(x is None for x in selected):
            continue
        nums = [int(x["horse_no"]) for x in selected]
        if len(set(nums)) != len(nums):
            continue
        ticket_strings.append(f"{spec['ticket_type']} " + "-".join(map(str, nums)))

    pick_name = current_by_u[mid.pick_u].horse_name if mid.pick_u in current_by_u else ""
    result: dict[str, Any] = {
        "date": key.day.isoformat(), "venue": key.venue, "race": key.race,
        "start_time": entries[0].start_time if entries else "",
        "race_name": entries[0].race_name if entries else "", "distance": mid.distance,
        "field_size": len(entries),
    }
    for role in ROLES:
        row = role_map[role]
        result[f"{role}_mark"] = MARK_LABELS[role] if row else ""
        result[f"{role}_u"] = row["horse_no"] if row else ""
        result[f"{role}_name"] = current_by_u[row["horse_no"]].horse_name if row else ""
        result[f"{role}_index"] = int(row["index"]) if row and row["index"] is not None and float(row["index"]).is_integer() else (row["index"] if row else "")
    result.update({
        "tickets": " / ".join(ticket_strings),
        "samecond_m_base": ",".join(map(str, mid.m_base)),
        "samecond_pick_u": mid.pick_u or "", "samecond_pick_name": pick_name,
        "samecond_tier": mid.tier, "samecond_subtype": mid.subtype,
        "axis_alignment": alignment, "integration_action": action,
        "display_label": display_label,
        "purchase_status": "候補表示のみ（オッズ・EV未使用）",
        "samecond_reason": mid.pick_reason or mid.race_reason,
    })
    return result
