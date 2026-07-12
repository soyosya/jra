from __future__ import annotations

import csv
import hashlib
import json
import math
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional


def parse_date(value: str) -> date:
    value = (value or "").strip()
    if not value:
        raise ValueError("empty date")
    token = value.split()[0]
    token = token.replace("/", "-")
    return datetime.strptime(token, "%Y-%m-%d").date()


def date_text(value: date) -> str:
    return value.strftime("%Y-%m-%d")


def to_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return None


def to_float(value: Any) -> Optional[float]:
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        x = float(s)
    except (ValueError, TypeError):
        return None
    return x if math.isfinite(x) else None


def relative_position(rank: Any, field_size: Any) -> Optional[float]:
    r = to_float(rank)
    n = to_float(field_size)
    if r is None or n is None or n <= 1 or r <= 0:
        return None
    return (r - 1.0) / (n - 1.0)


def mean_or_none(values: Iterable[Optional[float]]) -> Optional[float]:
    xs = [x for x in values if x is not None]
    return sum(xs) / len(xs) if xs else None


def fmt_float(value: Optional[float], digits: int = 6) -> str:
    if value is None:
        return ""
    text = f"{value:.{digits}f}"
    return text.rstrip("0").rstrip(".") if "." in text else text


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in fieldnames})


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(value, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
