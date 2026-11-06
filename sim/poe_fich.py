#!/usr/bin/env python3
# poe_fich.py: troca o conteudo de um ficheiro na imagem do cartao (FAT32, particao a 1 MiB) sem mexer na FAT:
# escreve os bytes novos nos clusters do ficheiro antigo e muda so' o tamanho na entrada da pasta. Assim um estado
# guardado da simulacao (com o esxDOS a meio, que guarda pedacos da FAT) continua valido. O ficheiro novo tem de
# caber nos clusters do antigo.
# Uso: poe_fich.py cartao.img /BIN/BROWSE.BIN BROWSE.BIN [...pares caminho_no_cartao ficheiro]
import struct, sys
img = sys.argv[1]
f = open(img, 'r+b')
P = 1024 * 1024
f.seek(P); bs = f.read(512)
bps, spc = struct.unpack('<H', bs[11:13])[0], bs[13]
res, nfat = struct.unpack('<H', bs[14:16])[0], bs[16]
fatsz, raiz = struct.unpack('<I', bs[36:40])[0], struct.unpack('<I', bs[44:48])[0]
dados = P + (res + nfat * fatsz) * bps
tc = spc * bps
def fat(c):
    f.seek(P + res * bps + c * 4); return struct.unpack('<I', f.read(4))[0] & 0x0FFFFFFF
def cadeia(c):
    l = []
    while 2 <= c < 0x0FFFFFF8: l.append(c); c = fat(c)
    return l
def off(c): return dados + (c - 2) * tc
def procura(pasta_c, nome):
    for c in cadeia(pasta_c):
        f.seek(off(c)); d = f.read(tc)
        for i in range(0, tc, 32):
            e = d[i:i + 32]
            if e[0] == 0: return None
            if e[0] == 0xE5 or e[11] == 0x0F: continue
            n = e[0:8].decode('latin-1').rstrip() + ('.' + e[8:11].decode('latin-1').rstrip() if e[8:11].strip() else '')
            if n.upper() == nome.upper():
                return off(c) + i, (struct.unpack('<H', e[20:22])[0] << 16) | struct.unpack('<H', e[26:28])[0]
    return None
args = sys.argv[2:]
for k in range(0, len(args), 2):
    caminho, novo = args[k], open(args[k + 1], 'rb').read()
    c = raiz; ent = None
    for parte in [p for p in caminho.split('/') if p]:
        r = procura(c, parte)
        if not r: sys.exit('%s: nao encontro %s' % (caminho, parte))
        ent, c = r
    cl = cadeia(c)
    if len(novo) > len(cl) * tc: sys.exit('%s: o novo (%d) nao cabe nos %d clusters' % (caminho, len(novo), len(cl)))
    for i, cc in enumerate(cl):
        f.seek(off(cc)); f.write(novo[i * tc:(i + 1) * tc].ljust(tc, b'\0'))
    f.seek(ent + 28); f.write(struct.pack('<I', len(novo)))
    print('%s: %d bytes em %d clusters' % (caminho, len(novo), len(cl)))
f.close()
