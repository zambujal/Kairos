#!/usr/bin/env python3
# tos_disco.py: le' e muda os ficheiros de um disco do TOS da Timex FDD3000 (.DSK, uma face).
#
# O formato (visto nos discos da TMX): 16 sectores de 256 bytes por pista; as pistas 0-3 sao o sistema (o TOS);
# o directorio e' como o do CP/M (entradas de 32 bytes: 0, nome 8, tipo 3, extensao, -, -, registos de 128 bytes,
# 16 blocos) e ocupa os blocos 0-3; os blocos tem 1 K (4 sectores) e contam-se a partir da pista 4. Dentro de cada
# pista o sector logico n esta' no sector fisico (n * 7) mod 16 (o salto do TOS). Os ficheiros de codigo comecam
# por um cabecalho de 5 bytes: 03, o comprimento, o endereco (e o BASIC por 7: 00, ...).
#
# Uso:
#   tos_disco.py lista   <disco.dsk>
#   tos_disco.py tira    <disco.dsk> <NOME.TIP> <ficheiro>            (com o cabecalho do TOS)
#   tos_disco.py codigo  <disco.dsk> <NOME.TIP> <bin> <endereco> <novo.dsk>
#        poe o <bin> no lugar do NOME.TIP (com o cabecalho 03 / comprimento / endereco), nos blocos que ele ja'
#        tem; o resto do disco fica igual.
import sys

SALTO = 7

class Disco:
    def __init__(s, nome):
        s.d = bytearray(open(nome, 'rb').read())
        d = s.d
        s.ext = d[:8] == b'EXTENDED'
        s.npis = d[0x30]; s.nfaces = d[0x31]
        if s.nfaces != 1:
            raise SystemExit('so' + "'" + ' discos de uma face')
        s.pos = {}                              # (pista, sector) -> deslocamento dos 256 bytes no ficheiro
        off = 0x100
        for t in range(s.npis * s.nfaces):
            tam = d[0x34 + t] * 256 if s.ext else d[0x32] | d[0x33] << 8
            if tam == 0:
                continue
            tb = d[off:off + tam]
            pista = tb[0x10]; n = tb[0x15]; p = off + 0x100
            for i in range(n):
                e = tb[0x18 + 8 * i:0x20 + 8 * i]
                stam = (e[6] | e[7] << 8) if s.ext else 128 << tb[0x14]
                s.pos[(pista, e[2])] = p
                p += stam
            off += tam
    def fis(s, logico):                         # sector logico a contar da pista 4 -> deslocamento no ficheiro
        pista = 4 + logico // 16
        return s.pos[(pista, (logico % 16) * SALTO % 16)]
    def bloco(s, b):
        return b''.join(bytes(s.d[s.fis(4 * b + k):s.fis(4 * b + k) + 256]) for k in range(4))
    def poe_bloco(s, b, dados):
        for k in range(4):
            o = s.fis(4 * b + k)
            s.d[o:o + 256] = dados[256 * k:256 * k + 256]
    def entradas(s):                            # (deslocamento da entrada no ficheiro, os 32 bytes)
        for b in range(4):
            for k in range(4):
                o = s.fis(4 * b + k)
                for j in range(8):
                    yield o + 32 * j, bytes(s.d[o + 32 * j:o + 32 * j + 32])
    def ficheiros(s):
        f = {}
        for o, e in s.entradas():
            if e[0] == 0xE5 or e[0] > 15:
                continue
            nome = e[1:9].decode('latin1').strip()
            tipo = bytes(c & 0x7F for c in e[9:12]).decode('latin1').strip()
            f.setdefault((nome + '.' + tipo).rstrip('.'), []).append((e[12], o, e))
        return {k: sorted(v) for k, v in f.items()}
    def le(s, nome):
        partes = s.ficheiros()[nome]
        dados = b''
        for _, _, e in partes:
            dados += b''.join(s.bloco(b) for b in e[16:32] if b)[:e[15] * 128]
        return dados

def main():
    if len(sys.argv) < 3:
        print(__doc__ if __doc__ else open(__file__).read().split('\nimport')[0]); return
    cmd, disco = sys.argv[1], Disco(sys.argv[2])
    if cmd == 'lista':
        for nome, partes in disco.ficheiros().items():
            reg = sum(e[15] for _, _, e in partes)
            blocos = [b for _, _, e in partes for b in e[16:32] if b]
            cab = disco.le(nome)[:5]
            info = ''
            if cab[0] == 3:
                info = 'codigo: %d bytes em %04Xh' % (cab[1] | cab[2] << 8, cab[3] | cab[4] << 8)
            elif cab[0] == 0:
                info = 'BASIC'
            print('%-12s %6d bytes  blocos %-30s %s' % (nome, reg * 128, ' '.join('%02X' % b for b in blocos), info))
    elif cmd == 'tira':
        open(sys.argv[4], 'wb').write(disco.le(sys.argv[3]))
    elif cmd == 'codigo':
        nome, binf, end, novo = sys.argv[3], sys.argv[4], int(sys.argv[5], 0), sys.argv[6]
        partes = disco.ficheiros()[nome]
        if len(partes) != 1:
            raise SystemExit('so' + "'" + ' ficheiros de uma extensao')
        _, oent, e = partes[0]
        blocos = [b for b in e[16:32] if b]
        cod = open(binf, 'rb').read()
        dados = bytes([3, len(cod) & 255, len(cod) >> 8, end & 255, end >> 8]) + cod
        if len(dados) > len(blocos) * 1024:
            raise SystemExit('nao cabe: %d bytes, ha' % len(dados) + "'" + ' %d' % (len(blocos) * 1024))
        dados += b'\x1a' * (len(blocos) * 1024 - len(dados))
        for i, b in enumerate(blocos):
            disco.poe_bloco(b, dados[1024 * i:1024 * i + 1024])
        # os registos de 128 bytes, em sectores inteiros: o TOS le' de 256 em 256 bytes (com 37 registos para 4687
        # bytes deu "Read past end of file"; nos discos da TMX o RC e' sempre par)
        disco.d[oent + 15] = 2 * ((len(cod) + 5 + 255) // 256)
        open(novo, 'wb').write(disco.d)
        print('%s: %d bytes em %04Xh, nos blocos %s; %s' % (nome, len(cod), end, ' '.join('%02X' % b for b in blocos), novo))
    else:
        raise SystemExit('comando desconhecido: ' + cmd)

if __name__ == '__main__':
    main()
