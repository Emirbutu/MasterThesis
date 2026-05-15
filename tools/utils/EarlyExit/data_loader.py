"""Load default dataset files for early-exit accuracy analysis.

This module parses the files in the default data directory:
- model
- states_in_1, states_in_2
- states_out_1, states_out_2
- energy_1, energy_2
- clusters_1, clusters_2
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np


@dataclass(frozen=True)
class EarlyExitCaseData:
    """Container for one default dataset case."""

    case_id: int
    j_matrix_nibble: np.ndarray
    h_vector_nibble: np.ndarray
    states_in_bits: np.ndarray
    states_out_bits: np.ndarray
    energy_raw: np.ndarray
    clusters_bits: np.ndarray
    offset: float | None
    scaling_factor: float | None


class EarlyExitDataLoader:
    """Load and parse early-exit data files from a base directory."""

    def __init__(self, base_dir: str | Path):
        self.base_dir = Path(base_dir)

    def load_case(self, case_id: int) -> EarlyExitCaseData:
        if case_id not in (1, 2):
            raise ValueError("case_id must be 1 or 2")

        model_path = self.base_dir / "model"
        states_in_path = self.base_dir / f"states_in_{case_id}"
        states_out_path = self.base_dir / f"states_out_{case_id}"
        energy_path = self.base_dir / f"energy_{case_id}"
        clusters_path = self.base_dir / f"clusters_{case_id}"

        j_mat, h_vec, offset, scaling = self._parse_model_file(model_path)

        spin_count = j_mat.shape[0]
        states_in = self._parse_fixed_width_binary_matrix(states_in_path, width=spin_count)
        states_out = self._parse_fixed_width_binary_matrix(states_out_path, width=spin_count)

        energy_width = self._infer_binary_width(energy_path, default=32)
        energy = self._parse_binary_vector(
            energy_path,
            width=energy_width,
            signed=True,
        )

        clusters = self._parse_fixed_width_binary_matrix(clusters_path, width=spin_count)

        return EarlyExitCaseData(
            case_id=case_id,
            j_matrix_nibble=j_mat,
            h_vector_nibble=h_vec,
            states_in_bits=states_in,
            states_out_bits=states_out,
            energy_raw=energy,
            clusters_bits=clusters,
            offset=offset,
            scaling_factor=scaling,
        )

    def load_all_cases(self) -> list[EarlyExitCaseData]:
        return [self.load_case(1), self.load_case(2)]

    @staticmethod
    def aligned_time_series(case: EarlyExitCaseData) -> dict[str, np.ndarray]:
        """Align state/cluster/energy arrays to a shared trailing window.

        Some datasets include one extra state snapshot compared to energy
        samples. This helper keeps the last common number of samples.
        """

        lengths = {
            "states_in": case.states_in_bits.shape[0],
            "states_out": case.states_out_bits.shape[0],
            "clusters": case.clusters_bits.shape[0],
            "energy": case.energy_raw.shape[0],
        }
        n = min(lengths.values())

        return {
            "states_in_bits": case.states_in_bits[-n:],
            "states_out_bits": case.states_out_bits[-n:],
            "clusters_bits": case.clusters_bits[-n:],
            "energy_raw": case.energy_raw[-n:],
        }

    def _parse_model_file(
        self,
        model_path: Path,
    ) -> tuple[np.ndarray, np.ndarray, float | None, float | None]:
        if not model_path.is_file():
            raise FileNotFoundError(f"Missing model file: {model_path}")

        sections: dict[str, list[str]] = {}
        current = ""

        for line in model_path.read_text(encoding="ascii").splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                current = stripped[1:].strip().lower()
                sections[current] = []
            elif current:
                sections[current].append(stripped)

        if "j matrix" not in sections:
            raise ValueError("model file does not contain '# J matrix' section")

        j_rows: list[list[int]] = []
        for row in sections["j matrix"]:
            tokens = row.split()
            if not tokens:
                continue
            j_rows.append([self._parse_bin_token(tok, signed=True) for tok in tokens])

        if not j_rows:
            raise ValueError("model '# J matrix' section is empty")

        row_lens = {len(r) for r in j_rows}
        if len(row_lens) != 1:
            raise ValueError("model '# J matrix' has inconsistent row width")

        j_mat = np.asarray(j_rows, dtype=np.int8)

        h_values: list[int] = []
        if "h vector" in sections:
            for line in sections["h vector"]:
                h_values.append(self._parse_bin_token(line.split()[0], signed=True))
        h_vec = np.asarray(h_values, dtype=np.int8)

        offset = None
        if "offset" in sections and sections["offset"]:
            offset = float(sections["offset"][0].split()[0])

        scaling = None
        if "scaling_factor" in sections and sections["scaling_factor"]:
            scaling = float(sections["scaling_factor"][0].split()[0])

        return j_mat, h_vec, offset, scaling

    def _parse_fixed_width_binary_matrix(self, file_path: Path, width: int) -> np.ndarray:
        if not file_path.is_file():
            raise FileNotFoundError(f"Missing data file: {file_path}")

        rows: list[list[int]] = []
        for bits in self._iter_binary_lines(file_path):
            if len(bits) != width:
                continue
            rows.append([1 if ch == "1" else 0 for ch in bits])

        if not rows:
            raise ValueError(f"No {width}-bit lines found in {file_path}")

        return np.asarray(rows, dtype=np.int8)

    def _parse_binary_vector(
        self,
        file_path: Path,
        width: int | None,
        signed: bool,
    ) -> np.ndarray:
        if not file_path.is_file():
            raise FileNotFoundError(f"Missing data file: {file_path}")

        vals: list[int] = []
        for bits in self._iter_binary_lines(file_path):
            if width is not None and len(bits) != width:
                continue
            w = len(bits) if width is None else width
            vals.append(self._bin_to_int(bits, w, signed=signed))

        if not vals:
            raise ValueError(f"No valid binary values found in {file_path}")

        return np.asarray(vals, dtype=np.int64)

    def _infer_binary_width(self, file_path: Path, default: int) -> int:
        widths: list[int] = [len(bits) for bits in self._iter_binary_lines(file_path)]
        if not widths:
            return default

        width_counts: dict[int, int] = {}
        for w in widths:
            width_counts[w] = width_counts.get(w, 0) + 1

        return max(width_counts, key=width_counts.get)

    @staticmethod
    def _iter_binary_lines(file_path: Path) -> Iterable[str]:
        for line in file_path.read_text(encoding="ascii").splitlines():
            s = line.strip()
            if s and all(ch in "01" for ch in s):
                yield s

    @staticmethod
    def _parse_bin_token(token: str, signed: bool = False) -> int:
        tok = token.strip()
        if not tok or any(ch not in "01" for ch in tok):
            raise ValueError(f"Invalid binary token: {token}")
        val = int(tok, 2)
        if signed and tok[0] == "1":
            return val - (1 << len(tok))
        return val

    @staticmethod
    def _bin_to_int(bits: str, width: int, signed: bool) -> int:
        u = int(bits, 2)
        if not signed:
            return u
        if bits[0] == "1":
            return u - (1 << width)
        return u


def bits01_to_pm1(bits_matrix: np.ndarray) -> np.ndarray:
    """Convert {0,1} bit matrix to Ising spin representation {-1,+1}."""

    return (2 * bits_matrix.astype(np.int8) - 1).astype(np.int8)
