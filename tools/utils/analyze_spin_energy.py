#!/usr/bin/env python3
# Copyright 2026 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Analyze spin/energy traces against banked J/hbias/hscaling CDE files.

This script reconstructs the 256x256 J matrix from the 16 weight SRAM .cde
files, reads 4 hbias/hscaling SRAM .cde files (one per lane), and compares
the DUT energy output in spin_energy_log.csv against a software reference.

Current mapping assumptions:
- 16 banks = 4 lanes x 4 banks/lane
- bank = lane*4 + bank_in_lane
- lane = column % 4
- column = lane + 4*word
- each 256-bit word stores 64 signed 4-bit rows for one column
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from pathlib import Path
from statistics import mean


@dataclass(frozen=True)
class TraceRow:
    time_ns: int
    cycle: int
    test_id: int
    spin_hex: str
    spin_ones: int
    energy_dut: int


@dataclass(frozen=True)
class ComparisonRow:
    time_ns: int
    cycle: int
    test_id: int
    spin_hex: str
    spin_ones: int
    energy_dut: int
    energy_ref: int
    diff: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze spin/energy traces against CDE files")
    parser.add_argument(
        "--cde-dir",
        type=Path,
        required=True,
        help="Directory containing bank CDE files",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        required=True,
        help="Simulation CSV written by the testbench",
    )
    parser.add_argument(
        "--prefix",
        default="TS1N28HPCPUHDHVTB64X256M1SWBSO_initial_bank",
        help="CDE file prefix before 2-digit bank index",
    )
    parser.add_argument(
        "--hbias-scaling-prefix",
        default="TS1N28HPCPUHDHVTB64X256M1SWBSO_hbias_scaling_bank",
        help="hbias/scaling CDE file prefix before 2-digit bank index",
    )
    parser.add_argument("--banks", type=int, default=16, help="Number of CDE bank files")
    parser.add_argument("--hbias-scaling-banks", type=int, default=4, help="Number of hbias/scaling bank files")
    parser.add_argument("--words", type=int, default=64, help="Words per CDE file")
    parser.add_argument("--bits", type=int, default=256, help="Bits per CDE word")
    parser.add_argument("--j-size", type=int, default=256, help="J matrix dimension")
    parser.add_argument("--hbias-bits", type=int, default=4, help="Signed hbias bit-width")
    parser.add_argument("--hscaling-bits", type=int, default=4, help="Unsigned hscaling bit-width")
    parser.add_argument("--parallelism", type=int, default=4, help="Lane count used for column mapping")
    parser.add_argument(
        "--out-csv",
        type=Path,
        default=None,
        help="Optional CSV for per-transaction DUT/reference comparison",
    )
    parser.add_argument(
        "--summary-json",
        type=Path,
        default=None,
        help="Optional JSON summary file",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return non-zero if any mismatch is found",
    )
    return parser.parse_args()


def read_bank_lines(cde_dir: Path, prefix: str, banks: int, words: int, hex_chars: int) -> list[list[str]]:
    bank_lines: list[list[str]] = []
    for bank in range(banks):
        file_path = cde_dir / f"{prefix}{bank:02d}.cde"
        if not file_path.is_file():
            raise FileNotFoundError(f"Missing CDE file: {file_path}")

        lines = [line.strip().lower() for line in file_path.read_text(encoding="ascii").splitlines() if line.strip()]
        if len(lines) != words:
            raise ValueError(f"{file_path} has {len(lines)} non-empty lines, expected {words}")

        for idx, line in enumerate(lines, start=1):
            if len(line) != hex_chars:
                raise ValueError(f"{file_path}:{idx} has {len(line)} hex chars, expected {hex_chars}")
            if any(ch not in "0123456789abcdef" for ch in line):
                raise ValueError(f"{file_path}:{idx} contains non-hex characters")

        bank_lines.append(lines)
    return bank_lines


def reconstruct_j_matrix(bank_lines: list[list[str]], words: int, j_size: int) -> list[list[int]]:
    j_matrix = [[0 for _ in range(j_size)] for _ in range(j_size)]

    for bank in range(len(bank_lines)):
        lane = bank // 4
        bank_in_lane = bank % 4
        row_base = bank_in_lane * 64

        for word_idx in range(words):
            column = lane + 4 * word_idx
            if column >= j_size:
                continue

            word_val = int(bank_lines[bank][word_idx], 16)
            for row_off in range(64):
                row = row_base + row_off
                if row < j_size:
                    j_matrix[row][column] = (word_val >> (row_off * 4)) & 0xF

    return j_matrix


def signed4(nibble: int) -> int:
    return nibble - 16 if (nibble & 0x8) else nibble


def signed_from_bits(value: int, bits: int) -> int:
    sign_bit = 1 << (bits - 1)
    full = 1 << bits
    return value - full if (value & sign_bit) else value


def scale_hbias_ref(hbias_raw: int, hscaling_raw: int) -> int:
    if hscaling_raw == 1:
        return hbias_raw
    if hscaling_raw == 2:
        return hbias_raw << 1
    if hscaling_raw == 4:
        return hbias_raw << 2
    if hscaling_raw == 8:
        return hbias_raw << 3
    if hscaling_raw == 16:
        return hbias_raw << 4
    return hbias_raw


def reconstruct_hbias_hscaling(
    hs_bank_lines: list[list[str]],
    words: int,
    j_size: int,
    hbias_bits: int,
    hscaling_bits: int,
    parallelism: int,
) -> tuple[list[int], list[int]]:
    hbias_vec = [0 for _ in range(j_size)]
    hscaling_vec = [1 for _ in range(j_size)]
    hbias_mask = (1 << hbias_bits) - 1
    hscaling_mask = (1 << hscaling_bits) - 1

    for lane in range(len(hs_bank_lines)):
        for word_idx in range(words):
            col = lane + parallelism * word_idx
            if col >= j_size:
                continue
            word_val = int(hs_bank_lines[lane][word_idx], 16)
            hbias_raw = word_val & hbias_mask
            hscaling_raw = (word_val >> hbias_bits) & hscaling_mask
            hbias_vec[col] = signed_from_bits(hbias_raw, hbias_bits)
            hscaling_vec[col] = hscaling_raw

    return hbias_vec, hscaling_vec


def spin_bit(spin_value: int, idx: int) -> int:
    return 1 if ((spin_value >> idx) & 1) else -1


def compute_reference_energy(
    j_matrix: list[list[int]],
    hbias_vec: list[int],
    hscaling_vec: list[int],
    spin_hex: str,
) -> int:
    spin_value = int(spin_hex, 16)
    j_size = len(j_matrix)
    total = 0

    for col in range(j_size):
        s_col = spin_bit(spin_value, col)
        col_dot = 0
        for row in range(j_size):
            if row == col:
                continue
            j_val = signed4(j_matrix[row][col])
            if j_val == 0:
                continue
            s_row = spin_bit(spin_value, row)
            col_dot += j_val * s_row

        hbias_scaled = scale_hbias_ref(hbias_vec[col], hscaling_vec[col])
        total += s_col * (col_dot + hbias_scaled)

    return total


def parse_trace_csv(csv_path: Path) -> list[TraceRow]:
    rows: list[TraceRow] = []
    with csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        required = {"time_ns", "cycle", "test_id", "spin_hex", "spin_ones", "energy"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"CSV is missing required columns: {sorted(missing)}")

        for row in reader:
            rows.append(
                TraceRow(
                    time_ns=int(row["time_ns"]),
                    cycle=int(row["cycle"]),
                    test_id=int(row["test_id"]),
                    spin_hex=row["spin_hex"].strip().lower(),
                    spin_ones=int(row["spin_ones"]),
                    energy_dut=int(row["energy"]),
                )
            )
    return rows


def analyze(
    cde_dir: Path,
    csv_path: Path,
    prefix: str,
    hbias_scaling_prefix: str,
    banks: int,
    hbias_scaling_banks: int,
    words: int,
    bits: int,
    j_size: int,
    hbias_bits: int,
    hscaling_bits: int,
    parallelism: int,
) -> tuple[list[ComparisonRow], dict[str, int | float]]:
    hex_chars = bits // 4
    if bits % 4 != 0:
        raise ValueError("bits must be a multiple of 4")

    bank_lines = read_bank_lines(cde_dir, prefix, banks, words, hex_chars)
    hs_bank_lines = read_bank_lines(cde_dir, hbias_scaling_prefix, hbias_scaling_banks, words, hex_chars)
    j_matrix = reconstruct_j_matrix(bank_lines, words, j_size)
    hbias_vec, hscaling_vec = reconstruct_hbias_hscaling(
        hs_bank_lines=hs_bank_lines,
        words=words,
        j_size=j_size,
        hbias_bits=hbias_bits,
        hscaling_bits=hscaling_bits,
        parallelism=parallelism,
    )
    trace_rows = parse_trace_csv(csv_path)

    comparisons: list[ComparisonRow] = []
    diffs: list[int] = []

    for row in trace_rows:
        energy_ref = compute_reference_energy(j_matrix, hbias_vec, hscaling_vec, row.spin_hex)
        diff = row.energy_dut - energy_ref
        comparisons.append(
            ComparisonRow(
                time_ns=row.time_ns,
                cycle=row.cycle,
                test_id=row.test_id,
                spin_hex=row.spin_hex,
                spin_ones=row.spin_ones,
                energy_dut=row.energy_dut,
                energy_ref=energy_ref,
                diff=diff,
            )
        )
        diffs.append(abs(diff))

    summary: dict[str, int | float] = {
        "num_rows": len(comparisons),
        "mismatches": sum(1 for item in comparisons if item.diff != 0),
        "max_abs_diff": max(diffs) if diffs else 0,
        "mean_abs_diff": mean(diffs) if diffs else 0.0,
        "first_test_id": comparisons[0].test_id if comparisons else -1,
        "last_test_id": comparisons[-1].test_id if comparisons else -1,
    }
    return comparisons, summary


def write_comparison_csv(out_csv: Path, comparisons: list[ComparisonRow]) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time_ns", "cycle", "test_id", "spin_hex", "spin_ones", "energy_dut", "energy_ref", "diff", "abs_diff"])
        for row in comparisons:
            writer.writerow([
                row.time_ns,
                row.cycle,
                row.test_id,
                row.spin_hex,
                row.spin_ones,
                row.energy_dut,
                row.energy_ref,
                row.diff,
                abs(row.diff),
            ])


def main() -> int:
    args = parse_args()
    comparisons, summary = analyze(
        cde_dir=args.cde_dir,
        csv_path=args.csv,
        prefix=args.prefix,
        hbias_scaling_prefix=args.hbias_scaling_prefix,
        banks=args.banks,
        hbias_scaling_banks=args.hbias_scaling_banks,
        words=args.words,
        bits=args.bits,
        j_size=args.j_size,
        hbias_bits=args.hbias_bits,
        hscaling_bits=args.hscaling_bits,
        parallelism=args.parallelism,
    )

    if args.out_csv is not None:
        write_comparison_csv(args.out_csv, comparisons)
        print(f"[analyze] wrote comparison CSV: {args.out_csv}")

    if args.summary_json is not None:
        args.summary_json.parent.mkdir(parents=True, exist_ok=True)
        with args.summary_json.open("w", encoding="utf-8", newline="") as f:
            json.dump(summary, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"[analyze] wrote summary JSON: {args.summary_json}")

    print(
        f"[analyze] rows={summary['num_rows']} mismatches={summary['mismatches']} "
        f"max_abs_diff={summary['max_abs_diff']} mean_abs_diff={summary['mean_abs_diff']:.3f}"
    )

    if comparisons and comparisons[0].diff != 0:
        first = comparisons[0]
        print(
            f"[analyze] first mismatch test_id={first.test_id} dut={first.energy_dut} "
            f"ref={first.energy_ref} diff={first.diff}"
        )

    if args.strict and summary["mismatches"] != 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
