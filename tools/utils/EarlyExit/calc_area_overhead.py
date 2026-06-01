#!/usr/bin/env python3
"""Calculate area overhead from a Genus area report.

The script reads a Genus ``report area`` output, sums a baseline instance set,
and reports the extra area inside the DUS block as ``DUS total - baseline``.
"""
from __future__ import annotations

import argparse
from pathlib import Path


DEFAULT_OVERHEAD_INSTANCES = [
    "gen_find_all_ones_0_u_find_all_ones",
    "gen_popcount_parallel_0_u_popcount_flipped",
    "u_spin_flipped",
    "u_find_max",
]

DEFAULT_BASELINE_INSTANCES = [
    "partial_energy_calc_inst_0_u_partial_energy_calc",
    "partial_energy_calc_inst_1_u_partial_energy_calc",
    "partial_energy_calc_inst_2_u_partial_energy_calc",
    "partial_energy_calc_inst_3_u_partial_energy_calc",
    "u_accumulator",
    "u_spin_cache",
    "u_logic_ctrl",
    "u_step_counter_diff",
    "u_step_counter_sram",
]


def parse_area_report(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        parts = raw_line.split()
        if len(parts) == 5 and parts[1].isdigit():
            instance, module = parts[0], ""
            cell_count, cell_area, net_area, total_area = parts[1:]
        elif len(parts) >= 6 and parts[2].isdigit():
            instance, module = parts[0], parts[1]
            cell_count, cell_area, net_area, total_area = parts[2:6]
        else:
            continue
        rows.append(
            {
                "instance": instance,
                "module": module,
                "cell_count": int(cell_count),
                "cell_area": float(cell_area),
                "net_area": float(net_area),
                "total_area": float(total_area),
            }
        )
    return rows


def find_row(rows: list[dict[str, object]], instance: str) -> dict[str, object]:
    for row in rows:
        if row["instance"] == instance:
            return row
    raise SystemExit(f"Instance not found in report: {instance}")


def sum_rows(rows: list[dict[str, object]], instances: list[str]) -> tuple[list[dict[str, object]], float]:
    selected = [find_row(rows, instance) for instance in instances]
    return selected, sum(float(row["total_area"]) for row in selected)


def format_area(value: float) -> str:
    return f"{value:.3f}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Calculate area overhead from a Genus area report.")
    parser.add_argument("report", type=Path, help="Path to the Genus area report")
    parser.add_argument(
        "--baseline-instance",
        action="append",
        default=None,
        help="Instance name to include in the baseline; repeat for multiple instances",
    )
    parser.add_argument(
        "--overhead-instance",
        action="append",
        default=None,
        help="Instance name to count as overhead; repeat for multiple instances",
    )
    args = parser.parse_args()
    baseline_instances = args.baseline_instance or DEFAULT_BASELINE_INSTANCES
    overhead_instances = args.overhead_instance or DEFAULT_OVERHEAD_INSTANCES

    rows = parse_area_report(args.report)
    if not rows:
        raise SystemExit(f"No area rows found in report: {args.report}")

    baseline_rows, baseline_area = sum_rows(rows, baseline_instances)
    overhead_rows, overhead_total = sum_rows(rows, overhead_instances)
    design_row = next((row for row in rows if row["module"] == ""), None)
    dus_row = next((row for row in rows if row["instance"] == "DUS"), None)

    print(f"Report: {args.report}")
    print("Baseline blocks:")
    for row in baseline_rows:
        print(f"  - {row['instance']} ({row['module']}) = {format_area(float(row['total_area']))}")
    print(f"Baseline total = {format_area(baseline_area)}")
    print("Overhead blocks:")
    for row in overhead_rows:
        print(f"  - {row['instance']} ({row['module']}) = {format_area(float(row['total_area']))}")
    print(f"Overhead total = {format_area(overhead_total)}")
    print(f"Overhead / baseline = {overhead_total / baseline_area * 100.0:.2f}%")
    if dus_row is not None:
        dus_area = float(dus_row["total_area"])
        print(f"DUS total: {dus_row['instance']} ({dus_row['module']}) = {format_area(dus_area)}")
        extra_area = dus_area - baseline_area
        print(f"DUS minus baseline = {format_area(extra_area)}")
        print(f"DUS minus baseline / DUS total = {extra_area / dus_area * 100.0:.2f}%")
        print(f"DUS minus baseline / baseline total = {extra_area / baseline_area * 100.0:.2f}%")
    elif design_row is not None:
        design_area = float(design_row["total_area"])
        print(f"Design total: {design_row['instance']} = {format_area(design_area)}")
        extra_area = design_area - baseline_area
        print(f"Design minus baseline = {format_area(extra_area)}")
        print(f"Design minus baseline / design total = {extra_area / design_area * 100.0:.2f}%")
        print(f"Design minus baseline / baseline total = {extra_area / baseline_area * 100.0:.2f}%")


if __name__ == "__main__":
    main()