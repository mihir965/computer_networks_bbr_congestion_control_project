#!/usr/bin/env python3
"""Parse iperf3 JSON outputs from data/raw/exp1/ into a CSV."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "exp1"
OUT = ROOT / "analysis" / "exp1_results.csv"

NAME_RE = re.compile(r"^([a-z]+)_(\d+)mbit_(\d+)ms_(\d+)p\.json$")


def parse_one(path: Path) -> dict | None:
    m = NAME_RE.match(path.name)
    if not m:
        print(f"skip (bad name): {path.name}", file=sys.stderr)
        return None
    cc, bw_mbit, delay_ms, buf_pkt = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))

    try:
        d = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        print(f"skip (bad json): {path.name}: {e}", file=sys.stderr)
        return None

    end = d.get("end", {})
    sum_recv = end.get("sum_received", {})
    sum_sent = end.get("sum_sent", {})
    streams = end.get("streams", [])
    sender_stats = streams[0].get("sender", {}) if streams else {}

    return {
        "cc": cc,
        "bw_mbit": bw_mbit,
        "delay_ms": delay_ms,
        "buf_pkt": buf_pkt,
        "throughput_mbps": sum_recv.get("bits_per_second", 0) / 1e6,
        "sender_mbps": sum_sent.get("bits_per_second", 0) / 1e6,
        "retransmits": sum_sent.get("retransmits", 0),
        "mean_rtt_ms": sender_stats.get("mean_rtt", 0) / 1000.0,
        "min_rtt_ms": sender_stats.get("min_rtt", 0) / 1000.0,
        "max_rtt_ms": sender_stats.get("max_rtt", 0) / 1000.0,
    }


def main() -> int:
    if not RAW.exists():
        print(f"no data dir: {RAW}", file=sys.stderr)
        return 1

    rows = [r for p in sorted(RAW.glob("*.json")) if (r := parse_one(p))]
    if not rows:
        print("no rows parsed", file=sys.stderr)
        return 1

    df = pd.DataFrame(rows)
    df["utilization"] = df["throughput_mbps"] / df["bw_mbit"]
    df = df.sort_values(["cc", "bw_mbit", "delay_ms", "buf_pkt"]).reset_index(drop=True)
    df.to_csv(OUT, index=False)
    print(f"wrote {len(df)} rows -> {OUT}")
    print(df.head(12).to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
