"""Analyze bandwidth improvement via memory replication strategies.

This module explores replicating columns across multiple banks to reduce
cycle count and improve bandwidth utilization at the cost of increased
memory size.

Replication strategies:
  - 1x (baseline): Each column in exactly one bank
  - 2x partial: 50% of columns replicated to second bank
  - 2x full: Each column replicated to 2 banks
  - 4x full: Each column replicated to all 4 banks
"""

from __future__ import annotations

from collections import deque
from typing import Literal

import numpy as np


def _replica_banks_for_column(
    column: int,
    num_banks: int,
    replication_factor: Literal["1x", "2x_partial", "2x_full", "4x_full"],
    bank_column_counts: np.ndarray | None = None,
) -> list[int]:
    """Return the banks that can serve a column under the replication scheme.

    For `2x_partial`, a column is considered replicated if it is in the upper
    half of its primary bank's local address range for the current access set.
    This keeps the model deterministic while still reflecting selective
    replication of hotter columns.
    """
    primary = int(column % num_banks)

    if replication_factor == "1x":
        return [primary]

    if replication_factor == "4x_full":
        return list(range(num_banks))

    secondary = int((primary + 1) % num_banks)
    if replication_factor == "2x_full":
        return [primary, secondary]

    if replication_factor == "2x_partial":
        if bank_column_counts is None:
            return [primary]
        local_addr = int(column // num_banks)
        primary_count = int(bank_column_counts[primary])
        if primary_count > 1 and local_addr >= primary_count // 2:
            return [primary, secondary]
        return [primary]

    raise ValueError(f"Unknown replication_factor: {replication_factor}")


def _find_feasible_assignment(
    ordered_columns: list[int],
    candidate_banks: list[list[int]],
    num_banks: int,
    max_load: int,
) -> list[int] | None:
    """Find a deterministic assignment with bank loads bounded by `max_load`."""
    n_cols = len(ordered_columns)
    source = 0
    column_offset = 1
    bank_offset = column_offset + n_cols
    sink = bank_offset + num_banks
    graph_size = sink + 1

    class Dinic:
        def __init__(self, size: int):
            self.size = size
            self.graph: list[list[list[object]]] = [[] for _ in range(size)]

        def add_edge(self, u: int, v: int, cap: int) -> None:
            forward = [v, cap, None]
            backward = [u, 0, forward]
            forward[2] = backward
            self.graph[u].append(forward)
            self.graph[v].append(backward)

        def max_flow(self, src: int, snk: int) -> int:
            flow = 0
            while True:
                level = [-1] * self.size
                queue = deque([src])
                level[src] = 0
                while queue:
                    node = queue.popleft()
                    for edge in self.graph[node]:
                        if int(edge[1]) > 0 and level[int(edge[0])] < 0:
                            level[int(edge[0])] = level[node] + 1
                            queue.append(int(edge[0]))
                if level[snk] < 0:
                    return flow

                iters = [0] * self.size

                def dfs(node: int, pushed: int) -> int:
                    if node == snk:
                        return pushed
                    for idx in range(iters[node], len(self.graph[node])):
                        iters[node] = idx
                        edge = self.graph[node][idx]
                        nxt = int(edge[0])
                        if int(edge[1]) <= 0 or level[nxt] != level[node] + 1:
                            continue
                        result = dfs(nxt, min(pushed, int(edge[1])))
                        if result > 0:
                            edge[1] = int(edge[1]) - result
                            edge[2][1] = int(edge[2][1]) + result
                            return result
                    return 0

                while True:
                    pushed = dfs(src, 1 << 30)
                    if pushed == 0:
                        break
                    flow += pushed

    net = Dinic(graph_size)
    for idx in range(n_cols):
        net.add_edge(source, column_offset + idx, 1)
        for bank in candidate_banks[idx]:
            net.add_edge(column_offset + idx, bank_offset + bank, 1)
    for bank in range(num_banks):
        net.add_edge(bank_offset + bank, sink, max_load)

    if net.max_flow(source, sink) != n_cols:
        return None

    assignment: list[int] = []
    for idx in range(n_cols):
        column_node = column_offset + idx
        chosen_bank = None
        for edge in net.graph[column_node]:
            target = int(edge[0])
            if bank_offset <= target < bank_offset + num_banks and int(edge[1]) == 0:
                chosen_bank = target - bank_offset
                break
        if chosen_bank is None:
            return None
        assignment.append(int(chosen_bank))

    return assignment


def _assign_columns_to_banks(
    columns: np.ndarray,
    num_banks: int,
    replication_factor: Literal["1x", "2x_partial", "2x_full", "4x_full"],
) -> list[list[int]]:
    """Assign each column to exactly one bank with minimum possible max load."""
    cols = np.asarray(columns, dtype=np.int64)
    if cols.size == 0:
        return [[] for _ in range(num_banks)]

    bank_column_counts = np.array([int(np.sum(cols % num_banks == bank)) for bank in range(num_banks)], dtype=np.int64)
    ordered_columns = sorted(
        (int(col) for col in cols),
        key=lambda col: (
            len(_replica_banks_for_column(col, num_banks, replication_factor, bank_column_counts)),
            col // num_banks,
            col,
        ),
    )
    candidate_banks = [
        _replica_banks_for_column(col, num_banks, replication_factor, bank_column_counts)
        for col in ordered_columns
    ]

    min_load = int(np.ceil(len(ordered_columns) / num_banks))
    max_load = len(ordered_columns)
    chosen_assignment: list[int] | None = None

    while min_load <= max_load:
        trial_load = (min_load + max_load) // 2
        assignment = _find_feasible_assignment(ordered_columns, candidate_banks, num_banks, trial_load)
        if assignment is not None:
            chosen_assignment = assignment
            max_load = trial_load - 1
        else:
            min_load = trial_load + 1

    if chosen_assignment is None:
        raise RuntimeError("Could not find a feasible bank assignment")

    bank_queues: list[list[int]] = [[] for _ in range(num_banks)]
    for col, bank in zip(ordered_columns, chosen_assignment):
        bank_queues[int(bank)].append(int(col))

    for bank in range(num_banks):
        bank_queues[bank].sort(key=lambda col: (col // num_banks, col))

    return bank_queues


def schedule_changed_columns_replicated(
    changed_columns: np.ndarray,
    num_banks: int = 4,
    replication_factor: Literal["1x", "2x_partial", "2x_full", "4x_full"] = "1x",
) -> list[dict[str, np.ndarray | int]]:
    """Schedule changed columns with memory replication.

    The schedule is derived from an exact minimum-max-load assignment and then
    packed cycle-by-cycle so that each bank contributes at most one column per
    cycle.
    """
    cols = np.asarray(changed_columns, dtype=np.int64)
    if cols.ndim != 1:
        raise ValueError(f"changed_columns must be 1D, got shape {cols.shape}")

    bank_queues = _assign_columns_to_banks(cols, num_banks, replication_factor)

    max_depth = max((len(queue) for queue in bank_queues), default=0)
    cycles: list[dict[str, np.ndarray | int]] = []

    for cycle_idx in range(max_depth):
        cycle_cols: list[int] = []
        cycle_banks: list[int] = []
        cycle_addrs: list[int] = []
        for bank in range(num_banks):
            if cycle_idx < len(bank_queues[bank]):
                col = int(bank_queues[bank][cycle_idx])
                cycle_cols.append(col)
                cycle_banks.append(bank)
                cycle_addrs.append(int(col // num_banks))

        if cycle_cols:
            cycles.append(
                {
                    "cycle": cycle_idx,
                    "columns": np.asarray(cycle_cols, dtype=np.int64),
                    "banks": np.asarray(cycle_banks, dtype=np.int64),
                    "addresses": np.asarray(cycle_addrs, dtype=np.int64),
                }
            )

    return cycles


def estimate_memory_overhead(
    replication_factor: Literal["1x", "2x_partial", "2x_full", "4x_full"],
    column_width_bits: int = 64,
    num_columns: int = 256,
) -> dict[str, float | int]:
    """Estimate memory overhead for different replication strategies.

    Args:
        replication_factor: Replication strategy.
        column_width_bits: Width of each J/h column in bits.
        num_columns: Total number of columns.

    Returns:
        Dict with keys:
        - "replication_factor": the factor (1, 1.5, 2, or 4)
        - "total_bits": total bits stored
        - "memory_multiplier": vs 1x baseline
        - "memory_per_bank": bits per bank
    """
    baseline_bits = num_columns * column_width_bits

    if replication_factor == "1x":
        factor = 1.0
        total_bits = baseline_bits
        memory_per_bank = baseline_bits / 4

    elif replication_factor == "2x_partial":
        factor = 1.5
        total_bits = int(1.5 * baseline_bits)
        memory_per_bank = int(1.5 * baseline_bits) / 4

    elif replication_factor == "2x_full":
        factor = 2.0
        total_bits = 2 * baseline_bits
        memory_per_bank = 2 * baseline_bits / 4

    elif replication_factor == "4x_full":
        factor = 4.0
        total_bits = 4 * baseline_bits
        memory_per_bank = 4 * baseline_bits / 4

    else:
        raise ValueError(f"Unknown replication_factor: {replication_factor}")

    return {
        "replication_factor": factor,
        "total_bits": total_bits,
        "memory_multiplier": total_bits / baseline_bits,
        "memory_per_bank": int(memory_per_bank),
    }


def compute_replication_statistics(
    case_data,
    replication_strategies: list[str] | None = None,
    include_offset: bool = False,
) -> dict[str, object]:
    """Analyze cycle counts and efficiency across replication strategies."""
    from .energy_calc import changed_spin_indices, bits_to_spins

    if replication_strategies is None:
        replication_strategies = ["1x", "2x_partial", "2x_full", "4x_full"]

    num_states = case_data.states_out_bits.shape[0]
    results = {}

    for strategy in replication_strategies:
        cycle_counts = []
        changed_bits_counts = []
        bank_utilizations = []
        bank_loads = []

        for transition_idx in range(1, num_states):
            prev_bits = case_data.states_out_bits[transition_idx - 1]
            curr_bits = case_data.states_out_bits[transition_idx]

            changed_cols = changed_spin_indices(prev_bits, curr_bits)
            if changed_cols.size == 0:
                cycle_counts.append(0)
                changed_bits_counts.append(0)
                continue

            cycles = schedule_changed_columns_replicated(
                changed_cols,
                num_banks=4,
                replication_factor=strategy,
            )

            cycle_count = len(cycles)
            cycle_counts.append(cycle_count)
            changed_bits_counts.append(len(changed_cols))
            if cycle_count > 0:
                bank_load = np.zeros(4, dtype=np.int64)
                for cycle in cycles:
                    banks = np.asarray(cycle["banks"], dtype=np.int64)
                    for bank in banks:
                        bank_load[int(bank)] += 1
                bank_loads.append(bank_load)
                bank_utilizations.append(bank_load / float(cycle_count) * 100.0)
            else:
                bank_loads.append(np.zeros(4, dtype=np.int64))
                bank_utilizations.append(np.zeros(4, dtype=np.float64))

        bank_loads_arr = np.asarray(bank_loads, dtype=np.int64)
        bank_utils_arr = np.asarray(bank_utilizations, dtype=np.float64)
        results[strategy] = {
            "cycle_counts": np.array(cycle_counts),
            "changed_bits_counts": np.array(changed_bits_counts),
            "mean_cycles": float(np.mean(cycle_counts)),
            "median_cycles": float(np.median(cycle_counts)),
            "max_cycles": int(np.max(cycle_counts)),
            "total_cycles": int(np.sum(cycle_counts)),
            "mean_bits": float(np.mean(changed_bits_counts)),
            "bank_loads": bank_loads_arr,
            "bank_utilization_percent": bank_utils_arr,
            "mean_bank_utilization_percent": np.mean(bank_utils_arr, axis=0),
            "aggregate_bandwidth_utilization_percent": float(
                np.sum(bank_loads_arr) / (np.sum(cycle_counts) * 4) * 100.0
                if np.sum(cycle_counts) > 0
                else 0.0
            ),
            "efficiency": float(np.mean(changed_bits_counts) / np.mean(cycle_counts))
            if np.mean(cycle_counts) > 0
            else 0.0,
        }

    return results
