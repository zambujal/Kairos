#!/usr/bin/env python3
# nomes.py: le' o core em Verilog do GHDL (core_kairos_syn.v) e escreve o nomes.h para o tb:
#   R_<sinal>  o registo de um sinal do core_kairos (o GHDL escreve "<sinal> = nNNNN_q; // (isignal)")
#   P_cpu_a, P_cpu_m1   o endereco e o M1 do Z80 do Timex (dentro do T80: "assign a = nNNNN_q;")
# Os nomes sao os membros do modelo do Verilator (o core_kairos fica um modulo; o T80 vai para dentro dele).
#   DR_<sinal>, DG_, DF_  a entrada D desse registo (para o mudar a partir do banco: ver o poe() do tb)
import re, sys
src = open(sys.argv[1]).read()
mods = {m.group(1): m.start() for m in re.finditer(r'^module (\S+)', src, re.M)}
def corpo(nome):
    i = mods[nome]
    j = src.find('\nendmodule', i)
    return src[i:j]
print('// gerado pelo nomes.py a partir do core_kairos_syn.v: nao mudar a mao')
def registos(modulo, macro, prefixo):
    c = corpo(modulo)
    # a entrada D de cada registo (nNNNN_q <= nMMMM_o): o banco muda um registo pela entrada D (D_), para o
    # Verilator ver a mudanca no flanco e reavaliar o que depende dele (mudar o _q directamente nao chega)
    d_de = {m.group(1): m.group(2) for m in re.finditer(r'^\s+(n\d+_q) <= (n\d+_o);', c, re.M)}
    vistos = set()
    for m in re.finditer(r'^\s+(\w+) = (n\d+_q); // \(isignal\)', c, re.M):
        s, q = m.group(1), m.group(2)
        if s in vistos: continue
        vistos.add(s)
        print('#define %s%s __PVT__%s%s' % (macro, s, prefixo, q))
        if q in d_de: print('#define D%s%s __PVT__%s%s' % (macro, s, prefixo, d_de[q]))
def primeiro(prefixo):
    l = [n for n in mods if n.startswith(prefixo)]
    return l[0] if l else None
registos('core_kairos', 'R_', '')                                   # o core
if primeiro('gs_'): registos(primeiro('gs_'), 'G_', 'gsnd__DOT__')     # o General Sound / o Z80 da FDD
if primeiro('fdd3000_'): registos(primeiro('fdd3000_'), 'F_', 'gsnd__DOT__fd__DOT__')   # os portos da FDD3000
t80 = primeiro('t80_0_')
if t80:
    c = corpo(t80)
    for porto, nome in (('a', 'cpu_a'), ('m1_n', 'cpu_m1')):
        m = re.search(r'^\s+assign %s = (n\d+_q);' % porto, c, re.M)
        if m:
            print('#define P_%s __PVT__cpu__DOT__u0__DOT__%s' % (nome, m.group(1)))              # o Z80 do Timex
            print('#define P_gs_%s __PVT__gsnd__DOT__cpu__DOT__u0__DOT__%s' % (nome[4:], m.group(1)))   # o Z80 da FDD
