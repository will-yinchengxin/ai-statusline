#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_SESSIONS_DIR = Path.home() / ".codex" / "sessions"


@dataclass
class WindowSnapshot:
    used_percent: float | None
    window_minutes: int | None
    resets_at: int | None


@dataclass
class RateLimitSnapshot:
    ts: str | None
    plan_type: str | None
    reached_type: str | None
    primary: WindowSnapshot | None
    secondary: WindowSnapshot | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read the latest Codex rate-limit snapshot and print reset countdowns."
    )
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=DEFAULT_SESSIONS_DIR,
        help=f"Codex sessions directory (default: {DEFAULT_SESSIONS_DIR})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the latest rate-limit snapshot as JSON.",
    )
    parser.add_argument(
        "--short",
        action="store_true",
        help="Print a compact one-line countdown summary.",
    )
    return parser.parse_args()


def load_latest_snapshot(sessions_dir: Path) -> RateLimitSnapshot:
    latest_payload: dict[str, Any] | None = None
    latest_ts: str | None = None

    for path in sorted(sessions_dir.rglob("rollout-*.jsonl")):
        try:
            with path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    payload = entry.get("payload")
                    if not isinstance(payload, dict):
                        continue
                    if payload.get("type") != "token_count":
                        continue
                    rate_limits = payload.get("rate_limits")
                    if not isinstance(rate_limits, dict):
                        continue
                    ts = entry.get("timestamp")
                    if latest_ts is None or (isinstance(ts, str) and ts > latest_ts):
                        latest_ts = ts if isinstance(ts, str) else latest_ts
                        latest_payload = rate_limits
        except OSError:
            continue

    if latest_payload is None:
        raise SystemExit(f"No rate-limit snapshot found under {sessions_dir}")

    return RateLimitSnapshot(
        ts=latest_ts,
        plan_type=_as_str(latest_payload.get("plan_type")),
        reached_type=_as_str(latest_payload.get("rate_limit_reached_type")),
        primary=_parse_window(latest_payload.get("primary")),
        secondary=_parse_window(latest_payload.get("secondary")),
    )


def _parse_window(value: Any) -> WindowSnapshot | None:
    if not isinstance(value, dict):
        return None
    return WindowSnapshot(
        used_percent=_as_float(value.get("used_percent")),
        window_minutes=_as_int(value.get("window_minutes")),
        resets_at=_as_int(value.get("resets_at")),
    )


def _as_str(value: Any) -> str | None:
    return value if isinstance(value, str) else None


def _as_int(value: Any) -> int | None:
    return value if isinstance(value, int) else None


def _as_float(value: Any) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    return None


def format_duration(seconds: int) -> str:
    if seconds <= 0:
        return "now"

    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)

    parts: list[str] = []
    if days:
        parts.append(f"{days}d")
    if hours or days:
        parts.append(f"{hours}h")
    parts.append(f"{minutes}m")
    return "".join(parts)


def describe_window(label: str, window: WindowSnapshot | None, now_ts: int) -> str:
    if window is None:
        return f"{label}: unavailable"

    used = "?" if window.used_percent is None else f"{window.used_percent:.0f}%"
    if window.resets_at is None:
        return f"{label}: {used} used, reset unavailable"

    remaining = max(0, window.resets_at - now_ts)
    reset_time = datetime.fromtimestamp(window.resets_at).astimezone()
    return (
        f"{label}: {used} used, {format_duration(remaining)} refresh "
        f"({reset_time:%m-%d %H:%M})"
    )


def short_window(label: str, window: WindowSnapshot | None, now_ts: int) -> str:
    if window is None or window.resets_at is None:
        return f"{label} unavailable"
    remaining = max(0, window.resets_at - now_ts)
    used = "?" if window.used_percent is None else f"{window.used_percent:.0f}%"
    return f"{label} {used} {format_duration(remaining)} refresh"


def main() -> None:
    args = parse_args()
    snapshot = load_latest_snapshot(args.sessions_dir)
    now = datetime.now().astimezone()
    now_ts = int(now.timestamp())

    if args.json:
        payload = {
            "timestamp": snapshot.ts,
            "plan_type": snapshot.plan_type,
            "rate_limit_reached_type": snapshot.reached_type,
            "primary": snapshot.primary.__dict__ if snapshot.primary else None,
            "secondary": snapshot.secondary.__dict__ if snapshot.secondary else None,
            "generated_at": now.isoformat(),
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    if args.short:
        print(
            " | ".join(
                [
                    short_window("5h", snapshot.primary, now_ts),
                    short_window("7d", snapshot.secondary, now_ts),
                ]
            )
        )
        return

    print(f"snapshot: {snapshot.ts or 'unknown'}")
    if snapshot.plan_type:
        print(f"plan: {snapshot.plan_type}")
    if snapshot.reached_type:
        print(f"limit reached: {snapshot.reached_type}")
    print(describe_window("5h window", snapshot.primary, now_ts))
    print(describe_window("7d window", snapshot.secondary, now_ts))


if __name__ == "__main__":
    main()
