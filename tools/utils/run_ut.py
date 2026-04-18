#!/usr/bin/env python3
# Copyright 2026 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

"""Python wrapper for ci/ut-run.sh.

This keeps your existing simulation flow unchanged while making it easy to:
- launch runs from Python
- capture return code/output for verification logic
- reuse the same CLI options as ut-run.sh
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    root_default = Path(__file__).resolve().parents[2]

    parser = argparse.ArgumentParser(description="Run unit tests through ci/ut-run.sh")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=root_default,
        help="Project root path (default: auto-detected)",
    )
    parser.add_argument("--test", required=True, help="Unit test name (e.g., syn_tle_with_sram)")
    parser.add_argument("--tool", default=None, help="Simulation tool (passed to ut-run.sh)")
    parser.add_argument("--hdl-flist", default=None, help="HDL file list path (passed as --hdl_flist)")
    parser.add_argument("--dbg", type=int, default=0, help="Debug level (0-3)")
    parser.add_argument("--gui", action="store_true", help="Enable GUI mode")
    parser.add_argument(
        "--post-syn",
        action="store_true",
        help="Use post-synthesis HDL/netlist configuration",
    )
    parser.add_argument(
        "--strict-gui",
        action="store_true",
        help="Fail if --gui is requested but no DISPLAY is available",
    )
    parser.add_argument("--defines", default=None, help="Additional defines string")
    parser.add_argument("--clean", action="store_true", help="Run clean before simulation")
    parser.add_argument("--clean-only", action="store_true", help="Only clean, do not simulate")
    parser.add_argument(
        "--no-analyze",
        action="store_true",
        help="Skip post-simulation analyzer execution",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the command without executing it",
    )
    parser.add_argument(
        "extra_args",
        nargs=argparse.REMAINDER,
        help="Extra args appended to ut-run.sh (usage: ... -- --some-flag)",
    )
    return parser.parse_args()


def build_command(args: argparse.Namespace, run_script: Path) -> list[str]:
    cmd = [str(run_script), f"--test={args.test}"]
    defines = args.defines
    env_post_syn = os.environ.get("POST_SYN_SIM", "").strip().lower() in {"1", "true", "yes", "on"}
    post_syn_enabled = args.post_syn or env_post_syn

    if post_syn_enabled:
        defines = f"{defines} POST_SYN_SIM=1".strip() if defines else "POST_SYN_SIM=1"
        if not args.hdl_flist:
            args.hdl_flist = str((Path(args.project_root).resolve() / "hw" / "unit_tests" / args.test / "hdl_file_list_post_syn.tcl"))

    if args.tool:
        cmd.append(f"--tool={args.tool}")
    if args.hdl_flist:
        cmd.append(f"--hdl_flist={args.hdl_flist}")

    cmd.append(f"--dbg={args.dbg}")

    if args.gui:
        cmd.append("--gui")
    if defines:
        cmd.append(f"--defines={defines}")
    if args.clean:
        cmd.append("--clean")
    if args.clean_only:
        cmd.append("--clean-only")

    # argparse.REMAINDER includes leading '--' if provided; drop it.
    if args.extra_args:
        extras = args.extra_args[1:] if args.extra_args[0] == "--" else args.extra_args
        cmd.extend(extras)

    return cmd


def main() -> int:
    args = parse_args()
    project_root = args.project_root.resolve()
    run_script = project_root / "ci" / "ut-run.sh"

    if not run_script.is_file():
        print(f"ERROR: script not found: {run_script}", file=sys.stderr)
        return 2

    if args.dbg < 0 or args.dbg > 3:
        print("ERROR: --dbg must be in [0, 3]", file=sys.stderr)
        return 2

    # On headless servers, Questa GUI fails with Tk initialization errors.
    if args.gui and not os.environ.get("DISPLAY"):
        if args.strict_gui:
            print(
                "ERROR: --gui requested but DISPLAY is not set. "
                "Use X forwarding or drop --gui.",
                file=sys.stderr,
            )
            return 2
        print(
            "[run_ut] WARNING: DISPLAY is not set; falling back to headless mode "
            "(removing --gui).",
            file=sys.stderr,
        )
        args.gui = False

    cmd = build_command(args, run_script)
    print("[run_ut] Command:", " ".join(cmd))
    print("[run_ut] CWD:", project_root)

    if args.dry_run:
        return 0

    completed = subprocess.run(
        cmd,
        cwd=project_root,
        text=True,
        check=False,
    )
    if completed.returncode != 0 or args.clean_only or args.no_analyze:
        return completed.returncode

    analyzer = project_root / "tools" / "utils" / "analyze_spin_energy.py"
    csv_path = project_root / "hw" / "unit_tests" / args.test / "spin_energy_log.csv"
    compare_csv = project_root / "hw" / "unit_tests" / args.test / "spin_energy_compare.csv"

    if not analyzer.is_file():
        print(f"ERROR: analyzer script not found: {analyzer}", file=sys.stderr)
        return 2
    if not csv_path.is_file():
        print(f"ERROR: simulation CSV not found: {csv_path}", file=sys.stderr)
        return 2

    python_bin = shutil.which("python3") or sys.executable
    analyze_cmd = [
        python_bin,
        str(analyzer),
        "--cde-dir",
        str(project_root / "hw" / "unit_tests" / args.test),
        "--csv",
        str(csv_path),
        "--out-csv",
        str(compare_csv),
        "--strict",
    ]

    print("[run_ut] Analyzer:", " ".join(analyze_cmd))
    analyzed = subprocess.run(
        analyze_cmd,
        cwd=project_root,
        text=True,
        check=False,
    )
    return analyzed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
