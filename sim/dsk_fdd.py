#!/usr/bin/env python3
# dsk_fdd.py: a memoria da FDD3000 (2 MB, a que o core tem na SDRAM em 400000h) a partir da ROM de arranque e
# de um .DSK do TOS, como o plugin DSK a deixa:
#   0x000000  a ROM de arranque da FDD (FDD3BOOT.ROM, 2K)
#   0x010000  a RAM de 64K do Z80 da FDD (a zeros)
#   0x100000  o disco: o byte b do sector s da pista p, face f, em ((p*2 + f)*16 + s)*256 + b
# Uso: dsk_fdd.py FDD3BOOT.ROM disco.DSK fdd.bin      (sem disco: dsk_fdd.py FDD3BOOT.ROM - fdd.bin)
import struct, sys

def sectores(fn):
    d = open(fn, 'rb').read()
    ext = d[:8] == b'EXTENDED'
    if not ext and d[:8] != b'MV - CPC':
        sys.exit('%s: nao e\' um .DSK' % fn)
    npist, nfaces = d[0x30], d[0x31]
    off = 0x100
    for t in range(npist * nfaces):
        tam = d[0x34 + t] * 256 if ext else struct.unpack('<H', d[0x32:0x34])[0]
        if tam == 0:
            continue
        ti = d[off:off + 0x100]
        if ti[:10] != b'Track-Info':
            sys.exit('%s: pista %d estragada' % (fn, t))
        p = off + 0x100
        for i in range(ti[0x15]):
            e = ti[0x18 + i * 8:0x20 + i * 8]
            n = struct.unpack('<H', e[6:8])[0] if ext else 128 << ti[0x14]
            yield e[0], e[1], e[2], d[p:p + n]
            p += n
        off += tam

boot = open(sys.argv[1], 'rb').read()
m = bytearray(0x200000)
m[0:len(boot)] = boot
n = 0
if sys.argv[2] != '-':
    for pista, face, sec, dados in sectores(sys.argv[2]):
        if sec > 15 or pista > 83 or face > 1:
            continue
        a = 0x100000 + ((pista * 2 + face) * 16 + sec) * 256
        m[a:a + 256] = dados[:256].ljust(256, b'\xe5')
        n += 1
open(sys.argv[3], 'wb').write(m)
print('%s: arranque %d bytes, %d sectores' % (sys.argv[3], len(boot), n))
