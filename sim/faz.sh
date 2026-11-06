#!/bin/bash
# faz.sh: o modelo do core do Kairos para a simulacao (GHDL -> Verilog -> Verilator).
#   ./faz.sh          tudo: o core em Verilog, os nomes para o banco e o programa (obra/obj/sim_kairos)
#   ./faz.sh tb       so' volta a compilar o banco (tb_kairos.cpp), depois de o mudar
# Precisa de: ghdl (com --synth), verilator (5.x), g++, python3. Fica tudo em sim/obra/ (nao vai para o git).
set -e
AQUI="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$AQUI/../core/src" && pwd)"
O="$AQUI/obra"
mkdir -p "$O"
cd "$O"
OPT=(OPT_FAST="-O3" OPT_SLOW="-O1" OPT_GLOBAL="-O2")

if [ "$1" = "tb" ]; then
  make -C obj -f Vcore_kairos.mk -j"$(nproc)" "${OPT[@]}" sim_kairos 2>&1 | grep -E "error|Error" || true
  ls -la obj/sim_kairos
  exit 0
fi

echo "== GHDL: o core em Verilog"
# as ROMs (do Timex e o esxDOS) ja' estao nas memorias desde o inicio (home.hex / esx.hex): sem o modo de carga
sed "s/signal carga : std_logic := '1';/signal carga : std_logic := '0';/" "$SRC/core_kairos.vhd" > core_kairos_sim.vhd
grep -q "signal carga : std_logic := '0';" core_kairos_sim.vhd || { echo "nao encontro o sinal carga"; exit 1; }
rm -f work-obj08.cf
for f in T80_Pack T80_ALU T80_MCode T80_Reg T80 T80se T80se_ct sdram ym2149 ulaplus fdd3000 gs; do
  ghdl -a --std=08 -fsynopsys -frelaxed "$SRC/$f.vhd"
done
ghdl -a --std=08 -fsynopsys -frelaxed core_kairos_sim.vhd
ghdl --synth --std=08 -fsynopsys -frelaxed -gCOM_SID=false --out=verilog core_kairos > core_kairos_syn.v 2> ghdl.log \
  || { tail -20 ghdl.log; exit 1; }
python3 "$AQUI/limpa_syn.py" core_kairos_syn.v core_kairos_v.v
echo "   $(wc -l < core_kairos_v.v) linhas"

echo "== nomes.h: os registos do core e dos dois Z80 para o banco"
python3 "$AQUI/nomes.py" core_kairos_v.v > nomes.h

echo "== Verilator"
rm -rf obj
verilator --cc --exe --savable -O3 -Wno-fatal -Wno-lint -Wno-style --x-assign fast --x-initial fast \
  --default-language 1364-2005 --top-module core_kairos --Mdir obj -CFLAGS "-I$O" \
  "$O/core_kairos_v.v" "$AQUI/mem_sim.v" \
  "$SRC/divt/divtiesus_tang.v" "$SRC/divt/divmmc_mcleod.v" "$SRC/divt/modo.v" "$SRC/divt/bancos128.v" \
  "$SRC/divt/tres_e.v" "$SRC/divt/zxunoregs.v" \
  "$AQUI/tb_kairos.cpp" -o sim_kairos > verilator.log 2>&1 || { grep -E "%Error" verilator.log | head -20; exit 1; }
make -C obj -f Vcore_kairos.mk -j"$(nproc)" "${OPT[@]}" > make.log 2>&1 || { grep -E "error" make.log | head -20; exit 1; }
ls -la obj/sim_kairos
