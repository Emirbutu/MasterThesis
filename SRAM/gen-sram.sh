# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Giuseppe Sarda <giuseppe.sarda@esat.kuleuven.be>
#         Emirhan Bututaki <emirhan.bututaki@student.kuleuven.be>

set -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")

OUTPUT_DIR=$SCRIPT_DIR/UHDSPSRAM_64x256m1S

if [ ! -d "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR"
fi

#COMPILER_NAME="/users/micas/micas/design/tsmc28hpcplus/memories/compilers/MC2/tsn28hpcpuhdspsram_20120200_170a/tsn28hpcpuhdspsram_170a.pl"
COMPILER_NAME="/users/micas/micas/design/tsmc28hpcplus/memories/compilers/MC2/tsn28hpcpd127spsram_20120200_180a/tsn28hpcpd127spsram_180a.pl"
export MC2_INSTALL_DIR=/users/micas/micas/design/tsmc28hpcplus/memories/compilers/MC2/MC2_install/MC2_2012.02.00.d
export LM_LICENSE_FILE=27015@licserv.esat.kuleuven.be
export PATH=$MC2_INSTALL_DIR/bin:$PATH
export MC_HOME=/users/micas/micas/design/tsmc28hpcplus/memories/compilers/MC2/tsn28hpcpd127spsram_20120200_180a
cd $OUTPUT_DIR && perl $COMPILER_NAME -file $SCRIPT_DIR/config/uhdspsram.txt