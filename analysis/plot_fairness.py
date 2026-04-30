#!/usr/bin/env python3
"""Per-flow throughput over time and Jain's index per pair, for Exp 3.

Jain's index for n flows: J = (sum x_i)^2 / (n * sum x_i^2).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
JSON_DIR = ROOT / "data" / "raw" / "exp3"
OUT = ROOT / "figures" / "exp3_fairness.png"
CSV_OUT = ROOT / "analysis" / "exp3_jain.csv"

PAIRS = [
    ("bbr",   "cubic"),
    ("bbr",   "bbr"),
    ("cubic", "cubic"),
]

CC_COLOR = {"bbr": "#1f77b4", "cubic": "#d62728", "reno": "#2ca02c"}


def load_intervals(path: Path) -> pd.DataFrame:
    d = json.loads(path.read_text())
    return pd.DataFrame([
        {"t": iv["streams"][0]["end"], "mbps": iv["streams"][0]["bits_per_second"] / 1e6}
        for iv in d["intervals"]
    ])


def jain(values: list[float]) -> float:
    n = len(values)
    s = sum(values)
    sq = sum(v * v for v in values)
    return (s * s) / (n * sq) if sq > 0 else float("nan")


def main() -> int:
    fig, axes = plt.subplots(len(PAIRS), 1, figsize=(11, 8), sharex=True)
    stats = []

    for ax, (cc_a, cc_b) in zip(axes, PAIRS):
        name = f"{cc_a}_vs_{cc_b}"
        path_a = JSON_DIR / f"{name}_A.json"
        path_b = JSON_DIR / f"{name}_B.json"
        if not path_a.exists() or not path_b.exists():
            print(f"skip {name}: missing json", file=sys.stderr)
            continue
        df_a = load_intervals(path_a)
        df_b = load_intervals(path_b)

        suffix_a, suffix_b = (" (A)", " (B)") if cc_a == cc_b else ("", "")
        ax.plot(df_a["t"], df_a["mbps"], color=CC_COLOR[cc_a],
                label=f"{cc_a.upper()}{suffix_a}", linewidth=1.4)
        ax.plot(df_b["t"], df_b["mbps"], color=CC_COLOR[cc_b],
                linestyle="--" if cc_a == cc_b else "-",
                label=f"{cc_b.upper()}{suffix_b}", linewidth=1.4, alpha=0.85)
        ax.axhline(50, color="gray", linestyle=":", linewidth=1, alpha=0.6, label="fair share (50 Mbps)")
        ax.set_ylim(0, 110)
        ax.set_ylabel("Mbps")
        ax.grid(True, alpha=0.3)
        ax.legend(loc="upper right", fontsize=9)

        # Skip first 5s (ramp-up).
        steady_a = df_a[df_a["t"] >= 5]["mbps"]
        steady_b = df_b[df_b["t"] >= 5]["mbps"]
        mean_a = steady_a.mean()
        mean_b = steady_b.mean()
        j = jain([mean_a, mean_b])
        ax.set_title(
            f"{cc_a.upper()} vs {cc_b.upper()}: "
            f"{mean_a:.1f} / {mean_b:.1f} Mbps   share_A={mean_a/(mean_a+mean_b):.2f}   Jain J={j:.3f}",
            fontsize=10,
        )
        stats.append({
            "pair": name,
            "mean_A_mbps": mean_a,
            "mean_B_mbps": mean_b,
            "share_A": mean_a / (mean_a + mean_b),
            "jain_index": j,
        })

    axes[-1].set_xlabel("time (s)")
    fig.suptitle("Exp 3: fairness (two competing flows, 100 Mbps / 40 ms RTT / 1000 pkt buffer)",
                 fontsize=12, y=1.0)
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
