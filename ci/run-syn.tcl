#!/bin/sh

# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Giuseppe Sarda <giuseppe.sarda@esat.kuleuven.be>
# run-syn.sh: run synthesis on the generated RTL

set -e

show_usage()
{
    echo "Swirl: Synthesis script"
    echo "Usage: $0 [[--clk_period=#n] [--syn_module=#name] [--sram] [--output_dir=#path] [--retime] [--help]]"
}

show_help()
{
    show_usage
    echo ""
    echo "Options:"
    echo "  --clk_period=#n: target clock period in ps (default: 10000)"
    echo "  --syn_module=#name: top module to synthesize (default: syn_tle)"
    echo "  --sram: synthesize syn_tle_with_sram instead of syn_tle"
    echo "  SRAM=1: environment-variable form of --sram"
    echo "  --retime: enable retiming (default: enabled)"
    echo "  --output_dir=#path: output directory (default: ./outputs/)"
    echo "  --help: show this help message"
}

SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(realpath "$SCRIPT_DIR/..")

# Default values

CLK_SPD=3000
SYN_MODULE=${SYN_MODULE:-}
SRAM=${SRAM:-0}
RETIME=1
OUTPUT_DIR=

for i in "$@"
do
case $i in
    --clk_period=*)
        CLK_SPD="${i#*=}"
        shift
        ;;
    --syn_module=*)
        SYN_MODULE="${i#*=}"
        shift
        ;;
    --sram)
        SRAM=1
        shift
        ;;
    --no-sram)
        SRAM=0
        shift
        ;;
    --output_dir=*)
        OUTPUT_DIR="${i#*=}"
        shift
        ;;
    --retime)
        RETIME=1
        shift
        ;;
    --help)
        show_help
        exit 0
        ;;
    *)
        echo "Invalid option: $i"
        show_usage
        exit -1
        ;;
esac
done

if [ -z "$SYN_MODULE" ]; then
    if [ "$SRAM" = "1" ]; then
        SYN_MODULE="syn_tle_with_sram"
    else
        SYN_MODULE="syn_tle"
    fi
fi


if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$ROOT_DIR/target/syn/outputs/${SYN_MODULE}/C${CLK_SPD}_RT${RETIME}"
    echo "No output directory specified, using default: $OUTPUT_DIR"	
fi

echo "Running synthesis with the following parameters:"
echo "  SYN_MODULE=$SYN_MODULE"
echo "  SRAM=$SRAM"
echo "  CLK_SPD=$CLK_SPD"
echo "  RETIME=$RETIME"
echo "  OUTPUT_DIR=$OUTPUT_DIR"

cd "$ROOT_DIR/target/syn/src"
echo "$ROOT_DIR"
mkdir -p ./work
cd ./work

source /esat/micas-data/data/design/scripts/ddi_22.35.rc
CLK_SPD=$CLK_SPD OUTPUT_DIR=$OUTPUT_DIR SYN_MODULE=$SYN_MODULE RETIME=$RETIME genus -legacy_ui -overwrite -files ../syn.tcl -log genCompile.log