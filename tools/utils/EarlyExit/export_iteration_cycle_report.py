#!/usr/bin/env python3
"""Export per-iteration changed spins and fetch-cycle counts.

The compact report records, for each state transition in cases 1 and 2:
- the transition index
- the required fetch cycles for the no-replication case

It also writes a JSON summary with totals across all iterations.
"""
from __future__ import annotations

from collections.abc import Iterable
from csv import DictWriter
import json
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.utils.EarlyExit.data_loader import EarlyExitDataLoader
from tools.utils.EarlyExit.energy_calc import changed_spin_indices, compute_case_transition_cycle_counts

NO_REPLICATION_STRATEGY = "1x"
COMPACT_COLUMNS = ["case_id", "transition_idx", "required_cycles_no_replication"]


def _format_indices(values: Iterable[int]) -> str:
    return "[" + ", ".join(str(int(v)) for v in values) + "]"


def _cycle_count(changed_cols: np.ndarray, strategy: str) -> int:
    from tools.utils.EarlyExit.bandwidth_replication_model import schedule_changed_columns_replicated

    cycles = schedule_changed_columns_replicated(changed_cols, num_banks=4, replication_factor=strategy)
    return len(cycles)


def build_case_rows(case_id: int, case_data) -> tuple[list[dict[str, object]], dict[str, object], list[dict[str, object]]]:
    rows: list[dict[str, object]] = []
    compact_rows: list[dict[str, object]] = []
    total_no_replication_cycles = 0
    total_changed_spins = 0

    no_replication_cycle_counts = compute_case_transition_cycle_counts(case_data, memory_mode="banked")

    for transition_idx in range(1, case_data.states_out_bits.shape[0]):
        prev_bits = case_data.states_out_bits[transition_idx - 1]
        curr_bits = case_data.states_out_bits[transition_idx]
        changed_cols = changed_spin_indices(prev_bits, curr_bits)

        bank_counts = np.bincount(changed_cols % 4, minlength=4) if changed_cols.size else np.zeros(4, dtype=int)
        row = {
            "case_id": case_id,
            "transition_idx": transition_idx,
            "changed_spins": _format_indices(changed_cols),
            "changed_count": int(changed_cols.size),
            "bank0_changed": int(bank_counts[0]),
            "bank1_changed": int(bank_counts[1]),
            "bank2_changed": int(bank_counts[2]),
            "bank3_changed": int(bank_counts[3]),
            "lower_bound_cycles": int(np.ceil(changed_cols.size / 4.0)) if changed_cols.size else 0,
        }

        total_changed_spins += int(changed_cols.size)
        rows.append(row)

        required_cycles = int(no_replication_cycle_counts["cycle_count"][transition_idx - 1])
        compact_rows.append(
            {
                "case_id": case_id,
                "transition_idx": transition_idx,
                "required_cycles_no_replication": required_cycles,
            }
        )
        total_no_replication_cycles += required_cycles

    summary = {
        "case_id": case_id,
        "iterations": len(rows),
        "total_changed_spins": total_changed_spins,
        "mean_changed_spins": float(np.mean([r["changed_count"] for r in rows])) if rows else 0.0,
        "total_no_replication_cycles": total_no_replication_cycles,
        "mean_no_replication_cycles": float(np.mean([r["required_cycles_no_replication"] for r in compact_rows])) if compact_rows else 0.0,
    }
    return rows, summary, compact_rows


def main() -> None:
    loader = EarlyExitDataLoader(ROOT / "default")
    out_dir = ROOT / "tools" / "utils" / "EarlyExit" / "generated_reports"
    out_dir.mkdir(parents=True, exist_ok=True)

    combined_rows: list[dict[str, object]] = []
    combined_compact_rows: list[dict[str, object]] = []
    summaries: list[dict[str, object]] = []

    for case_id in (1, 2):
        case_data = loader.load_case(case_id)
        rows, summary, compact_rows = build_case_rows(case_id, case_data)
        combined_rows.extend(rows)
        combined_compact_rows.extend(compact_rows)
        summaries.append(summary)

        case_csv = out_dir / f"iteration_cycle_report_case{case_id}.csv"
        compact_case_csv = out_dir / f"iteration_cycle_required_cycles_case{case_id}.csv"
        case_json = out_dir / f"iteration_cycle_report_case{case_id}_summary.json"
        _write_csv(case_csv, rows)
        _write_csv(compact_case_csv, compact_rows)
        case_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    combined_summary = {
        "cases": summaries,
        "combined": {
            "iterations": sum(item["iterations"] for item in summaries),
            "total_changed_spins": sum(item["total_changed_spins"] for item in summaries),
            "total_no_replication_cycles": int(sum(item["total_no_replication_cycles"] for item in summaries)),
        },
    }

    combined_csv = out_dir / "iteration_cycle_report_all_cases.csv"
    compact_combined_csv = out_dir / "iteration_cycle_required_cycles_all_cases.csv"
    combined_json = out_dir / "iteration_cycle_report_all_cases_summary.json"
    _write_csv(combined_csv, combined_rows)
    _write_csv(compact_combined_csv, combined_compact_rows)
    combined_json.write_text(json.dumps(combined_summary, indent=2), encoding="utf-8")

    print(f"Wrote {combined_csv}")
    print(f"Wrote {compact_combined_csv}")
    print(f"Wrote {combined_json}")
    for summary in summaries:
        print(
            f"Case {summary['case_id']}: iterations={summary['iterations']}, "
            f"total_no_replication_cycles={summary['total_no_replication_cycles']}"
        )


def _write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return

    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
