"""Hamiltonian energy calculation for Ising spin system.

Computes the total energy as:
    H = -0.5 * s^T * J * s - h^T * s

Where s are the spins (converted to {-1, +1}), J is the coupling matrix,
and h is the bias vector.

Scaling factor is applied as per hardware implementation.
"""

from __future__ import annotations

from typing import Literal

import numpy as np

from .data_loader import EarlyExitCaseData


def bits_to_spins(bits: np.ndarray) -> np.ndarray:
    """Convert {0, 1} bit representation to Ising spins {-1, +1}.
    
    Args:
        bits: Binary array with shape (..., N) where N is number of spins.
              Values should be 0 or 1.
    
    Returns:
        Spin array with same shape, values in {-1, +1}.
    """
    return 2 * bits - 1


def changed_spin_indices(previous_bits: np.ndarray, current_bits: np.ndarray) -> np.ndarray:
    """Return the indices that changed between two bit vectors.

    Args:
        previous_bits: Bit vector of shape (N,).
        current_bits: Bit vector of shape (N,).

    Returns:
        Sorted index array of the changed positions.
    """
    prev = np.asarray(previous_bits)
    curr = np.asarray(current_bits)
    if prev.shape != curr.shape:
        raise ValueError(f"bit vectors must have the same shape, got {prev.shape} and {curr.shape}")
    if prev.ndim != 1:
        raise ValueError(f"bit vectors must be 1D, got shape {prev.shape}")
    return np.flatnonzero(prev != curr)


def column_bank_index(column_index: int, num_banks: int = 4) -> int:
    """Return the memory bank used for a J/h column.

    The hardware mapping is round-robin:
        column 0 -> bank 0
        column 1 -> bank 1
        column 2 -> bank 2
        column 3 -> bank 3
        column 4 -> bank 0
        ...

    Args:
        column_index: Zero-based column index.
        num_banks: Number of memory banks.

    Returns:
        Bank index in [0, num_banks - 1].
    """
    if num_banks <= 0:
        raise ValueError("num_banks must be positive")
    return int(column_index % num_banks)


def column_bank_address(column_index: int, num_banks: int = 4) -> int:
    """Return the address within a bank for a J/h column.

    With round-robin banking, each bank stores every num_banks-th column.

    Args:
        column_index: Zero-based column index.
        num_banks: Number of memory banks.

    Returns:
        Bank-local address.
    """
    if num_banks <= 0:
        raise ValueError("num_banks must be positive")
    return int(column_index // num_banks)


def schedule_changed_columns_by_bank(
    changed_columns: np.ndarray,
    num_banks: int = 4,
    parallelism: int = 4,
) -> list[dict[str, np.ndarray | int]]:
    """Group changed columns into a hardware-like bank access schedule.

    The output is ordered bank-by-bank. Inside each bank, columns are sorted by
    their bank-local address. Each batch contains up to `parallelism` columns.

    Args:
        changed_columns: 1D array of changed column indices.
        num_banks: Number of banks used by the hardware.
        parallelism: Maximum number of columns fetched in one batch.

    Returns:
        A list of batches. Each batch is a dict with keys:
        - "bank": bank index
        - "columns": column indices in that batch
        - "addresses": bank-local addresses for those columns
    """
    cols = np.asarray(changed_columns, dtype=np.int64)
    if cols.ndim != 1:
        raise ValueError(f"changed_columns must be 1D, got shape {cols.shape}")
    if num_banks <= 0:
        raise ValueError("num_banks must be positive")
    if parallelism <= 0:
        raise ValueError("parallelism must be positive")

    batches: list[dict[str, np.ndarray | int]] = []
    for bank in range(num_banks):
        bank_columns = cols[cols % num_banks == bank]
        if bank_columns.size == 0:
            continue

        bank_columns = bank_columns[np.argsort(bank_columns // num_banks, kind="stable")]
        for start in range(0, bank_columns.size, parallelism):
            batch_columns = bank_columns[start:start + parallelism]
            batches.append(
                {
                    "bank": bank,
                    "columns": batch_columns,
                    "addresses": batch_columns // num_banks,
                }
            )

    return batches


def schedule_changed_columns_by_cycle(
    changed_columns: np.ndarray,
    num_banks: int = 4,
) -> list[dict[str, np.ndarray | int]]:
    """Group changed columns into parallel fetch cycles.

    One internal cycle can fetch at most one column from each bank. Columns are
    first sorted within each bank by bank-local address, then the i-th entry of
    each bank is fetched together in cycle i.

    Args:
        changed_columns: 1D array of changed column indices.
        num_banks: Number of banks used by the hardware.

    Returns:
        A list of cycle dictionaries with keys:
        - "cycle": cycle index
        - "columns": columns fetched in that cycle
        - "banks": bank index for each fetched column
        - "addresses": bank-local address for each fetched column
    """
    cols = np.asarray(changed_columns, dtype=np.int64)
    if cols.ndim != 1:
        raise ValueError(f"changed_columns must be 1D, got shape {cols.shape}")
    if num_banks <= 0:
        raise ValueError("num_banks must be positive")

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


def hamiltonian_energy(
    spins: np.ndarray,
    j_matrix: np.ndarray,
    h_vector: np.ndarray,
    scaling_factor: float = 4.0,
    offset: float | None = None,
) -> np.ndarray | float:
    """Compute Hamiltonian energy for Ising spin system.
    
    Computes: H = -0.5 * s^T * J * s - (h * scaling)^T * s + offset
    
    Args:
        spins: Spin configuration(s), shape (N,) or (M, N).
               Values should be in {-1, +1}.
        j_matrix: Coupling matrix, shape (N, N).
        h_vector: Bias vector, shape (N,).
        scaling_factor: Scaling applied to h_vector (default 4.0).
        offset: Constant energy offset (default None, treated as 0).
    
    Returns:
        Energy value(s). If spins is 1D, returns scalar.
        If spins is 2D (M, N), returns array of shape (M,).
    """
    # Ensure arrays are numpy
    spins = np.asarray(spins)
    j_matrix = np.asarray(j_matrix, dtype=np.float64)
    h_vector = np.asarray(h_vector, dtype=np.float64)
    
    if offset is None:
        offset = 0.0
    
    # Handle batch dimension
    if spins.ndim == 1:
        # Single spin configuration: shape (N,)
        s = spins.astype(np.float64)
        
        # Compute J contribution: -0.5 * s^T * J * s
        j_contribution = -0.5 * (s @ j_matrix @ s)
        
        # Compute h contribution: -(h * scaling)^T * s
        h_scaled = h_vector * scaling_factor
        h_contribution = -(h_scaled @ s)
        
        return j_contribution + h_contribution + offset
    
    elif spins.ndim == 2:
        # Multiple spin configurations: shape (M, N)
        s = spins.astype(np.float64)
        
        # Compute J contribution: -0.5 * s^T * J * s for each row
        # Result shape: (M,)
        j_contribution = -0.5 * np.sum(s * (s @ j_matrix.T), axis=1)
        
        # Compute h contribution: -(h * scaling)^T * s for each row
        h_scaled = h_vector * scaling_factor
        h_contribution = -(s @ h_scaled)
        
        return j_contribution + h_contribution + offset
    
    else:
        raise ValueError(f"spins must be 1D or 2D, got shape {spins.shape}")


def hamiltonian_energy_delta(
    previous_spins: np.ndarray,
    current_spins: np.ndarray,
    j_matrix: np.ndarray,
    h_vector: np.ndarray,
    scaling_factor: float = 4.0,
) -> float:
    """Compute the Hamiltonian energy delta between two spin states.

    This is the incremental form used after the first full evaluation.
    It walks only the flipped spin indices, updates the working state one
    flip at a time, and uses the affected J columns plus the affected h
    entries to accumulate the delta.

    The factors you asked about are made explicit here:
    - pairwise J contribution is accumulated as a 4x-scaled partial term
    - bias h contribution is accumulated as a 2x-scaled partial term

    Args:
        previous_spins: Previous spin vector in {-1, +1}, shape (N,).
        current_spins: Current spin vector in {-1, +1}, shape (N,).
        j_matrix: Coupling matrix, shape (N, N).
        h_vector: Bias vector, shape (N,).
        scaling_factor: Scaling applied to h_vector.

    Returns:
        Energy difference E(current) - E(previous).
    """
    prev = np.asarray(previous_spins, dtype=np.float64)
    curr = np.asarray(current_spins, dtype=np.float64)
    j = np.asarray(j_matrix, dtype=np.float64)
    h = np.asarray(h_vector, dtype=np.float64)

    if prev.shape != curr.shape:
        raise ValueError(f"spin vectors must have the same shape, got {prev.shape} and {curr.shape}")
    if prev.ndim != 1:
        raise ValueError(f"spin vectors must be 1D, got shape {prev.shape}")

    changed = np.flatnonzero(prev != curr)
    if changed.size == 0:
        return 0.0

    working = prev.copy()
    h_scaled = h * scaling_factor
    delta_energy = 0.0

    access_cycles = schedule_changed_columns_by_cycle(
        changed,
        num_banks=4,
    )

    for cycle in access_cycles:
        for idx in cycle["columns"]:
            spin_delta = curr[idx] - working[idx]  # +/- 2 for one bit flip

            # Read the target column from the bank and evaluate its contribution
            # against the current working spin state.
            j_column = j[:, idx]

            # The hardware-style normalized J partial is scaled back by 4.
            pair_partial = -0.25 * spin_delta * float(j_column @ working)
            pair_delta = 4.0 * pair_partial

            # The hardware-style normalized h partial is scaled back by 2.
            bias_partial = -0.5 * spin_delta * float(h_scaled[idx])
            bias_delta = 2.0 * bias_partial

            delta_energy += pair_delta + bias_delta
            working[idx] = curr[idx]

    return float(delta_energy)


def update_hamiltonian_energy(
    previous_energy: float,
    previous_spins: np.ndarray,
    current_spins: np.ndarray,
    j_matrix: np.ndarray,
    h_vector: np.ndarray,
    scaling_factor: float = 4.0,
) -> float:
    """Update energy from the previous state using the incremental delta.

    Args:
        previous_energy: Energy of the previous state.
        previous_spins: Previous spin vector in {-1, +1}, shape (N,).
        current_spins: Current spin vector in {-1, +1}, shape (N,).
        j_matrix: Coupling matrix, shape (N, N).
        h_vector: Bias vector, shape (N,).
        scaling_factor: Scaling applied to h_vector.

    Returns:
        Updated energy for the current state.
    """
    delta = hamiltonian_energy_delta(
        previous_spins=previous_spins,
        current_spins=current_spins,
        j_matrix=j_matrix,
        h_vector=h_vector,
        scaling_factor=scaling_factor,
    )
    return float(previous_energy + delta)


def compute_case_energy(
    case: EarlyExitCaseData,
    state_bits: np.ndarray | None = None,
    scaling_factor: float = 4.0,
    include_offset: bool = True,
) -> np.ndarray:
    """Compute Hamiltonian energy for all states in a case.
    
    Args:
        case: EarlyExitCaseData containing J matrix and h vector.
        state_bits: Binary state array with shape (M, N) or None to use states_out.
                    If None, uses case.states_out_bits.
        scaling_factor: Scaling applied to h_vector (default 4.0).
        include_offset: If False, omit the model offset and return raw energy.
    
    Returns:
        Energy array of shape (M,) for M states.
    """
    if state_bits is None:
        state_bits = case.states_out_bits
    
    # Convert bits {0,1} to spins {-1, +1}
    spins = bits_to_spins(state_bits)
    
    # Compute Hamiltonian with offset from case
    return hamiltonian_energy(
        spins, 
        case.j_matrix_nibble, 
        case.h_vector_nibble, 
        scaling_factor,
        offset=case.offset if include_offset else 0.0,
    )


def compute_case_energy_incremental(
    case: EarlyExitCaseData,
    state_bits: np.ndarray | None = None,
    scaling_factor: float = 4.0,
    include_offset: bool = True,
) -> np.ndarray:
    """Compute case energy with a first full evaluation and incremental updates.

    The first state is evaluated with the full Hamiltonian. Every following state
    is updated from the previous energy using only the spins that changed.

    Args:
        case: EarlyExitCaseData containing J matrix and h vector.
        state_bits: Binary state array with shape (M, N) or None to use states_out.
        scaling_factor: Scaling applied to h_vector.
        include_offset: If False, omit the model offset and return raw energy.

    Returns:
        Energy array of shape (M,) for M states.
    """
    if state_bits is None:
        state_bits = case.states_out_bits

    spins = bits_to_spins(state_bits)
    if spins.ndim != 2:
        raise ValueError(f"state_bits must be 2D, got shape {state_bits.shape}")

    energies = np.empty(spins.shape[0], dtype=np.float64)
    energies[0] = hamiltonian_energy(
        spins[0],
        case.j_matrix_nibble,
        case.h_vector_nibble,
        scaling_factor,
        offset=case.offset if include_offset else 0.0,
    )

    for idx in range(1, spins.shape[0]):
        energies[idx] = update_hamiltonian_energy(
            energies[idx - 1],
            spins[idx - 1],
            spins[idx],
            case.j_matrix_nibble,
            case.h_vector_nibble,
            scaling_factor,
        )

    return energies


def compute_case_energy_trace(
    case: EarlyExitCaseData,
    state_bits: np.ndarray | None = None,
    scaling_factor: float = 4.0,
    include_offset: bool = True,
    num_banks: int = 4,
    parallelism: int = 4,
) -> dict[str, object]:
    """Return a detailed per-cycle trace of the incremental energy calculation.

    The returned trace is useful when you want to inspect the energy after each
    iteration cycle, not just the final value. Each step records the updated
    energy, the delta from the previous step, the changed columns, and the
    banked access batches used to mimic the hardware fetch order.

    Args:
        case: EarlyExitCaseData containing J matrix and h vector.
        state_bits: Binary state array with shape (M, N) or None to use states_out.
        scaling_factor: Scaling applied to h_vector.
        include_offset: If False, omit the model offset and return raw energy.
        num_banks: Number of memory banks in the hardware mapping.
        parallelism: Number of columns fetched per batch.

    Returns:
        A dictionary with keys:
        - "energies": np.ndarray of shape (M,)
        - "deltas": np.ndarray of shape (M,), first entry is 0
        - "changed_columns": list[np.ndarray]
        - "bank_batches": list[list[dict[str, np.ndarray | int]]]
    """
    if state_bits is None:
        state_bits = case.states_out_bits

    spins = bits_to_spins(state_bits)
    if spins.ndim != 2:
        raise ValueError(f"state_bits must be 2D, got shape {state_bits.shape}")

    num_steps = spins.shape[0]
    energies = np.empty(num_steps, dtype=np.float64)
    deltas = np.zeros(num_steps, dtype=np.float64)
    changed_columns_trace: list[np.ndarray] = []
    cycle_batches_trace: list[list[dict[str, np.ndarray | int]]] = []

    energies[0] = hamiltonian_energy(
        spins[0],
        case.j_matrix_nibble,
        case.h_vector_nibble,
        scaling_factor,
        offset=case.offset if include_offset else 0.0,
    )
    changed_columns_trace.append(np.array([], dtype=np.int64))
    cycle_batches_trace.append([])

    for idx in range(1, num_steps):
        changed_columns = changed_spin_indices(state_bits[idx - 1], state_bits[idx])
        cycle_batches = schedule_changed_columns_by_cycle(
            changed_columns,
            num_banks=num_banks,
        )

        delta = hamiltonian_energy_delta(
            spins[idx - 1],
            spins[idx],
            case.j_matrix_nibble,
            case.h_vector_nibble,
            scaling_factor,
        )

        energies[idx] = energies[idx - 1] + delta
        deltas[idx] = delta
        changed_columns_trace.append(changed_columns)
        cycle_batches_trace.append(cycle_batches)

    return {
        "energies": energies,
        "deltas": deltas,
        "changed_columns": changed_columns_trace,
        "cycle_batches": cycle_batches_trace,
        "bank_batches": cycle_batches_trace,
    }


def compute_sigma_delta_cycle_trace(
    previous_bits: np.ndarray,
    current_bits: np.ndarray,
    previous_energy: float,
    j_matrix: np.ndarray,
    h_vector: np.ndarray,
    scaling_factor: float = 4.0,
    num_banks: int = 4,
    parallelism: int = 4,
) -> dict[str, object]:
    """Trace per-fetch-cycle delta energy for one sigma transition.

    A cycle in this trace corresponds to one batch fetch (up to `parallelism`
    columns) from the bank scheduler.

    Args:
        previous_bits: Previous sigma bits, shape (N,).
        current_bits: Current sigma bits, shape (N,).
        previous_energy: Energy of the previous sigma.
        j_matrix: Coupling matrix, shape (N, N).
        h_vector: Bias vector, shape (N,).
        scaling_factor: Scaling applied to h_vector.
        num_banks: Number of memory banks.
        parallelism: Number of columns fetched per cycle.

    Returns:
        Dictionary with:
        - "cycle_energies": np.ndarray, energy after each fetch cycle
        - "cycle_deltas": np.ndarray, delta added at each fetch cycle
        - "changed_columns": np.ndarray
        - "cycle_batches": list of cycle dicts
    """
    prev_bits = np.asarray(previous_bits)
    curr_bits = np.asarray(current_bits)
    if prev_bits.shape != curr_bits.shape:
        raise ValueError(f"bit vectors must have same shape, got {prev_bits.shape} and {curr_bits.shape}")
    if prev_bits.ndim != 1:
        raise ValueError(f"bit vectors must be 1D, got shape {prev_bits.shape}")

    prev = bits_to_spins(prev_bits).astype(np.float64)
    curr = bits_to_spins(curr_bits).astype(np.float64)
    j = np.asarray(j_matrix, dtype=np.float64)
    h_scaled = np.asarray(h_vector, dtype=np.float64) * scaling_factor

    changed_columns = changed_spin_indices(prev_bits, curr_bits)
    cycle_batches = schedule_changed_columns_by_cycle(
        changed_columns,
        num_banks=num_banks,
    )

    working = prev.copy()
    energy = float(previous_energy)
    cycle_energies: list[float] = [energy]
    cycle_deltas: list[float] = [0.0]

    for cycle in cycle_batches:
        batch_delta = 0.0
        for idx in cycle["columns"]:
            spin_delta = curr[idx] - working[idx]
            j_column = j[:, idx]

            pair_partial = -0.25 * spin_delta * float(j_column @ working)
            pair_delta = 4.0 * pair_partial

            bias_partial = -0.5 * spin_delta * float(h_scaled[idx])
            bias_delta = 2.0 * bias_partial

            batch_delta += pair_delta + bias_delta
            working[idx] = curr[idx]

        energy += batch_delta
        cycle_deltas.append(float(batch_delta))
        cycle_energies.append(float(energy))

    return {
        "cycle_energies": np.asarray(cycle_energies, dtype=np.float64),
        "cycle_deltas": np.asarray(cycle_deltas, dtype=np.float64),
        "changed_columns": changed_columns,
        "cycle_batches": cycle_batches,
        "bank_batches": cycle_batches,
    }


def compute_case_single_sigma_cycle_trace(
    case: EarlyExitCaseData,
    transition_index: int,
    state_bits: np.ndarray | None = None,
    scaling_factor: float = 4.0,
    include_offset: bool = False,
    num_banks: int = 4,
    parallelism: int = 4,
) -> dict[str, object]:
    """Build a per-fetch-cycle trace for one sigma transition in a case.

    Args:
        case: Loaded case data.
        transition_index: Transition k means sigma[k-1] -> sigma[k], must be >= 1.
        state_bits: Optional state matrix (M, N). Defaults to case.states_out_bits.
        scaling_factor: Scaling applied to h_vector.
        include_offset: Whether previous sigma energy includes the model offset.
        num_banks: Number of memory banks.
        parallelism: Number of columns fetched per cycle.

    Returns:
        Trace dictionary from compute_sigma_delta_cycle_trace with two extra keys:
        - "transition_index"
        - "previous_energy"
    """
    if state_bits is None:
        state_bits = case.states_out_bits

    states = np.asarray(state_bits)
    if states.ndim != 2:
        raise ValueError(f"state_bits must be 2D, got shape {states.shape}")
    if transition_index < 1 or transition_index >= states.shape[0]:
        raise ValueError(
            f"transition_index must be in [1, {states.shape[0] - 1}], got {transition_index}"
        )

    prev_bits = states[transition_index - 1]
    curr_bits = states[transition_index]
    prev_spins = bits_to_spins(prev_bits)

    previous_energy = hamiltonian_energy(
        prev_spins,
        case.j_matrix_nibble,
        case.h_vector_nibble,
        scaling_factor,
        offset=case.offset if include_offset else 0.0,
    )

    trace = compute_sigma_delta_cycle_trace(
        previous_bits=prev_bits,
        current_bits=curr_bits,
        previous_energy=float(previous_energy),
        j_matrix=case.j_matrix_nibble,
        h_vector=case.h_vector_nibble,
        scaling_factor=scaling_factor,
        num_banks=num_banks,
        parallelism=parallelism,
    )
    trace["transition_index"] = transition_index
    trace["previous_energy"] = float(previous_energy)
    return trace


def compute_case_early_stop_accuracy(
    case: EarlyExitCaseData,
    state_bits: np.ndarray | None = None,
    scaling_factor: float = 4.0,
    include_offset: bool = False,
    num_banks: int = 4,
    parallelism: int = 4,
    mode: Literal["per_transition", "propagated", "propagated_with_refresh"] = "per_transition",
    refresh_interval: int | None = None,
) -> dict[str, np.ndarray]:
    """Compute accuracy drop when stopping after a limited fetch-cycle budget.

        Modes:
        - per_transition: each transition is evaluated independently
        - propagated: early-stopped energy is propagated as baseline to the next
            transition, so error can accumulate across iterations
        - propagated_with_refresh: same as propagated, but the baseline is
            periodically refreshed with the full energy every refresh_interval
            transitions

    Args:
        case: Loaded case data.
        state_bits: Optional state matrix (M, N). Defaults to case.states_out_bits.
        scaling_factor: Scaling applied to h_vector.
        include_offset: Whether energies include the model offset.
        num_banks: Number of memory banks.
        parallelism: Number of columns fetched per cycle.
        mode: Accuracy mode, either "per_transition" or "propagated".
        refresh_interval: Required when mode is "propagated_with_refresh".

    Returns:
        Dictionary with arrays keyed by:
        - "cycle_budget": 0..max_cycles
        - "mae": mean absolute error over transitions
        - "rmse": root mean square error over transitions
        - "max_abs_error": max absolute error over transitions
        - "mean_rel_error": mean relative error over transitions
        - "num_transitions": scalar array with transition count
    """
    if state_bits is None:
        state_bits = case.states_out_bits

    states = np.asarray(state_bits)
    if states.ndim != 2:
        raise ValueError(f"state_bits must be 2D, got shape {states.shape}")
    if states.shape[0] < 2:
        raise ValueError("Need at least two states to evaluate early-stop accuracy")

    if mode not in ("per_transition", "propagated", "propagated_with_refresh"):
        raise ValueError(f"Unsupported mode: {mode}")
    if mode == "propagated_with_refresh":
        if refresh_interval is None:
            raise ValueError("refresh_interval is required for propagated_with_refresh mode")
        if refresh_interval <= 0:
            raise ValueError("refresh_interval must be positive")

    transition_traces: list[dict[str, object]] = []
    max_cycles = 0
    for transition_index in range(1, states.shape[0]):
        trace = compute_case_single_sigma_cycle_trace(
            case=case,
            transition_index=transition_index,
            state_bits=states,
            scaling_factor=scaling_factor,
            include_offset=include_offset,
            num_banks=num_banks,
            parallelism=parallelism,
        )
        transition_traces.append(trace)
        max_cycles = max(max_cycles, int(len(trace["cycle_energies"]) - 1))

    full_energies = compute_case_energy(
        case=case,
        state_bits=states,
        scaling_factor=scaling_factor,
        include_offset=include_offset,
    )

    budgets = np.arange(max_cycles + 1, dtype=np.int64)
    mae = np.zeros_like(budgets, dtype=np.float64)
    rmse = np.zeros_like(budgets, dtype=np.float64)
    max_abs_error = np.zeros_like(budgets, dtype=np.float64)
    mean_rel_error = np.zeros_like(budgets, dtype=np.float64)

    for b_idx, budget in enumerate(budgets):
        abs_errors: list[float] = []
        rel_errors: list[float] = []
        if mode == "per_transition":
            for trace in transition_traces:
                cycle_energies = np.asarray(trace["cycle_energies"], dtype=np.float64)
                final_energy = float(cycle_energies[-1])
                stop_idx = min(int(budget), int(len(cycle_energies) - 1))
                stopped_energy = float(cycle_energies[stop_idx])
                err = abs(stopped_energy - final_energy)
                abs_errors.append(err)
                denom = abs(final_energy)
                rel_errors.append(0.0 if denom == 0.0 else err / denom)
        elif mode == "propagated":
            approx_prev = float(full_energies[0])
            for t_idx, trace in enumerate(transition_traces, start=1):
                cycle_deltas = np.asarray(trace["cycle_deltas"], dtype=np.float64)
                stop_idx = min(int(budget), int(len(cycle_deltas) - 1))
                partial_delta = float(np.sum(cycle_deltas[1:stop_idx + 1]))
                approx_next = approx_prev + partial_delta

                target_energy = float(full_energies[t_idx])
                err = abs(approx_next - target_energy)
                abs_errors.append(err)
                denom = abs(target_energy)
                rel_errors.append(0.0 if denom == 0.0 else err / denom)

                approx_prev = approx_next
        else:
            refresh = int(refresh_interval)
            approx_prev = float(full_energies[0])
            for t_idx, trace in enumerate(transition_traces, start=1):
                if t_idx > 1 and (t_idx - 1) % refresh == 0:
                    approx_prev = float(full_energies[t_idx - 1])

                cycle_deltas = np.asarray(trace["cycle_deltas"], dtype=np.float64)
                stop_idx = min(int(budget), int(len(cycle_deltas) - 1))
                partial_delta = float(np.sum(cycle_deltas[1:stop_idx + 1]))
                approx_next = approx_prev + partial_delta

                target_energy = float(full_energies[t_idx])
                err = abs(approx_next - target_energy)
                abs_errors.append(err)
                denom = abs(target_energy)
                rel_errors.append(0.0 if denom == 0.0 else err / denom)

                approx_prev = approx_next

        abs_arr = np.asarray(abs_errors, dtype=np.float64)
        rel_arr = np.asarray(rel_errors, dtype=np.float64)
        mae[b_idx] = float(np.mean(abs_arr))
        rmse[b_idx] = float(np.sqrt(np.mean(abs_arr * abs_arr)))
        max_abs_error[b_idx] = float(np.max(abs_arr))
        mean_rel_error[b_idx] = float(np.mean(rel_arr))

    return {
        "cycle_budget": budgets,
        "mae": mae,
        "rmse": rmse,
        "max_abs_error": max_abs_error,
        "mean_rel_error": mean_rel_error,
        "num_transitions": np.asarray([len(transition_traces)], dtype=np.int64),
        "mode": np.asarray(
            [
                0
                if mode == "per_transition"
                else 1
                if mode == "propagated"
                else 2
            ],
            dtype=np.int64,
        ),
        "refresh_interval": np.asarray([0 if refresh_interval is None else refresh_interval], dtype=np.int64),
    }


def compute_case_transition_cycle_counts(
    case: EarlyExitCaseData,
    state_bits: np.ndarray | None = None,
    num_banks: int = 4,
    parallelism: int = 4,
) -> dict[str, np.ndarray]:
    """Count how many internal fetch cycles each transition needs.

    The count is based on the banked schedule of changed columns. If only four
    bits change and parallelism is four, the transition needs one cycle.

    Args:
        case: Loaded case data.
        state_bits: Optional state matrix (M, N). Defaults to case.states_out_bits.
        num_banks: Number of memory banks.
        parallelism: Number of columns fetched per cycle.

    Returns:
        Dictionary with:
        - "transition_index": 1..M-1
        - "changed_bits": number of changed spin bits per transition
        - "cycle_count": internal fetch cycles per transition
        - "cycle_count": internal fetch cycles per transition
    """
    if state_bits is None:
        state_bits = case.states_out_bits

    states = np.asarray(state_bits)
    if states.ndim != 2:
        raise ValueError(f"state_bits must be 2D, got shape {states.shape}")
    if states.shape[0] < 2:
        raise ValueError("Need at least two states to evaluate cycle counts")

    transition_indices = np.arange(1, states.shape[0], dtype=np.int64)
    changed_bits = np.zeros_like(transition_indices, dtype=np.int64)
    cycle_count = np.zeros_like(transition_indices, dtype=np.int64)
    cycle_count = np.zeros_like(transition_indices, dtype=np.int64)

    for out_idx, transition_index in enumerate(transition_indices):
        prev_bits = states[transition_index - 1]
        curr_bits = states[transition_index]
        changed = changed_spin_indices(prev_bits, curr_bits)
        cycles = schedule_changed_columns_by_cycle(
            changed,
            num_banks=num_banks,
        )

        changed_bits[out_idx] = int(changed.size)
        cycle_count[out_idx] = int(len(cycles))

    return {
        "transition_index": transition_indices,
        "changed_bits": changed_bits,
        "cycle_count": cycle_count,
    }


def energy_error(
    computed_energy: np.ndarray,
    reference_energy: np.ndarray,
) -> np.ndarray:
    """Compute absolute energy error.
    
    Args:
        computed_energy: Computed energy values, shape (M,).
        reference_energy: Reference/true energy values, shape (M,).
    
    Returns:
        Absolute error array of shape (M,).
    """
    return np.abs(computed_energy - reference_energy)


def relative_energy_error(
    computed_energy: np.ndarray,
    reference_energy: np.ndarray,
) -> np.ndarray:
    """Compute relative energy error.
    
    Args:
        computed_energy: Computed energy values, shape (M,).
        reference_energy: Reference/true energy values, shape (M,).
    
    Returns:
        Relative error array of shape (M,). Undefined where reference is 0.
    """
    ref = np.asarray(reference_energy, dtype=np.float64)
    with np.errstate(divide='ignore', invalid='ignore'):
        rel_err = np.abs(computed_energy - ref) / np.abs(ref)
    return rel_err
