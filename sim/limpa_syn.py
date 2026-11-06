#!/usr/bin/env python3
# limpa_syn.py: arranja o Verilog que o GHDL (4.1) escreve para o Verilator o aceitar.
#  1. "u0_\reg " (o porto REG do T80 com o prefixo da instancia: um nome escapado mal feito) -> u0_reg_x
#  2. nomes declarados duas vezes no mesmo modulo: um sinal do VHDL com o mesmo nome que o fio de saida de uma
#     instancia (instancia "dv", porto "mapeado" e o sinal dv_mapeado). E' o mesmo fio: fica uma declaracao
#     (o reg, se houver) e saem os assign que o ligavam a si proprio (X = X, ou X = Y com Y = X).
# Uso: limpa_syn.py entrada.v saida.v
import re, sys
linhas = open(sys.argv[1]).read().replace('u0_\\reg ', 'u0_reg_x ').split('\n')
decl = re.compile(r'^\s*(wire|reg)\b[^;]*?\b(\w+)\s*;')
ini = 0
mudou = 0
while ini < len(linhas):
    if not linhas[ini].startswith('module '):
        ini += 1
        continue
    fim = ini
    while not linhas[fim].startswith('endmodule'):
        fim += 1
    vistos = {}
    for i in range(ini, fim):
        m = decl.match(linhas[i])
        if m:
            vistos.setdefault(m.group(2), []).append((i, m.group(1)))
    for nome, l in vistos.items():
        if len(l) < 2:
            continue
        # fica o reg (escrito num always) ou a primeira declaracao
        fica = next((i for i, k in l if k == 'reg'), l[0][0])
        for i, k in l:
            if i != fica:
                linhas[i] = '  // (limpa_syn) ' + linhas[i].strip()
                mudou += 1
        corpo = range(ini, fim)
        pela_instancia = any(re.search(r'^\s*\.\w+\(%s\)' % nome, linhas[i]) for i in corpo)
        for i in corpo:
            m = re.match(r'^\s*assign (\w+) = (\w+);', linhas[i])
            if not m:
                continue
            if m.group(1) == nome and (m.group(2) == nome or pela_instancia):
                linhas[i] = '  // (limpa_syn) ' + linhas[i].strip()
                mudou += 1
    ini = fim + 1
open(sys.argv[2], 'w').write('\n'.join(linhas))
print('limpa_syn: %d linhas comentadas' % mudou, file=sys.stderr)
