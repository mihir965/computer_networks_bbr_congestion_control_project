#!/usr/bin/env python3
"""RTT and throughput time-series for Exp 2, plus inflation table."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
JSON_DIR = ROOT / "data" / "raw" / "exp2"
OUT = ROOT / "figures" / "exp2_rtt.png"
CSV_OUT = ROOT / "analysis" / "exp2_inflation.csv"

CCS = ["bbr", "cubic", "reno"]
COLORS = {"bbr": "#1f77b4", "cubic": "#d62728", "reno": "#2ca02c"}


def load_intervals(cc: str) -> pd.DataFrame:
    path = JSON_DIR / f"iperf_{cc}.json"
    d = json.loads(path.read_text())
    rows = []
    for iv in d["intervals"]:
        s = iv["streams"][0]
        rows.append({
            "t_end": s["end"],
            "rtt_ms": s["rtt"] / 1000.0,
            "throughput_mbps": s["bits_per_second"] / 1e6,
        })
    return pd.DataFrame(rows)


def main() -> int:
    fig, (ax_rtt, ax_thr) = plt.subplots(
        2, 1, figsize=(11, 7), sharex=True,
        gridspec_kw={"height_ratios": [2, 1]},
    )
    stats = []

    for cc in CCS:
        path = JSON_DIR / f"iperf_{cc}.json"
        if not path.exists():
            print(f"skip {cc}: no json", file=sys.stderr)
            continue
        df = load_intervals(cc)

        ax_rtt.plot(df["t_end"], df["rtt_ms"], color=COLORS[cc],
                    label=cc.upper(), linewidth=1.2, alpha=0.9)
        ax_thr.plot(df["t_end"], df["throughput_mbps"], color=COLORS[cc],
                    label=cc.upper(), linewidth=1.2, alpha=0.9)

        stats.append({
            "cc": cc.upper(),
            "samples": len(df),
            "min_rtt_ms": df["rtt_ms"].min(),
            "mean_rtt_ms": df["rtt_ms"].mean(),
            "p99_rtt_ms": df["rtt_ms"].quantile(0.99),
            "max_rtt_ms": df["rtt_ms"].max(),
            "inflation": df["rtt_ms"].mean() / df["rtt_ms"].min(),
            "mean_thr_mbps": df["throughput_mbps"].mean(),
        })

    ax_rtt.axhline(40, color="black", linestyle="--", linewidth=1,
                   alpha=0.5, label="propagation RTT (40 ms)")
    ax_rtt.set_ylabel("TCP smoothed RTT (ms)")
    ax_rtt.set_title("Exp 2: RTT and throughput under sustained load (100 Mbps, 40 ms RTT, 1000 pkt buffer)")
    ax_rtt.legend(loc="upper right")
    ax_rtt.grid(True, alpha=0.3)

    ax_thr.axhline(100, color="gray", linestyle="--", linewidth=1, alpha=0.5, label="bottleneck (100 Mbps)")
    ax_thr.set_xlabel("time (s)")
    ax_thr.set_ylabel("throughput (Mbps)")
    ax_thr.set_ylim(0, 110)
    ax_thr.grid(True, alpha=0.3)

    fig.tight_layout()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, dpi=150, bbox_inches="tight")
    print(f"wrote {OUT}")

    if stats:
        df_stats = pd.DataFrame(stats)
        df_stats.to_csv(CSV_OUT, index=False)
        print()
        print(df_stats.to_string(index=False))
        print(f"\nwrote {CSV_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
