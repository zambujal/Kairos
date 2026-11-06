#!/bin/bash
# corre.sh: o caminho do teclado USB (mcu_spi + hid_teclado) com o BL616 a falar como o FPGA-Companion.
#   ./corre.sh [DELTA_NS]   DELTA_NS = do ultimo flanco do SCLK ao CSN a 1 (por omissao 1000 ns)
# Precisa do ghdl. Escreve "mensagens: N, erros: M" no fim.
set -e
AQUI="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$AQUI/../../core/src" && pwd)"
O="$AQUI/../obra/teclado"; mkdir -p "$O"; cd "$O"
ghdl -a --std=08 -frelaxed "$SRC/mcu_spi.vhd" "$SRC/hid_teclado.vhd" "$AQUI/tb_teclado.vhd"
ghdl -r --std=08 -frelaxed tb_teclado -gDELTA_NS=${1:-1000} 2>&1 | grep -E "ERRO|mensagens" | sed 's/.*(report [a-z]*): //'
