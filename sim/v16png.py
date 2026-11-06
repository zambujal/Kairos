#!/usr/bin/env python3
# v16png.py: os ecras da simulacao (.v16: os 32K da RAM de video, a porta FF, a cor do hi-res, o border e o banco 7)
# em PNG de 544 x 416 (o ecra a 512 x 384 com 16 pontos de border). Modos do Timex (porta FF, bits 2-0):
#   000 normal (4000h), 001 o 2.o ecra (6000h), 010 hi-colour (pontos 4000h, cores 6000h), 110 hi-res (512 x 192,
#   colunas alternadas de 4000h e 6000h, tinta da porta FF bits 5-3 e papel o complemento)
# Uso: v16png.py ecra.v16 [...]   (escreve ecra.png ao lado)
import sys
from PIL import Image

PAL = [(0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205), (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205),
       (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]

def linha(y):          # o endereco da linha y no bitmap
    return ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)

def converte(fn):
    d = open(fn, 'rb').read()
    ram, (ff, hcor, border) = d[:32768], d[32768:32771]
    modo = ff & 7
    banco7 = len(d) > 32771 and d[32771]
    v = ram[16384:32768] if banco7 else ram[:16384]
    img = Image.new('RGB', (544, 416), PAL[border & 7])
    px = img.load()
    for y in range(192):
        for xb in range(32):
            if modo & 7 == 6:                                   # hi-res
                tinta, papel = PAL[hcor & 7], PAL[7 - (hcor & 7)]
                for k, base in enumerate((0, 0x2000)):
                    b = v[base + linha(y) + xb]
                    for bit in range(8):
                        c = tinta if b & (0x80 >> bit) else papel
                        x = 16 + (xb * 16 + k * 8 + bit)
                        px[x, 16 + 2 * y] = c; px[x, 17 + 2 * y] = c
                continue
            if modo & 7 == 2:                                   # hi-colour
                b, a = v[linha(y) + xb], v[0x2000 + linha(y) + xb]
            else:
                base = 0x2000 if modo & 7 == 1 else 0
                b, a = v[base + linha(y) + xb], v[base + 0x1800 + (y >> 3) * 32 + xb]
            br = 8 if a & 0x40 else 0
            tinta, papel = PAL[(a & 7) + br], PAL[((a >> 3) & 7) + br]
            for bit in range(8):
                c = tinta if b & (0x80 >> bit) else papel
                x = 16 + 2 * (xb * 8 + bit)
                for dx in (0, 1):
                    px[x + dx, 16 + 2 * y] = c; px[x + dx, 17 + 2 * y] = c
    out = fn.rsplit('.', 1)[0] + '.png'
    img.save(out)
    return out

for f in sys.argv[1:]:
    print(converte(f))
