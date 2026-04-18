# Copyright 2026 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Generate per-bank SRAM CDE initialization files.

Default output naming matches the TSMC 64x256 macro preload convention:
TS1N28HPCPUHDHVTB64X256M1SWBSO_initial_bank00.cde ... bank15.cde
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate banked SRAM .cde preload files")
    parser.add_argument(
        "--out-dir",
        type=Path,
        required=True,
        help="Directory where .cde files are generated",
    )
    parser.add_argument(
        "--prefix",
        default="TS1N28HPCPUHDHVTB64X256M1SWBSO_initial_bank",
        help="File prefix before 2-digit bank index",
    )
    parser.add_argument("--banks", type=int, default=16, help="Number of bank files")
    parser.add_argument("--start-bank", type=int, default=0, help="Starting bank index")
    parser.add_argument("--words", type=int, default=64, help="Words per bank file")
    parser.add_argument("--bits", type=int, default=256, help="Bits per word")
    parser.add_argument(
        "--mode",
        choices=["bank-nibble", "zeros", "ones", "random", "j-symmetric", "model-file"],
        default="bank-nibble",
        help="Initialization pattern mode",
    )
    parser.add_argument(
        "--model-file",
        type=Path,
        help="Path to model file with # J matrix and # h vector sections",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1,
        help="Random seed (used only in random mode)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing files",
    )
    parser.add_argument(
        "--j-size",
        type=int,
        default=256,
        help=(
            "Square J-matrix dimension for j-symmetric mode. "
            "Must satisfy j-size*4 == bits*banks/4 and j-size == words*4."
        ),
    )
    parser.add_argument(
        "--hbias-scaling-banks",
        type=int,
        default=4,
        help="Number of hbias/scaling bank files to generate (set 0 to disable)",
    )
    parser.add_argument(
        "--hbias-scaling-prefix",
        default="TS1N28HPCPUHDHVTB64X256M1SWBSO_hbias_scaling_bank",
        help="File prefix for hbias/scaling files before 2-digit bank index",
    )
    parser.add_argument(
        "--hbias-bits",
        type=int,
        default=4,
        help="Signed hbias bit-width packed at LSB of hbias/scaling word",
    )
    parser.add_argument(
        "--hscaling-bits",
        type=int,
        default=4,
        help="Unsigned hscaling bit-width packed above hbias",
    )
    parser.add_argument(
        "--parallelism",
        type=int,
        default=4,
        help="Lane count used for column mapping (column = lane + parallelism*word)",
    )
    return parser.parse_args()


def parse_model_file(file_path: Path) -> tuple[list[list[int]], list[int], float, float]:
    """Parse model file with sections: # J matrix, # h vector, # offset, # scaling_factor."""
    with file_path.open("r", encoding="ascii") as f:
        lines = [line.strip() for line in f]

    sections: dict[str, list[str]] = {}
    current = ""
    for line in lines:
        if not line:
            continue
        if line.startswith("#"):
            current = line[1:].strip().lower()
            sections[current] = []
        elif current:
            sections[current].append(line)

    if "j matrix" not in sections:
        raise ValueError("model file missing '# J matrix' section")

    j_mat: list[list[int]] = []
    for row_line in sections["j matrix"]:
        row = [int(tok, 2) & 0xF for tok in row_line.split()]
        j_mat.append(row)

    h_vec: list[int] = []
    if "h vector" in sections:
        for val_line in sections["h vector"]:
            h_vec.append(int(val_line, 2) & 0xF)

    offset = 0.0
    if "offset" in sections and sections["offset"]:
        offset = float(sections["offset"][0])

    scaling_factor = 1.0
    if "scaling_factor" in sections and sections["scaling_factor"]:
        scaling_factor = float(sections["scaling_factor"][0])

    return j_mat, h_vec, offset, scaling_factor


def random_j_nibble(rng: random.Random) -> int:
    """Return a random signed 4-bit value encoded as nibble, excluding zero."""
    val = rng.choice([i for i in range(-8, 8) if i != 0])
    return val & 0xF


def mode_j_nibble(mode: str, row: int, col: int, rng: random.Random) -> int:
    if mode == "zeros":
        return 0
    if mode == "ones":
        return 1
    if mode == "random":
        return rng.randrange(16)
    if mode == "bank-nibble":
        return ((row + col) % 15) + 1
    return random_j_nibble(rng)


def build_symmetric_j_matrix(j_size: int, rng: random.Random, mode: str) -> list[list[int]]:
    """Build symmetric J with zero diagonal; entries are encoded 4-bit nibbles."""
    mat = [[0 for _ in range(j_size)] for _ in range(j_size)]
    for r in range(j_size):
        for c in range(r + 1, j_size):
            nib = mode_j_nibble(mode=mode, row=r, col=c, rng=rng)
            mat[r][c] = nib
            mat[c][r] = nib
    return mat


def build_bank_word_tables_for_j(
    j_mat: list[list[int]],
    banks: int,
    words: int,
    bits: int,
) -> list[list[str]]:
    """Pack J into [bank][word] hex lines according to RTL lane mapping."""
    if banks != 16:
        raise ValueError("j packing currently expects banks=16")
    if bits != 256:
        raise ValueError("j packing currently expects bits=256")

    j_size = len(j_mat)
    if words * 4 != j_size:
        raise ValueError(f"j-size ({j_size}) must equal words*4 ({words*4})")

    out: list[list[str]] = [["0" * (bits // 4) for _ in range(words)] for _ in range(banks)]

    for bank in range(banks):
        lane = bank // 4
        bank_in_lane = bank % 4
        row_base = bank_in_lane * 64

        for w in range(words):
            col = lane + 4 * w
            if col >= j_size:
                raise ValueError(f"Computed col index {col} out of range for j-size={j_size}")

            word_val = 0
            for row_off in range(64):
                row = row_base + row_off
                nib = j_mat[row][col] & 0xF
                word_val |= nib << (row_off * 4)

            out[bank][w] = f"{word_val:0{bits // 4}x}"

    return out


def to_twos_complement(value: int, bits: int) -> int:
    mask = (1 << bits) - 1
    return value & mask


def select_hscaling_value(idx: int) -> int:
    return [1, 2, 4, 8, 16][idx]


def build_hbias_hscaling_word(
    lane: int,
    word_idx: int,
    mode: str,
    rng: random.Random,
    hbias_bits: int,
    hscaling_bits: int,
    parallelism: int,
) -> int:
    column = lane + parallelism * word_idx

    if mode == "zeros":
        hbias_signed = 0
        hscaling = 1
    elif mode == "ones":
        hbias_signed = 1
        hscaling = 1
    elif mode == "random":
        hbias_signed = rng.randrange(-(1 << (hbias_bits - 1)), 1 << (hbias_bits - 1))
        hscaling = select_hscaling_value(rng.randrange(5))
    elif mode == "bank-nibble":
        hbias_signed = lane + 1
        hscaling = select_hscaling_value(min(lane, 4))
    else:
        hbias_signed = column
        hscaling = 1

    hbias_raw = to_twos_complement(hbias_signed, hbias_bits)
    hscaling_raw = hscaling & ((1 << hscaling_bits) - 1)
    return hbias_raw | (hscaling_raw << hbias_bits)


def main() -> None:
    args = parse_args()

    if args.banks <= 0 or args.words <= 0 or args.bits <= 0:
        raise ValueError("banks, words, and bits must be positive")
    if args.hbias_scaling_banks < 0:
        raise ValueError("hbias-scaling-banks must be non-negative")
    if args.hbias_bits <= 0 or args.hscaling_bits <= 0:
        raise ValueError("hbias-bits and hscaling-bits must be positive")
    if args.parallelism <= 0:
        raise ValueError("parallelism must be positive")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)

    if args.model_file is not None:
        j_mat, h_vec, offset_val, scaling_factor = parse_model_file(args.model_file)
        mode = "model-file"
    else:
        if args.j_size <= 0:
            raise ValueError("j-size must be positive")
        if args.j_size != 256:
            raise ValueError("generator currently supports only --j-size 256")
        j_mat = build_symmetric_j_matrix(args.j_size, rng, args.mode)
        h_vec = []
        offset_val = 0.0
        scaling_factor = 1.0
        mode = args.mode

    if len(j_mat) != 256 or any(len(row) != 256 for row in j_mat):
        raise ValueError("J matrix must be exactly 256x256")

    bank_words = build_bank_word_tables_for_j(
        j_mat=j_mat,
        banks=args.banks,
        words=args.words,
        bits=args.bits,
    )

    for idx in range(args.start_bank, args.start_bank + args.banks):
        rel_idx = idx - args.start_bank
        file_name = f"{args.prefix}{idx:02d}.cde"
        file_path = args.out_dir / file_name

        if file_path.exists() and not args.overwrite:
            raise FileExistsError(f"{file_path} already exists. Use --overwrite to replace it.")

        with file_path.open("w", encoding="ascii", newline="\n") as f:
            for w in range(args.words):
                f.write(bank_words[rel_idx][w])
                f.write("\n")

    if args.hbias_scaling_banks > 0:
        hs_hex_chars = (args.bits + 3) // 4
        hbias_mask = (1 << args.hbias_bits) - 1
        hscale_mask = (1 << args.hscaling_bits) - 1
        model_hscale = int(round(scaling_factor)) & hscale_mask

        for idx in range(args.hbias_scaling_banks):
            file_name = f"{args.hbias_scaling_prefix}{idx:02d}.cde"
            file_path = args.out_dir / file_name

            if file_path.exists() and not args.overwrite:
                raise FileExistsError(f"{file_path} already exists. Use --overwrite to replace it.")

            with file_path.open("w", encoding="ascii", newline="\n") as f:
                for w in range(args.words):
                    if mode == "model-file" and h_vec:
                        col = idx + args.parallelism * w
                        if col < len(h_vec):
                            hbias_raw = h_vec[col] & hbias_mask
                            # Keep scaling global from model file; fallback to 1 if missing/zero.
                            hscaling_raw = model_hscale if model_hscale != 0 else 1
                            packed = hbias_raw | ((hscaling_raw & hscale_mask) << args.hbias_bits)
                        else:
                            packed = 0
                    else:
                        packed = build_hbias_hscaling_word(
                            lane=idx,
                            word_idx=w,
                            mode=mode,
                            rng=rng,
                            hbias_bits=args.hbias_bits,
                            hscaling_bits=args.hscaling_bits,
                            parallelism=args.parallelism,
                        )
                    line = f"{packed:0{hs_hex_chars}x}"
                    f.write(line)
                    f.write("\n")

    print(
        f"Generated {args.banks} weight files"
        f" and {args.hbias_scaling_banks} hbias/scaling files in {args.out_dir} "
        f"({args.words} words/file, {args.bits} bits/word, mode={mode}, offset={offset_val}, scaling={scaling_factor})."
    )


if __name__ == "__main__":
    main()
