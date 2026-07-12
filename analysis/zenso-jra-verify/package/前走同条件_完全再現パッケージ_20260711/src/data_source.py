from __future__ import annotations

import csv
import heapq
import io
import zipfile
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterator, Optional

from common import parse_date, to_float, to_int


RACE_INFO = "レース情報.csv"
COMPI = "コンピ指数.csv"
HISTORY = "vw_競走結果統合.csv"


@dataclass(frozen=True)
class RaceKey:
    day: date
    venue: str
    race: int


@dataclass
class Entry:
    key: RaceKey
    horse_no: int
    horse_name: str
    lineage_id: str
    distance: int
    start_time: str = ""
    race_name: str = ""

    @property
    def instance_key(self) -> tuple[str, str, int, int]:
        return (self.key.day.isoformat(), self.key.venue, self.key.race, self.horse_no)


@dataclass
class HistoryRow:
    day: date
    venue: str
    race: int
    distance: int
    finish: int
    time_seconds: Optional[float]
    field_size: int
    c1: Optional[float]
    c2: Optional[float]
    c3: Optional[float]
    c4: Optional[float]
    horse_name: str
    lineage_id: str
    raw: dict[str, str] = field(default_factory=dict)


class ZipCsvDataSource:
    def __init__(self, zip_path: Path):
        self.zip_path = Path(zip_path)
        if not self.zip_path.exists():
            raise FileNotFoundError(self.zip_path)

    def rows(self, member: str) -> Iterator[dict[str, str]]:
        with zipfile.ZipFile(self.zip_path) as zf:
            if member not in zf.namelist():
                raise KeyError(f"ZIP member not found: {member}")
            with zf.open(member) as raw:
                text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
                yield from csv.DictReader(text)

    def available_compi_dates(self) -> dict[date, dict[str, Any]]:
        result: dict[date, dict[str, Any]] = {}
        for row in self.rows(COMPI):
            try:
                d = parse_date(row.get("開催日", ""))
            except ValueError:
                continue
            item = result.setdefault(d, {"rows": 0, "venues": set()})
            item["rows"] += 1
            item["venues"].add(row.get("開催場所", ""))
        return result

    def load_entries(self, target_dates: set[date]) -> dict[RaceKey, list[Entry]]:
        races: dict[RaceKey, list[Entry]] = defaultdict(list)
        for row in self.rows(RACE_INFO):
            try:
                d = parse_date(row.get("開催日", ""))
            except ValueError:
                continue
            if d not in target_dates:
                continue
            venue = (row.get("開催場所") or "").strip()
            race = to_int(row.get("レース番号"))
            u = to_int(row.get("馬番"))
            dist = to_int(row.get("距離"))
            name = (row.get("馬名") or "").strip()
            if not venue or race is None or u is None or dist is None or not name:
                continue
            key = RaceKey(d, venue, race)
            races[key].append(Entry(
                key=key,
                horse_no=u,
                horse_name=name,
                lineage_id=(row.get("血統登録番号") or "").strip(),
                distance=dist,
                start_time=(row.get("発走時刻") or "").strip(),
                race_name=(row.get("競走名") or "").strip(),
            ))
        for entries in races.values():
            entries.sort(key=lambda e: e.horse_no)
        return dict(races)

    def load_compi(self, target_dates: set[date]) -> dict[RaceKey, list[dict[str, Any]]]:
        # 同一馬の指数は取得スナップショットが複数存在するため、取得日時が最新の1行だけを採用する。
        latest: dict[tuple[RaceKey, int], tuple[str, int, dict[str, Any]]] = {}
        for row in self.rows(COMPI):
            try:
                d = parse_date(row.get("開催日", ""))
            except ValueError:
                continue
            if d not in target_dates:
                continue
            venue = (row.get("開催場所") or "").strip()
            race = to_int(row.get("レース番号"))
            u = to_int(row.get("馬番"))
            if not venue or race is None or u is None:
                continue
            key = RaceKey(d, venue, race)
            acquired = (row.get("取得日時") or "").strip()
            row_id = to_int(row.get("Id")) or 0
            item = {
                "horse_no": u,
                "horse_name": (row.get("馬名") or "").strip(),
                "index": to_float(row.get("指数")),
                "rank": to_int(row.get("指数順位")),
                "field_size": to_int(row.get("頭数")),
                "acquired_at": acquired,
            }
            k = (key, u)
            prior = latest.get(k)
            if prior is None or (acquired, row_id) > (prior[0], prior[1]):
                latest[k] = (acquired, row_id, item)
        result: dict[RaceKey, list[dict[str, Any]]] = defaultdict(list)
        for (key, _), (_, __, item) in latest.items():
            result[key].append(item)
        for rows in result.values():
            rows.sort(key=lambda r: (
                r["rank"] if r["rank"] is not None and r["rank"] > 0 else 10**9,
                -(r["index"] if r["index"] is not None else -10**9),
                r["horse_no"],
            ))
        return dict(result)

    def load_last_histories(
        self,
        races: dict[RaceKey, list[Entry]],
        max_runs: int = 3,
        excluded_venue: str = "帯広ば",
    ) -> tuple[dict[tuple[str, str, int, int], list[HistoryRow]], list[dict[str, str]]]:
        targets_by_name: dict[str, list[Entry]] = defaultdict(list)
        for entries in races.values():
            for e in entries:
                targets_by_name[e.horse_name].append(e)

        heaps: dict[tuple[str, str, int, int], list[tuple[int, int, int, HistoryRow]]] = defaultdict(list)
        selected_raw: dict[tuple, dict[str, str]] = {}
        seq = 0
        for row in self.rows(HISTORY):
            name = (row.get("馬名") or "").strip()
            target_entries = targets_by_name.get(name)
            if not target_entries:
                continue
            venue = (row.get("開催場所") or "").strip()
            if venue == excluded_venue:
                continue
            finish = to_int(row.get("着順"))
            if finish is None or finish <= 0:
                continue
            try:
                hday = parse_date(row.get("開催日", ""))
            except ValueError:
                continue
            race = to_int(row.get("レース番号")) or 0
            dist = to_int(row.get("距離")) or 0
            n = to_int(row.get("頭数")) or 0
            hist_lineage = (row.get("血統登録番号") or "").strip()
            hist = HistoryRow(
                day=hday,
                venue=venue,
                race=race,
                distance=dist,
                finish=finish,
                time_seconds=to_float(row.get("走破時計")),
                field_size=n,
                c1=to_float(row.get("一コーナー")),
                c2=to_float(row.get("二コーナー")),
                c3=to_float(row.get("三コーナー")),
                c4=to_float(row.get("四コーナー")),
                horse_name=name,
                lineage_id=hist_lineage,
                raw=dict(row),
            )
            ordinal = hday.toordinal()
            for target in target_entries:
                if hday >= target.key.day:
                    continue
                if target.lineage_id and hist_lineage and target.lineage_id != hist_lineage:
                    continue
                ikey = target.instance_key
                seq += 1
                item = (ordinal, race, seq, hist)
                heap = heaps[ikey]
                if len(heap) < max_runs:
                    heapq.heappush(heap, item)
                elif item[:2] > heap[0][:2]:
                    heapq.heapreplace(heap, item)

        histories: dict[tuple[str, str, int, int], list[HistoryRow]] = {}
        for ikey, heap in heaps.items():
            rows = [x[3] for x in sorted(heap, key=lambda x: (x[0], x[1], x[2]), reverse=True)]
            histories[ikey] = rows
            for h in rows:
                raw_key = (
                    h.day.isoformat(), h.venue, h.race, h.horse_name, h.lineage_id,
                    h.finish, h.field_size, h.c1, h.c2, h.c3, h.c4, h.time_seconds,
                )
                selected_raw[raw_key] = h.raw
        return histories, list(selected_raw.values())
