#!/usr/bin/env python3
"""Regenerate a single averaged cycle-reduction plot for replication strategies.

Produces: tools/utils/EarlyExit/generated_plots/memory_replication_analysis.png
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from tools.utils.EarlyExit.data_loader import EarlyExitDataLoader
from tools.utils.EarlyExit.bandwidth_replication_model import compute_replication_statistics


def main():
    loader = EarlyExitDataLoader(Path("default"))
    strategies = ["1x", "2x_partial", "2x_full", "4x_full"]

    reductions_per_case = []
    for cid in (1, 2):
        case = loader.load_case(cid)
        stats = compute_replication_statistics(case, replication_strategies=strategies)
        baseline = stats["1x"]["mean_cycles"]
        reductions = []
        for s in strategies:
            meanc = stats[s]["mean_cycles"]
            red = 100.0 * (baseline - meanc) / baseline if baseline > 0 else 0.0
            reductions.append(red)
        reductions_per_case.append(reductions)

    avg_reduction = np.mean(np.asarray(reductions_per_case), axis=0)

    labels = ["1x", "2x_partial", "2x_full", "4x_full"]
    colors = ["#d62728", "#ff7f0e", "#1f77b4", "#2ca02c"]

    fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
    bars = ax.bar(labels, avg_reduction, color=colors, alpha=0.95)
    ax.set_ylabel("Cycle reduction vs 1x (%)")
    ax.set_xlabel("Replication strategy")
    ax.set_title("Average Cycle Reduction (Case 1 & 2)")
    ax.grid(axis="y", alpha=0.25)
    ax.set_ylim(0, max(10.0, float(np.max(avg_reduction)) * 1.15))

    for bar, val in zip(bars, avg_reduction):
        ax.text(bar.get_x() + bar.get_width() / 2, val + 0.5, f"{val:.1f}%", ha="center", va="bottom")

    out = Path("tools/utils/EarlyExit/generated_plots/memory_replication_analysis.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    print("Wrote:", out)


if __name__ == "__main__":
    main()
