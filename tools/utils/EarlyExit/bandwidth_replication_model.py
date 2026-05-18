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

from typing import Literal

import numpy as np


def schedule_changed_columns_replicated(
    changed_columns: np.ndarray,
    num_banks: int = 4,
    replication_factor: Literal["1x", "2x_partial", "2x_full", "4x_full"] = "1x",
) -> list[dict[str, np.ndarray | int]]:
    """Schedule changed columns with memory replication.

    Replication strategies:
    - 1x: No replication (baseline)
    - 2x_partial: Replicate ~50% of columns to a secondary bank (those with highest addresses)
    - 2x_full: Each column replicated to 2 banks (even distribution)
    - 4x_full: Each column replicated to all 4 banks (maximum flexibility)

    With replication, the scheduler can choose which bank to fetch from, allowing
    load balancing to reduce total cycles needed. The algorithm distributes fetches
    across cycles to minimize the maximum bank depth.

    Args:
        changed_columns: 1D array of changed column indices.
        num_banks: Number of banks.
        replication_factor: Replication strategy.

    Returns:
        List of cycle dicts with keys: cycle, columns, banks, addresses.
    """
    cols = np.asarray(changed_columns, dtype=np.int64)
    if cols.ndim != 1:
        raise ValueError(f"changed_columns must be 1D, got shape {cols.shape}")

    if replication_factor == "1x":
        # Baseline: no replication, standard round-robin banking
        bank_columns: list[np.ndarray] = []
        bank_addresses: list[np.ndarray] = []
        max_depth = 0
        for bank in range(num_banks):
            current = cols[cols % num_banks == bank]
            if current.size == 0:
                bank_columns.append(np.array([], dtype=np.int64))
                bank_addresses.append(np.array([], dtype=np.int64))
                continue
            order = np.argsort(current // num_banks, kind="stable")
            current = current[order]
            addresses = current // num_banks
            bank_columns.append(current)
            bank_addresses.append(addresses)
            max_depth = max(max_depth, int(current.size))

        cycles: list[dict[str, np.ndarray | int]] = []
        for cycle_idx in range(max_depth):
            cycle_cols: list[int] = []
            cycle_banks: list[int] = []
            cycle_addrs: list[int] = []
            for bank in range(num_banks):
                if cycle_idx < bank_columns[bank].size:
                    cycle_cols.append(int(bank_columns[bank][cycle_idx]))
                    cycle_banks.append(bank)
                    cycle_addrs.append(int(bank_addresses[bank][cycle_idx]))
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

    elif replication_factor == "2x_partial":
        # Replicate 50% of columns (those needing highest addresses) to secondary banks
        # This reduces the maximum depth of heavily-loaded banks

        # First, identify which columns go to which banks in original scheme
        bank_columns_original: list[np.ndarray] = []
        bank_depths: list[int] = []
        
        for bank in range(num_banks):
            current = cols[cols % num_banks == bank]
            if current.size > 0:
                order = np.argsort(current // num_banks, kind="stable")
                current = current[order]
                bank_columns_original.append(current)
                bank_depths.append(current.size)
            else:
                bank_columns_original.append(np.array([], dtype=np.int64))
                bank_depths.append(0)
        
        max_depth = max(bank_depths) if bank_depths else 0
        
        # Create replicas: highest-address columns get replicated to secondary banks
        # This reduces the maximum depth
        bank_columns_replica: list[set[int]] = [set() for _ in range(num_banks)]
        
        for bank in range(num_banks):
            bank_cols = bank_columns_original[bank]
            if bank_cols.size == 0:
                continue
            
            # Add all columns to primary bank
            for col in bank_cols:
                bank_columns_replica[bank].add(col)
            
            # Replicate top 50% (highest addresses) to secondary bank
            replicate_count = max(1, int(np.ceil(bank_cols.size / 2)))
            for col in bank_cols[-replicate_count:]:  # Top 50%
                secondary_bank = (bank + 1) % num_banks
                bank_columns_replica[secondary_bank].add(col)
        
        # Schedule using greedy load-balancing
        cycles: list[dict[str, np.ndarray | int]] = []
        remaining: list[set[int]] = [set(bank_columns_replica[b]) for b in range(num_banks)]
        cycle_idx = 0
        
        while any(remaining):
            cycle_cols: list[int] = []
            cycle_banks: list[int] = []
            cycle_addrs: list[int] = []
            
            # For each bank, fetch one column if available
            for bank in range(num_banks):
                if remaining[bank]:
                    col = remaining[bank].pop()
                    cycle_cols.append(col)
                    cycle_banks.append(bank)
                    cycle_addrs.append(col // num_banks)
            
            if cycle_cols:
                cycles.append(
                    {
                        "cycle": cycle_idx,
                        "columns": np.asarray(cycle_cols, dtype=np.int64),
                        "banks": np.asarray(cycle_banks, dtype=np.int64),
                        "addresses": np.asarray(cycle_addrs, dtype=np.int64),
                    }
                )
                cycle_idx += 1
        
        return cycles

    elif replication_factor == "2x_full":
        # Each column replicated to 2 banks: its primary bank and a secondary bank
        # Column i → banks: (i % 4) and ((i+1) % 4)
        
        bank_columns_replica: list[set[int]] = [set() for _ in range(num_banks)]
        
        for col in cols:
            primary = int(col % num_banks)
            secondary = int((col + 1) % num_banks)
            bank_columns_replica[primary].add(col)
            if secondary != primary:
                bank_columns_replica[secondary].add(col)
        
        # Greedy scheduling: balance load across cycles
        cycles: list[dict[str, np.ndarray | int]] = []
        remaining: list[set[int]] = [set(bank_columns_replica[b]) for b in range(num_banks)]
        cycle_idx = 0
        
        while any(remaining):
            cycle_cols: list[int] = []
            cycle_banks: list[int] = []
            cycle_addrs: list[int] = []
            
            for bank in range(num_banks):
                if remaining[bank]:
                    col = remaining[bank].pop()
                    cycle_cols.append(col)
                    cycle_banks.append(bank)
                    cycle_addrs.append(col // num_banks)
            
            if cycle_cols:
                cycles.append(
                    {
                        "cycle": cycle_idx,
                        "columns": np.asarray(cycle_cols, dtype=np.int64),
                        "banks": np.asarray(cycle_banks, dtype=np.int64),
                        "addresses": np.asarray(cycle_addrs, dtype=np.int64),
                    }
                )
                cycle_idx += 1
        
        return cycles

    elif replication_factor == "4x_full":
        # Each column replicated to all 4 banks (maximum flexibility)
        # This allows completely free scheduling: every column accessible from any bank
        
        unique_cols = np.unique(cols)
        bank_columns_replica: list[set[int]] = [set(unique_cols) for _ in range(num_banks)]
        
        cycles: list[dict[str, np.ndarray | int]] = []
        remaining: list[set[int]] = [set(bank_columns_replica[b]) for b in range(num_banks)]
        cycle_idx = 0
        
        while any(remaining):
            cycle_cols: list[int] = []
            cycle_banks: list[int] = []
            cycle_addrs: list[int] = []
            
            for bank in range(num_banks):
                if remaining[bank]:
                    col = remaining[bank].pop()
                    cycle_cols.append(col)
                    cycle_banks.append(bank)
                    cycle_addrs.append(col // num_banks)
            
            if cycle_cols:
                cycles.append(
                    {
                        "cycle": cycle_idx,
                        "columns": np.asarray(cycle_cols, dtype=np.int64),
                        "banks": np.asarray(cycle_banks, dtype=np.int64),
                        "addresses": np.asarray(cycle_addrs, dtype=np.int64),
                    }
                )
                cycle_idx += 1
        
        return cycles

    else:
        raise ValueError(f"Unknown replication_factor: {replication_factor}")


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
        # Replicate ~50% of columns, so average replication ~1.5x
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
    """Analyze cycle counts and efficiency across replication strategies.

    Args:
        case_data: EarlyExitCaseData object.
        replication_strategies: List of replication factors to test.
                               Defaults to ["1x", "2x_partial", "2x_full", "4x_full"].
        include_offset: Whether to include offset in energy calc (unused here).

    Returns:
        Dictionary with per-strategy cycle statistics.
    """
    from .energy_calc import changed_spin_indices, bits_to_spins

    if replication_strategies is None:
        replication_strategies = ["1x", "2x_partial", "2x_full", "4x_full"]

    num_states = case_data.states_out_bits.shape[0]
    results = {}

    for strategy in replication_strategies:
        cycle_counts = []
        changed_bits_counts = []

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

            cycle_counts.append(len(cycles))
            changed_bits_counts.append(len(changed_cols))

        results[strategy] = {
            "cycle_counts": np.array(cycle_counts),
            "changed_bits_counts": np.array(changed_bits_counts),
            "mean_cycles": float(np.mean(cycle_counts)),
            "median_cycles": float(np.median(cycle_counts)),
            "max_cycles": int(np.max(cycle_counts)),
            "total_cycles": int(np.sum(cycle_counts)),
            "mean_bits": float(np.mean(changed_bits_counts)),
            "efficiency": float(np.mean(changed_bits_counts) / np.mean(cycle_counts))
            if np.mean(cycle_counts) > 0
            else 0.0,
        }

    return results
