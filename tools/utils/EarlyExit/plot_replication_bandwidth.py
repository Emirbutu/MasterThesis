#!/usr/bin/env python3
"""Plot average bandwidth utilization across replication strategies.

The metric is actual bank-capacity utilization:

    utilization_percent = total_requests_served / (total_cycles * num_banks) * 100

That matches the intuition of "3000 requests over 6000 cycles on one bank =
50%" and rises when replication lets the scheduler use banks more often.
The result is averaged across Case 1 and Case 2.
"""

from __future__ import annotations

from pathlib import Path
import sys

# Ensure project root is on sys.path so package imports work when run as script
ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from tools.utils.EarlyExit.bandwidth_replication_model import compute_replication_statistics, estimate_memory_overhead
from tools.utils.EarlyExit.data_loader import EarlyExitDataLoader


TITLE_SIZE = 20
AXIS_LABEL_SIZE = 16
TICK_LABEL_SIZE = 14
ANNOTATION_SIZE = 13


def compute_bandwidth_utilization(stats: dict) -> dict[str, float]:
    """Compute actual aggregate bandwidth utilization per strategy.

    This is the fraction of all available bank slots that were used while
    processing the transition set.
    """
    out: dict[str, float] = {}
    for strat, data in stats.items():
        out[strat] = float(data["aggregate_bandwidth_utilization_percent"])
    return out


def main() -> None:
    base = Path("default")
    loader = EarlyExitDataLoader(base)

    # load both cases and compute stats per-case
    cases = [loader.load_case(1), loader.load_case(2)]
    strategies = ["1x", "2x_partial", "2x_full", "4x_full"]

    per_case_utils: list[dict[str, float]] = []

    for case in cases:
        stats = compute_replication_statistics(case, replication_strategies=strategies)
        per_case_utils.append(compute_bandwidth_utilization(stats))

    combined_utils = {
        strat: float(np.mean([case_utils[strat] for case_utils in per_case_utils]))
        for strat in strategies
    }

    # Plot bar chart of combined mean utilization
    labels = ["1x", "2x_partial", "2x_full", "4x_full"]
    vals = [combined_utils[s] for s in labels]

    fig, ax = plt.subplots(figsize=(8.0, 5.0), dpi=180)
    bars = ax.bar(labels, vals, color=["#d62728", "#ff7f0e", "#1f77b4", "#2ca02c"], alpha=0.9)

    ax.set_ylabel("Bandwidth utilization of bank capacity (%)", fontsize=AXIS_LABEL_SIZE)
    ax.set_xlabel("Replication strategy", fontsize=AXIS_LABEL_SIZE)
    ax.set_title("Average Bank Bandwidth Utilization Across Cases 1 and 2", fontsize=TITLE_SIZE)
    ax.set_ylim(0, min(100, max(vals) * 1.15 + 1))
    ax.grid(axis="y", alpha=0.25)
    ax.tick_params(axis="both", labelsize=TICK_LABEL_SIZE)

    for bar, s in zip(bars, labels):
        h = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2.0, h + 0.6, f"{h:.1f}%", ha="center", va="bottom", fontsize=ANNOTATION_SIZE)

    out = Path("tools/utils/EarlyExit/replication_bandwidth_avg.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out, bbox_inches="tight")
    fig.savefig(out.with_suffix(".pdf"), bbox_inches="tight")
    print(f"Wrote: {out}")


if __name__ == "__main__":
    main()
