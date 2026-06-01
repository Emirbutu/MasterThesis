#!/usr/bin/env python3
"""Generate a single averaged cycle-reduction plot for both default cases.

This script computes per-case cycle reductions relative to the 1x baseline,
averages the reductions across Case 1 and Case 2, and writes both the plot
and a short explanation report.
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

from tools.utils.EarlyExit.bandwidth_replication_model import compute_replication_statistics
from tools.utils.EarlyExit.data_loader import EarlyExitDataLoader


STRATEGIES = ["1x", "2x_partial", "2x_full", "4x_full"]
PLOT_STRATEGIES = ["2x_partial", "2x_full", "4x_full"]

TITLE_SIZE = 20
AXIS_LABEL_SIZE = 16
TICK_LABEL_SIZE = 14
ANNOTATION_SIZE = 13


def compute_average_reduction(loader: EarlyExitDataLoader) -> tuple[list[dict[str, float]], dict[str, float]]:
    per_case_reductions: list[dict[str, float]] = []

    for case_id in (1, 2):
        case = loader.load_case(case_id)
        stats = compute_replication_statistics(case, replication_strategies=STRATEGIES)
        baseline_cycles = float(stats["1x"]["total_cycles"])
        reductions = {}
        for strategy in STRATEGIES:
            cycles = float(stats[strategy]["total_cycles"])
            reductions[strategy] = 0.0 if baseline_cycles == 0 else 100.0 * (baseline_cycles - cycles) / baseline_cycles
        per_case_reductions.append(reductions)

    average_reduction = {
        strategy: float(np.mean([case_reduction[strategy] for case_reduction in per_case_reductions]))
        for strategy in STRATEGIES
    }
    return per_case_reductions, average_reduction


def write_explanation(out_path: Path, per_case_reductions: list[dict[str, float]], average_reduction: dict[str, float]) -> None:
    case1 = per_case_reductions[0]
    case2 = per_case_reductions[1]

    text = rf"""# Cycle-Reduction Analysis

## What this plot shows

This figure shows the **average cycle reduction relative to the 1x baseline** for the two default cases.
The values are averaged across Case 1 and Case 2 so the final plot reflects the shared replication trend,
not just one case.

## How the numbers were computed

For each case, we compared consecutive output spin vectors (`states_out`) and detected which spin positions changed.
For every transition:

1. Find the changed spin indices between the previous and current state.
2. Group those changed columns by memory bank using round-robin banking (`column % 4`).
3. Count cycles assuming each bank can provide at most one changed column per cycle.
4. Repeat the same count for each replication strategy (`1x`, `2x_partial`, `2x_full`, `4x_full`).

The cycle reduction for a strategy is:

$$
\\text{{reduction}}(\\%) = 100 \\times \\frac{{C_{{1x}} - C_{{strategy}}}}{{C_{{1x}}}}
$$

where $C_{{1x}}$ is the total cycle count for the baseline and $C_{{strategy}}$ is the total cycle count for the replication strategy.

## Why replication reduces cycles

Replication gives the scheduler more bank choices for each changed column.
That lets the scheduler spread the work across banks more evenly, so fewer cycles are needed to fetch all changed columns.

## Case results

The `1x` baseline is defined as zero reduction, so it is not shown in the plot.

- Case 1: `2x_partial = {case1['2x_partial']:.3f}%`, `2x_full = {case1['2x_full']:.3f}%`, `4x_full = {case1['4x_full']:.3f}%`
- Case 2: `2x_partial = {case2['2x_partial']:.3f}%`, `2x_full = {case2['2x_full']:.3f}%`, `4x_full = {case2['4x_full']:.3f}%`
- Average across both cases: `2x_partial = {average_reduction['2x_partial']:.3f}%`, `2x_full = {average_reduction['2x_full']:.3f}%`, `4x_full = {average_reduction['4x_full']:.3f}%`

## Files produced

- `generated_plots/cycle_reduction_average.png`
- `generated_reports/cycle_reduction_analysis.md`
"""

    out_path.write_text(text, encoding="utf-8")


def make_plot(average_reduction: dict[str, float], out_path: Path) -> None:
    labels = PLOT_STRATEGIES
    values = [average_reduction[strategy] for strategy in labels]
    colors = ["#ff7f0e", "#1f77b4", "#2ca02c"]

    fig, ax = plt.subplots(figsize=(8.8, 5.0), dpi=160)
    bars = ax.bar(labels, values, color=colors, alpha=0.95)
    ax.set_title("Average Cycle Reduction Across Cases 1 and 2", fontsize=TITLE_SIZE)
    ax.set_xlabel("Replication strategy", fontsize=AXIS_LABEL_SIZE)
    ax.set_ylabel("Cycle reduction vs 1x (%)", fontsize=AXIS_LABEL_SIZE)
    ax.set_ylim(0, max(8.0, max(values) * 1.2))
    ax.grid(axis="y", alpha=0.25)
    ax.tick_params(axis="both", labelsize=TICK_LABEL_SIZE)

    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            value + 0.3,
            f"{value:.3f}%",
            ha="center",
            va="bottom",
            fontsize=ANNOTATION_SIZE,
        )

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    fig.savefig(out_path.with_suffix(".pdf"), bbox_inches="tight")


def main() -> None:
    loader = EarlyExitDataLoader(ROOT / "default")
    per_case_reductions, average_reduction = compute_average_reduction(loader)

    plot_path = ROOT / "tools" / "utils" / "EarlyExit" / "generated_plots" / "cycle_reduction_average.png"
    report_path = ROOT / "tools" / "utils" / "EarlyExit" / "generated_reports" / "cycle_reduction_analysis.md"

    make_plot(average_reduction, plot_path)
    write_explanation(report_path, per_case_reductions, average_reduction)

    print(f"Wrote {plot_path}")
    print(f"Wrote {report_path}")


if __name__ == "__main__":
    main()
