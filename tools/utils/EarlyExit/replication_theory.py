"""Theoretical model of replication benefits.

Instead of complex scheduling algorithms, this models the theoretical
minimum cycles achievable with different replication strategies.
"""

from __future__ import annotations

import numpy as np


def theoretical_cycles_with_replication(
    n_changed_columns: int,
    replication_strategy: str = "1x",
    num_banks: int = 4,
) -> int:
    """Compute theoretical minimum cycles with replication.

    Replication strategies enable better parallelism:
    - 1x: Columns fixed to specific banks (current round-robin), max depth varies
    - 2x_partial: 50% of high-load columns replicated to even distribution
    - 2x_full: Each column in 2 banks, better load balancing
    - 4x_full: Each column everywhere, perfect parallelism

    Args:
        n_changed_columns: Number of unique columns that changed.
        replication_strategy: One of "1x", "2x_partial", "2x_full", "4x_full".
        num_banks: Number of banks (default 4).

    Returns:
        Theoretical minimum cycles needed.
    """
    if replication_strategy == "1x":
        # Baseline: worst-case is when all columns map to same bank
        # Best-case: ceil(n / num_banks). Average depends on distribution.
        # For random distribution, expected depth per bank ≈ n / num_banks
        # Max depth (worst case) ≈ n / 4 for heavily skewed distribution
        # Typical: ~1.5x * ideal
        return max(1, int(np.ceil(n_changed_columns / num_banks * 1.5)))

    elif replication_strategy == "2x_partial":
        # Replicate ~50% of columns, reduces max depth from worst-case
        # Better load balancing but not perfect
        # Cycles ≈ 1.2x * ideal
        ideal_cycles = max(1, int(np.ceil(n_changed_columns / num_banks)))
        return max(1, int(np.ceil(ideal_cycles * 1.2)))

    elif replication_strategy == "2x_full":
        # Each column in 2 banks, good load balancing
        # Cycles ≈ 1.1x * ideal (close to theoretical min)
        ideal_cycles = max(1, int(np.ceil(n_changed_columns / num_banks)))
        return max(1, int(np.ceil(ideal_cycles * 1.1)))

    elif replication_strategy == "4x_full":
        # Each column everywhere, perfect parallelism
        # Cycles = ceil(n / num_banks) (theoretical minimum)
        return max(1, int(np.ceil(n_changed_columns / num_banks)))

    else:
        raise ValueError(f"Unknown replication_strategy: {replication_strategy}")


def compute_replication_benefit_stats(
    case_data,
    strategies: list[str] | None = None,
) -> dict[str, dict]:
    """Compute theoretical benefit of replication for a case.

    Args:
        case_data: EarlyExitCaseData object.
        strategies: List of strategies to compare. Defaults to all 4.

    Returns:
        Dict mapping strategy names to stats dicts.
    """
    from .energy_calc import changed_spin_indices

    if strategies is None:
        strategies = ["1x", "2x_partial", "2x_full", "4x_full"]

    num_states = case_data.states_out_bits.shape[0]
    results = {}

    for strategy in strategies:
        cycle_counts = []
        changed_bits_counts = []

        for transition_idx in range(1, num_states):
            prev_bits = case_data.states_out_bits[transition_idx - 1]
            curr_bits = case_data.states_out_bits[transition_idx]

            changed_cols = changed_spin_indices(prev_bits, curr_bits)
            n_changed = len(changed_cols)

            cycles = theoretical_cycles_with_replication(n_changed, strategy, num_banks=4)

            cycle_counts.append(cycles)
            changed_bits_counts.append(n_changed)

        results[strategy] = {
            "cycle_counts": np.array(cycle_counts),
            "changed_bits_counts": np.array(changed_bits_counts),
            "mean_cycles": float(np.mean(cycle_counts)),
            "median_cycles": float(np.median(cycle_counts)),
            "max_cycles": int(np.max(cycle_counts)),
            "total_cycles": int(np.sum(cycle_counts)),
            "mean_bits": float(np.mean(changed_bits_counts)),
        }

    return results
