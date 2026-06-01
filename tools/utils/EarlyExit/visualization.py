"""Visualization helpers for early-exit datasets."""

from __future__ import annotations

from pathlib import Path
from collections.abc import Mapping, Sequence

import matplotlib.pyplot as plt
import numpy as np

from .data_loader import EarlyExitCaseData
from .energy_calc import compute_case_percentage_stop_accuracy, compute_case_wrong_decision_rate


def plot_matrix_image(
    matrix: np.ndarray,
    title: str = "Matrix",
    cmap: str = "coolwarm",
    figsize: tuple[float, float] = (12.0, 10.0),
    dpi: int = 150,
    vmin: float | None = None,
    vmax: float | None = None,
    annotate: bool = False,
    annotate_format: str = "d",
    max_annotated_cells: int = 4096,
    force_annotate: bool = False,
    show_grid: bool = False,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot a matrix as a heatmap and optionally write each value in each cell.

    For large matrices (for example 256x256), annotating every cell is visually
    dense and slow. By default, annotation is skipped above max_annotated_cells
    unless force_annotate is True.
    """

    arr = np.asarray(matrix)
    if arr.ndim != 2:
        raise ValueError("matrix must be 2-dimensional")

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    im = ax.imshow(arr, cmap=cmap, vmin=vmin, vmax=vmax, interpolation="nearest")
    ax.set_title(title)
    ax.set_xlabel("Column")
    ax.set_ylabel("Row")
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)

    if show_grid:
        ax.set_xticks(np.arange(-0.5, arr.shape[1], 1), minor=True)
        ax.set_yticks(np.arange(-0.5, arr.shape[0], 1), minor=True)
        ax.grid(which="minor", color="black", linestyle="-", linewidth=0.1, alpha=0.2)
        ax.tick_params(which="minor", bottom=False, left=False)

    cell_count = arr.shape[0] * arr.shape[1]
    do_annotate = annotate and (force_annotate or cell_count <= max_annotated_cells)

    if do_annotate:
        fontsize = 3 if cell_count > 10000 else 5
        for r in range(arr.shape[0]):
            for c in range(arr.shape[1]):
                ax.text(
                    c,
                    r,
                    format(arr[r, c], annotate_format),
                    ha="center",
                    va="center",
                    fontsize=fontsize,
                    color="black",
                )

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_j_matrix(
    case_data: EarlyExitCaseData,
    output_path: str | Path | None = None,
    annotate: bool = False,
    force_annotate: bool = False,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot the 256x256 J matrix from a loaded case."""

    return plot_matrix_image(
        matrix=case_data.j_matrix_nibble,
        title=f"Case {case_data.case_id} J Matrix",
        cmap="coolwarm",
        vmin=-8,
        vmax=7,
        annotate=annotate,
        annotate_format="d",
        max_annotated_cells=4096,
        force_annotate=force_annotate,
        show_grid=False,
        output_path=output_path,
        show=show,
    )


def plot_matrix_window_with_values(
    matrix: np.ndarray,
    row_start: int,
    row_end: int,
    col_start: int,
    col_end: int,
    title: str = "Matrix Window",
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot a sub-window with per-cell values shown for easier inspection."""

    arr = np.asarray(matrix)
    window = arr[row_start:row_end, col_start:col_end]

    return plot_matrix_image(
        matrix=window,
        title=title,
        cmap="coolwarm",
        annotate=True,
        annotate_format="d",
        max_annotated_cells=10_000,
        force_annotate=True,
        show_grid=True,
        output_path=output_path,
        show=show,
    )


def plot_energy_trace(
    trace: Mapping[str, object] | np.ndarray,
    title: str = "Energy Trace",
    figsize: tuple[float, float] = (12.0, 6.0),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, tuple[plt.Axes, plt.Axes]]:
    """Plot energy after each iteration cycle.

    Args:
        trace: Either a trace dict returned by compute_case_energy_trace or a
            1D array-like of energy values.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional file path for saving the figure.
        show: Whether to call plt.show().

    Returns:
        Figure and a pair of axes (energy axis, delta axis).
    """
    if isinstance(trace, Mapping):
        energies = np.asarray(trace["energies"], dtype=np.float64)
        deltas = np.asarray(trace.get("deltas", np.zeros_like(energies)), dtype=np.float64)
    else:
        energies = np.asarray(trace, dtype=np.float64)
        deltas = np.diff(energies, prepend=energies[0])

    if energies.ndim != 1:
        raise ValueError(f"energy trace must be 1D, got shape {energies.shape}")

    cycles = np.arange(energies.shape[0])
    fig, (ax_energy, ax_delta) = plt.subplots(
        2,
        1,
        sharex=True,
        figsize=figsize,
        dpi=dpi,
        gridspec_kw={"height_ratios": [3, 1]},
    )

    ax_energy.plot(cycles, energies, color="#1f77b4", linewidth=1.5)
    ax_energy.set_title(title)
    ax_energy.set_ylabel("Energy")
    ax_energy.grid(True, alpha=0.3)

    ax_delta.plot(cycles, deltas, color="#d62728", linewidth=1.0)
    ax_delta.axhline(0.0, color="black", linewidth=0.8, alpha=0.4)
    ax_delta.set_xlabel("Iteration cycle")
    ax_delta.set_ylabel("Delta")
    ax_delta.grid(True, alpha=0.3)

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, (ax_energy, ax_delta)


def plot_sigma_cycle_trace(
    sigma_trace: Mapping[str, object],
    title: str = "Single-Sigma Fetch-Cycle Energy",
    figsize: tuple[float, float] = (11.0, 5.0),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, tuple[plt.Axes, plt.Axes]]:
    """Plot energy and delta after each internal fetch cycle for one sigma.

    Args:
        sigma_trace: Dictionary returned by compute_sigma_delta_cycle_trace or
            compute_case_single_sigma_cycle_trace.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional output image path.
        show: Whether to call plt.show().

    Returns:
        Figure and a pair of axes (energy axis, delta axis).
    """
    energies = np.asarray(sigma_trace["cycle_energies"], dtype=np.float64)
    deltas = np.asarray(sigma_trace["cycle_deltas"], dtype=np.float64)
    if energies.ndim != 1:
        raise ValueError(f"cycle_energies must be 1D, got shape {energies.shape}")
    if deltas.shape != energies.shape:
        raise ValueError(
            f"cycle_deltas must have same shape as cycle_energies, got {deltas.shape} and {energies.shape}"
        )

    cycles = np.arange(energies.shape[0])
    fig, (ax_energy, ax_delta) = plt.subplots(
        2,
        1,
        sharex=True,
        figsize=figsize,
        dpi=dpi,
        gridspec_kw={"height_ratios": [3, 1]},
    )

    ax_energy.step(cycles, energies, where="post", color="#1f77b4", linewidth=1.5)
    ax_energy.set_title(title)
    ax_energy.set_ylabel("Energy")
    ax_energy.grid(True, alpha=0.3)

    ax_delta.bar(cycles, deltas, color="#ff7f0e", width=0.8)
    ax_delta.axhline(0.0, color="black", linewidth=0.8, alpha=0.4)
    ax_delta.set_xlabel("Fetch cycle (4-column batch)")
    ax_delta.set_ylabel("Delta")
    ax_delta.grid(True, alpha=0.3)

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, (ax_energy, ax_delta)


def plot_early_stop_accuracy(
    accuracy: Mapping[str, object],
    title: str = "Early-Stop Accuracy Drop",
    figsize: tuple[float, float] = (10.0, 5.5),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot accuracy drop versus fetch-cycle budget.

    Args:
        accuracy: Dictionary from compute_case_early_stop_accuracy.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional output image path.
        show: Whether to call plt.show().

    Returns:
        Figure and axis.
    """
    cycle_budget = np.asarray(accuracy["cycle_budget"], dtype=np.float64)
    mae = np.asarray(accuracy["mae"], dtype=np.float64)
    rmse = np.asarray(accuracy["rmse"], dtype=np.float64)
    max_abs_error = np.asarray(accuracy["max_abs_error"], dtype=np.float64)

    if cycle_budget.ndim != 1:
        raise ValueError(f"cycle_budget must be 1D, got shape {cycle_budget.shape}")

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    ax.plot(cycle_budget, mae, label="MAE", linewidth=1.6, color="#1f77b4")
    ax.plot(cycle_budget, rmse, label="RMSE", linewidth=1.6, color="#ff7f0e")
    ax.plot(cycle_budget, max_abs_error, label="Max Abs Error", linewidth=1.6, color="#d62728")

    ax.set_title(title)
    ax.set_xlabel("Fetch-cycle budget (4-column cycles)")
    ax.set_ylabel("Energy error")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="upper right")

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_transition_cycle_counts(
    counts: Mapping[str, object],
    title: str = "Cycles per Iteration",
    figsize: tuple[float, float] = (12.0, 5.5),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot how many internal fetch cycles each transition needs.

    Args:
        counts: Dictionary returned by compute_case_transition_cycle_counts.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional output image path.
        show: Whether to call plt.show().

    Returns:
        Figure and axis.
    """
    transition_index = np.asarray(counts["transition_index"], dtype=np.int64)
    cycle_count = np.asarray(counts["cycle_count"], dtype=np.int64)
    changed_bits = np.asarray(counts["changed_bits"], dtype=np.int64)

    if transition_index.ndim != 1:
        raise ValueError(f"transition_index must be 1D, got shape {transition_index.shape}")
    if cycle_count.shape != transition_index.shape:
        raise ValueError(
            f"cycle_count must match transition_index shape, got {cycle_count.shape} and {transition_index.shape}"
        )

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    ax.bar(transition_index, cycle_count, color="#1f77b4", width=0.8, label="Fetch cycles")
    ax.plot(transition_index, changed_bits / 4.0, color="#d62728", linewidth=1.4, label="Changed bits / 4 (lower bound)")

    ax.set_title(title)
    ax.set_xlabel("Iteration transition")
    ax.set_ylabel("Internal fetch cycles")
    ax.grid(True, alpha=0.3, axis="y")
    ax.legend(loc="upper right")

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_percentage_stop_accuracy(
    analysis: Mapping[str, object],
    title: str = "Early-Stop Accuracy (%)",
    figsize: tuple[float, float] = (11.0, 5.5),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot the per-transition early-stop accuracy as a percentage.

    Args:
        analysis: Dictionary returned by compute_case_percentage_stop_accuracy.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional output image path.
        show: Whether to call plt.show().

    Returns:
        Figure and axis.
    """
    transition_index = np.asarray(analysis["transition_index"], dtype=np.int64)
    accuracy_percent = np.asarray(analysis["accuracy_percent"], dtype=np.float64)
    executed_cycles = np.asarray(analysis["executed_cycles"], dtype=np.int64)
    total_cycles = np.asarray(analysis["total_cycles"], dtype=np.int64)
    reserve_fraction = float(np.asarray(analysis.get("reserve_fraction", np.asarray([0.0])))[0])

    if transition_index.ndim != 1:
        raise ValueError(f"transition_index must be 1D, got shape {transition_index.shape}")
    if accuracy_percent.shape != transition_index.shape:
        raise ValueError(
            f"accuracy_percent must match transition_index shape, got {accuracy_percent.shape} and {transition_index.shape}"
        )

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    ax.plot(transition_index, accuracy_percent, color="#1f77b4", linewidth=1.6, label="Accuracy ratio (%)")
    ax.axhline(100.0, color="#d62728", linestyle="--", linewidth=1.0, alpha=0.8, label="Reference 100%")

    ax.set_title(f"{title} (reserve last {reserve_fraction * 100:.1f}%)")
    ax.set_xlabel("Iteration transition")
    ax.set_ylabel("Early-exit value / full value (%)")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="upper right")

    ax2 = ax.twinx()
    ax2.step(transition_index, executed_cycles, where="mid", color="#ff7f0e", linewidth=1.2, alpha=0.65, label="Executed cycles")
    ax2.plot(transition_index, total_cycles, color="#2ca02c", linewidth=1.0, alpha=0.45, label="Total cycles")
    ax2.set_ylabel("Cycles")

    handles_1, labels_1 = ax.get_legend_handles_labels()
    handles_2, labels_2 = ax2.get_legend_handles_labels()
    ax2.legend(handles_1 + handles_2, labels_1 + labels_2, loc="lower right")

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_percentage_stop_drop_comparison(
    case_data: EarlyExitCaseData,
    reserve_fractions: Sequence[float] = (0.05, 0.10, 0.15, 0.20, 0.25),
    mode: str = "propagated",
    title: str = "Early-Stop Accuracy Drop Comparison",
    figsize: tuple[float, float] = (12.0, 6.0),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot accuracy drop for several reserve fractions on the same transition axis.

    The y-axis shows the drop from ideal accuracy, computed as:
        drop_percent = 100 - accuracy_percent

    By default the helper uses propagated accumulation, so each transition's
    early-exit energy is built on top of the previous approximate energy and
    the drop can grow over time.

    Args:
        case_data: Loaded case data.
        reserve_fractions: Stop percentages to compare, for example 0.05 for 5%.
        mode: Accuracy accumulation mode passed to
            compute_case_percentage_stop_accuracy.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional output image path.
        show: Whether to call plt.show().

    Returns:
        Figure and axis.
    """
    if not reserve_fractions:
        raise ValueError("reserve_fractions must not be empty")

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    color_map = plt.get_cmap("tab10")

    for idx, reserve_fraction in enumerate(reserve_fractions):
        analysis = compute_case_percentage_stop_accuracy(
            case_data,
            reserve_fraction=float(reserve_fraction),
            mode=mode,
        )
        transition_index = np.asarray(analysis["transition_index"], dtype=np.int64)
        accuracy_percent = np.asarray(analysis["accuracy_percent"], dtype=np.float64)
        accuracy_drop = 100.0 - accuracy_percent

        ax.plot(
            transition_index,
            accuracy_drop,
            linewidth=1.6,
            color=color_map(idx % 10),
            label=f"reserve {float(reserve_fraction) * 100:.0f}%",
        )

    ax.set_title(title)
    ax.set_xlabel("Iteration transition")
    ax.set_ylabel("Accuracy drop (%) = 100 - accuracy")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best")

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_wrong_decision_rate_comparison(
    case_data: EarlyExitCaseData,
    reserve_fractions: Sequence[float] = (0.05, 0.10, 0.15, 0.20, 0.25, 0.30),
    zero_is_decrease: bool = True,
    zero_is_increase: bool = False,
    title: str = "Wrong Decision Rate vs Reserve Fraction",
    figsize: tuple[float, float] = (11.5, 6.0),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Plot the percentage of wrong sign decisions for several reserve fractions.

    A wrong decision is a propagated incremental update whose sign is opposite
    to the sign of the full-energy transition. When zero_is_decrease is True,
    a zero delta is treated as a decrease. When zero_is_increase is True, a
    zero delta is treated as an increase.

    Args:
        case_data: Loaded case data.
        reserve_fractions: Stop percentages to compare, for example 0.05 for 5%.
        title: Plot title.
        figsize: Figure size.
        dpi: Figure DPI.
        output_path: Optional output image path.
        show: Whether to call plt.show().

    Returns:
        Figure and axis.
    """
    if not reserve_fractions:
        raise ValueError("reserve_fractions must not be empty")

    fractions = np.asarray([float(value) for value in reserve_fractions], dtype=np.float64)
    wrong_decision_rates = np.zeros_like(fractions, dtype=np.float64)
    wrong_decision_rates_all = np.zeros_like(fractions, dtype=np.float64)
    accuracy_percent = np.zeros_like(fractions, dtype=np.float64)

    for idx, reserve_fraction in enumerate(fractions):
        analysis = compute_case_wrong_decision_rate(
            case_data,
            reserve_fraction=float(reserve_fraction),
            zero_is_decrease=zero_is_decrease,
            zero_is_increase=zero_is_increase,
        )
        wrong_decision_rates[idx] = float(np.asarray(analysis["wrong_decision_rate"], dtype=np.float64)[0])
        wrong_decision_rates_all[idx] = float(np.asarray(analysis["wrong_decision_rate_all"], dtype=np.float64)[0])
        accuracy_percent[idx] = float(np.asarray(analysis["accuracy_percent"], dtype=np.float64)[0])

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    bars = ax.bar(fractions * 100.0, wrong_decision_rates, color="#d62728", width=3.0, alpha=0.85)
    ax.set_title(title)
    ax.set_xlabel("Reserved last cycles (%)")
    if zero_is_increase:
        y_label = "Wrong decision rate (%)"
    elif zero_is_decrease:
        y_label = "Wrong decision rate (%)"
    else:
        y_label = "Wrong decision rate among nonzero transitions (%)"
    ax.set_ylabel(y_label)
    ax.set_ylim(0.0, max(100.0, float(np.max(wrong_decision_rates)) * 1.15))
    ax.set_xticks(fractions * 100.0)
    ax.set_xticklabels([f"{int(round(value * 100))}%" for value in fractions])
    ax.grid(True, axis="y", alpha=0.3)

    for bar, wrong_rate in zip(bars, wrong_decision_rates, strict=False):
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{wrong_rate:.1f}%",
            ha="center",
            va="bottom",
            fontsize=8,
        )

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_percentage_stop_drop_comparison_avg(
    case_data_1: EarlyExitCaseData,
    case_data_2: EarlyExitCaseData,
    reserve_fractions: Sequence[float] = (0.05, 0.10, 0.15, 0.20, 0.25),
    mode: str = "propagated",
    title: str = "Average Early-Stop Accuracy Drop Across Cases 1 and 2",
    figsize: tuple[float, float] = (12.0, 6.0),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Compute and plot the average accuracy drop across two cases.

    This helper runs `compute_case_percentage_stop_accuracy` for both cases
    and plots the element-wise average of the drops (100 - accuracy_percent).
    """
    if not reserve_fractions:
        raise ValueError("reserve_fractions must not be empty")

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    color_map = plt.get_cmap("tab10")

    for idx, reserve_fraction in enumerate(reserve_fractions):
        a1 = compute_case_percentage_stop_accuracy(case_data_1, reserve_fraction=float(reserve_fraction), mode=mode)
        a2 = compute_case_percentage_stop_accuracy(case_data_2, reserve_fraction=float(reserve_fraction), mode=mode)

        t1 = np.asarray(a1["transition_index"], dtype=np.int64)
        t2 = np.asarray(a2["transition_index"], dtype=np.int64)
        min_n = min(t1.shape[0], t2.shape[0])

        drop1 = 100.0 - np.asarray(a1["accuracy_percent"], dtype=np.float64)[:min_n]
        drop2 = 100.0 - np.asarray(a2["accuracy_percent"], dtype=np.float64)[:min_n]
        avg_drop = 0.5 * (drop1 + drop2)

        ax.plot(
            np.arange(1, min_n + 1),
            avg_drop,
            linewidth=1.6,
            color=color_map(idx % 10),
            label=f"reserve {float(reserve_fraction) * 100:.0f}%",
        )

    ax.set_title(title, fontsize=20)
    ax.set_xlabel("Iteration transition", fontsize=18)
    ax.set_ylabel("Average accuracy drop (%) = 100 - accuracy", fontsize=18)
    ax.tick_params(axis="both", labelsize=16)
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best", fontsize=16)

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")
        fig.savefig(out.with_suffix(".pdf"), bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax


def plot_wrong_decision_rate_comparison_avg(
    case_data_1: EarlyExitCaseData,
    case_data_2: EarlyExitCaseData,
    reserve_fractions: Sequence[float] = (0.05, 0.10, 0.15, 0.20, 0.25, 0.30),
    zero_is_decrease: bool = True,
    zero_is_increase: bool = False,
    title: str = "Average Wrong Decision Rate vs Reserve Fraction (cases 1 & 2)",
    figsize: tuple[float, float] = (11.5, 6.0),
    dpi: int = 150,
    output_path: str | Path | None = None,
    show: bool = False,
) -> tuple[plt.Figure, plt.Axes]:
    """Compute wrong-decision rates for both cases and plot their average as bars.

    When zero_is_decrease is True, a zero delta is treated as a decrease.
    When zero_is_increase is True, a zero delta is treated as an increase.
    """
    if not reserve_fractions:
        raise ValueError("reserve_fractions must not be empty")

    fractions = np.asarray([float(value) for value in reserve_fractions], dtype=np.float64)
    avg_wrong = np.zeros_like(fractions, dtype=np.float64)
    avg_wrong_all = np.zeros_like(fractions, dtype=np.float64)

    for idx, reserve_fraction in enumerate(fractions):
        a1 = compute_case_wrong_decision_rate(
            case_data_1,
            reserve_fraction=float(reserve_fraction),
            zero_is_decrease=zero_is_decrease,
            zero_is_increase=zero_is_increase,
        )
        a2 = compute_case_wrong_decision_rate(
            case_data_2,
            reserve_fraction=float(reserve_fraction),
            zero_is_decrease=zero_is_decrease,
            zero_is_increase=zero_is_increase,
        )

        r1 = float(np.asarray(a1["wrong_decision_rate"], dtype=np.float64)[0])
        r2 = float(np.asarray(a2["wrong_decision_rate"], dtype=np.float64)[0])
        ra1 = float(np.asarray(a1["wrong_decision_rate_all"], dtype=np.float64)[0])
        ra2 = float(np.asarray(a2["wrong_decision_rate_all"], dtype=np.float64)[0])

        avg_wrong[idx] = 0.5 * (r1 + r2)
        avg_wrong_all[idx] = 0.5 * (ra1 + ra2)

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    bars = ax.bar(fractions * 100.0, avg_wrong, color="#d62728", width=3.0, alpha=0.85)
    ax.set_title(title)
    ax.set_xlabel("Reserved last cycles (%)")
    if zero_is_increase:
        y_label = "Avg wrong decision rate (%)"
    elif zero_is_decrease:
        y_label = "Avg wrong decision rate (%)"
    else:
        y_label = "Avg wrong decision rate among nonzero transitions (%)"
    ax.set_ylabel(y_label)
    ax.set_ylim(0.0, max(100.0, float(np.max(avg_wrong)) * 1.15))
    ax.set_xticks(fractions * 100.0)
    ax.set_xticklabels([f"{int(round(value * 100))}%" for value in fractions])
    ax.grid(True, axis="y", alpha=0.3)

    for bar, wrong_rate in zip(bars, avg_wrong, strict=False):
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            bar.get_height(),
            f"{wrong_rate:.1f}%",
            ha="center",
            va="bottom",
            fontsize=8,
        )

    fig.tight_layout()

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, bbox_inches="tight")

    if show:
        plt.show()

    return fig, ax
