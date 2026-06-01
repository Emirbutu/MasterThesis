#!/usr/bin/env python3
# Copyright 2026 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Plot cycle-trace CSV logs.

The plot auto-detects either:
- spin-energy logs with `test_id` and `cycle` columns, or
- iteration-cycle reports with `transition_idx`, `cycles_1x`, and
  `lower_bound_cycles` columns.

In both cases it plots per-iteration cycles, a no-overhead approximation,
and cumulative totals.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass, replace
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np


TITLE_SIZE = 21
AXIS_LABEL_SIZE = 17
TICK_LABEL_SIZE = 15
LEGEND_SIZE = 14
PANEL_TITLE_SIZE = 18


@dataclass(frozen=True)
class SpinEnergySeries:
    label: str
    iterations: np.ndarray
    cycles: np.ndarray
    cycles_without_overhead: np.ndarray
    cumulative_cycles: np.ndarray
    cumulative_without_overhead: np.ndarray


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Plot spin-energy CSV traces")
    parser.add_argument(
        "csv_files",
        nargs="+",
        type=Path,
        help="One or more spin_energy_log CSV files",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("spin_energy_cycles_plot.png"),
        help="Output image path",
    )
    parser.add_argument("--title", default="Iteration Cycles and Cumulative Cycles", help="Figure title")
    parser.add_argument(
        "--vertical",
        action="store_true",
        help="Use a taller, vertical layout instead of wide horizontal layout",
    )
    parser.add_argument(
        "--legend-position",
        choices=["top", "bottom", "right", "left", "none"],
        default="bottom",
        help="Place a single legend outside the plot (default: bottom)",
    )
    parser.add_argument("--dpi", type=int, default=180, help="Figure DPI")
    return parser.parse_args()


def load_series(csv_path: Path) -> SpinEnergySeries:
    if not csv_path.is_file():
        raise FileNotFoundError(f"CSV file not found: {csv_path}")

    with csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = set(reader.fieldnames or [])

        if {"test_id", "cycle"}.issubset(fieldnames):
            rows: list[tuple[int, float, float]] = []
            for row in reader:
                test_id = int(row["test_id"])
                cycle = float(row["cycle"])
                rows.append((test_id, cycle, max(cycle - 5.0, 0.0)))
        elif {"transition_idx", "cycles_1x", "lower_bound_cycles"}.issubset(fieldnames):
            rows = []
            for row in reader:
                transition_idx = int(row["transition_idx"])
                cycle = float(row["cycles_1x"])
                no_overhead = float(row["lower_bound_cycles"])
                rows.append((transition_idx, cycle, no_overhead))
        else:
            raise ValueError(
                f"{csv_path} must contain either test_id/cycle or transition_idx/cycles_1x/lower_bound_cycles columns"
            )

    if not rows:
        raise ValueError(f"{csv_path} has no data rows")

    rows.sort(key=lambda item: item[0])
    iterations = np.asarray([item[0] for item in rows], dtype=np.int64)
    cycles = np.asarray([item[1] for item in rows], dtype=np.float64)
    cycles_without_overhead = np.asarray([item[2] for item in rows], dtype=np.float64)
    cumulative_cycles = np.cumsum(cycles)
    cumulative_without_overhead = np.cumsum(cycles_without_overhead)

    return SpinEnergySeries(
        label=csv_path.stem,
        iterations=iterations,
        cycles=cycles,
        cycles_without_overhead=cycles_without_overhead,
        cumulative_cycles=cumulative_cycles,
        cumulative_without_overhead=cumulative_without_overhead,
    )


def plot_series(
    series_list: list[SpinEnergySeries],
    output_path: Path,
    title: str,
    dpi: int,
    vertical: bool = False,
    legend_position: str = "bottom",
) -> None:
    if not series_list:
        raise ValueError("No CSV series to plot")

    if len(series_list) != 2:
        raise ValueError("This plot layout expects exactly two cases")

    if vertical:
        fig_width = 10.0
        fig_height = 11.0
    else:
        fig_width = 14.0
        fig_height = 8.8

    fig, axes = plt.subplots(
        2,
        2,
        sharex="col",
        figsize=(fig_width, fig_height),
        dpi=dpi,
        constrained_layout=True,
    )

    # collect a single representative handle per unique label
    handle_map: dict[str, matplotlib.lines.Line2D] = {}

    def draw_iteration_panel(axis: plt.Axes, series: SpinEnergySeries) -> None:
        left_line = axis.plot(
            series.iterations,
            series.cycles,
            color="#1f77b4",
            linewidth=1.4,
            marker="o",
            markersize=2.5,
            label="Cycles per iteration",
        )
        overhead_free_line = axis.plot(
            series.iterations,
            series.cycles_without_overhead,
            color="#9467bd",
            linewidth=1.5,
            linestyle=":",
            label="Cycles per iteration without control overhead",
        )
        baseline_y = np.full_like(series.iterations, 64.0, dtype=np.float64)
        baseline_line = axis.plot(
            series.iterations,
            baseline_y,
            color="black",
            linewidth=1.2,
            linestyle="--",
            label="Baseline: 64 cycles/iteration",
        )

        axis.set_ylabel("Cycles / iteration")
        axis.grid(True, alpha=0.28)
        axis.set_xlim(-0.5, series.iterations.max() + 0.5)
        axis.set_title(f"{series.label} - Iteration Cycles", fontsize=PANEL_TITLE_SIZE)
        axis.tick_params(axis="both", labelsize=TICK_LABEL_SIZE)

        # place a compact legend inside the panel
        axis.legend(loc="upper right", fontsize=LEGEND_SIZE)

    def draw_cumulative_panel(axis: plt.Axes, series: SpinEnergySeries) -> None:
        right_line = axis.plot(
            series.iterations,
            series.cumulative_cycles,
            color="#d62728",
            linewidth=1.7,
            label="Cumulative cycles",
        )
        no_overhead_line = axis.plot(
            series.iterations,
            series.cumulative_without_overhead,
            color="#2ca02c",
            linewidth=1.7,
            linestyle="--",
            label="Cumulative cycles without control overhead",
        )
        baseline_cumulative = 64.0 * (np.arange(series.iterations.shape[0]) + 1.0)
        baseline_cum_line = axis.plot(
            series.iterations,
            baseline_cumulative,
            color="black",
            linewidth=1.2,
            linestyle="-",
            label="Baseline cumulative (64 * iterations)",
        )

        axis.set_ylabel("Cumulative cycles")
        axis.grid(True, alpha=0.28)
        axis.set_xlim(-0.5, series.iterations.max() + 0.5)
        axis.set_title(f"{series.label} - Cumulative Cycles", fontsize=PANEL_TITLE_SIZE)
        axis.tick_params(axis="both", labelsize=TICK_LABEL_SIZE)

        # place a compact legend inside the panel
        axis.legend(loc="upper left", fontsize=LEGEND_SIZE)

    draw_iteration_panel(axes[0, 0], series_list[0])
    draw_cumulative_panel(axes[0, 1], series_list[0])
    draw_iteration_panel(axes[1, 0], series_list[1])
    draw_cumulative_panel(axes[1, 1], series_list[1])

    axes[1, 0].set_xlabel("Iterations")
    axes[1, 1].set_xlabel("Iterations")
    axes[0, 0].tick_params(labelbottom=False)
    axes[0, 1].tick_params(labelbottom=False)

    fig.suptitle(title, fontsize=TITLE_SIZE)
    for axis in axes.flat:
        axis.set_xlabel(axis.get_xlabel(), fontsize=AXIS_LABEL_SIZE)
        axis.set_ylabel(axis.get_ylabel(), fontsize=AXIS_LABEL_SIZE)
    if legend_position != "none" and handle_map:
        handles = list(handle_map.values())
        labels = list(handle_map.keys())
        if legend_position == "top":
            fig.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, 1.02), ncol=max(2, len(handles)), fontsize=LEGEND_SIZE)
        elif legend_position == "bottom":
            fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(0.5, -0.02), ncol=max(2, len(handles)), fontsize=LEGEND_SIZE)
        elif legend_position == "right":
            fig.legend(handles, labels, loc="center right", bbox_to_anchor=(1.02, 0.5), fontsize=LEGEND_SIZE)
        elif legend_position == "left":
            fig.legend(handles, labels, loc="center left", bbox_to_anchor=(-0.02, 0.5), fontsize=LEGEND_SIZE)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, bbox_inches="tight")
    fig.savefig(output_path.with_suffix(".pdf"), bbox_inches="tight")


def main() -> None:
    args = parse_args()
    series_list = [replace(load_series(csv_path), label=f"Case {index + 1}") for index, csv_path in enumerate(args.csv_files)]
    plot_series(series_list, args.output, args.title, args.dpi, args.vertical, args.legend_position)
    print(f"Wrote plot to {args.output}")


if __name__ == "__main__":
    main()