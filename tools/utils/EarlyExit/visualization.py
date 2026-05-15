"""Visualization helpers for early-exit datasets."""

from __future__ import annotations

from pathlib import Path
from collections.abc import Mapping

import matplotlib.pyplot as plt
import numpy as np

from .data_loader import EarlyExitCaseData


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
