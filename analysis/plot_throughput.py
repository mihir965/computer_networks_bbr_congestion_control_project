#!/usr/bin/env python3
"""Throughput vs buffer, faceted by (delay, bandwidth), one line per CC."""
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
CSV = ROOT / "analysis" / "exp1_results.csv"
OUT = ROOT / "figures" / "exp1_throughput.png"

CC_STYLE = {
    "bbr":   {"color": "#1f77b4", "marker": "o", "label": "BBR"},
    "cubic": {"color": "#d62728", "marker": "s", "label": "CUBIC"},
    "reno":  {"color": "#2ca02c", "marker": "^", "label": "RENO"},
}


def main() -> int:
    if not CSV.exists():
        print(f"no csv: {CSV}. run parse.py first.", file=sys.stderr)
        return 1

    df = pd.read_csv(CSV)
    delays = sorted(df["delay_ms"].unique())
    bws = sorted(df["bw_mbit"].unique())

    fig, axes = plt.subplots(
        len(delays), len(bws),
        figsize=(4 * len(bws), 3 * len(delays)),
        sharex=True, squeeze=False,
    )

    for r, delay in enumerate(delays):
        for c, bw in enumerate(bws):
            ax = axes[r][c]
            sub = df[(df["delay_ms"] == delay) & (df["bw_mbit"] == bw)]
            for cc, style in CC_STYLE.items():
                rows = sub[sub["cc"] == cc].sort_values("buf_pkt")
                if rows.empty:
                    continue
                ax.plot(rows["buf_pkt"], rows["throughput_mbps"], **style, linewidth=2, markersize=7)
            ax.axhline(bw, color="gray", linestyle="--", linewidth=1, alpha=0.5, label=f"{bw} Mbps cap")
            ax.set_xscale("log")
            ax.set_xticks(sorted(df["buf_pkt"].unique()))
            ax.set_xticklabels(sorted(df["buf_pkt"].unique()))
            ax.set_ylim(0, bw * 1.15)
            ax.set_title(f"{bw} Mbps, {delay}ms one-way (RTT={2*delay}ms)", fontsize=10)
            ax.grid(True, alpha=0.3)
            if r == len(delays) - 1:
                ax.set_xlabel("buffer (packets)")
            if c == 0:
                ax.set_ylabel("throughput (Mbps)")

    handles, labels = axes[0][0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=4, bbox_to_anchor=(0.5, 1.02), fontsize=10)
    fig.suptitle("Exp 1: Throughput vs buffer size, by (bandwidth, delay)", y=1.06, fontsize=12)
    fig.tight_layout()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, dpi=150, bbox_inches="tight")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
