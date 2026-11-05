#!/usr/bin/env python3
# fdd_roms.py: tira as duas ROMs da Timex FDD3000 do pacote do Fuse com o emulador da FDD3000 (fdd3000e, de
# slawkis: https://sourceforge.net/projects/fdd3000e/ , fuse-1.7.0-fdd3000-0.2.1-win32.7z) e grava-as como o
# plugin DSK do Kairos as quer:
#   SYS/ROMS/FDD3TI.ROM    a ROM de 4K do Timex Interface: roms/fdd3stavi.rom do pacote
#                          (a roms/fdd3timex.rom nao arranca o TOS com a ROM do TC2048)
#   SYS/ROMS/FDD3BOOT.ROM  o arranque da propria FDD (2K, 100 bytes de codigo): esta' dentro do fuse.exe
#                          (a tabela fddROM, que o fdd3000e usa como ROM da FDD)
# Uso:  python3 fdd_roms.py <pasta do pacote descompactado> <raiz do cartao>
# As ROMs sao da Timex: nao vem com o Kairos.
import sys, os, hashlib, struct
pac, cartao = sys.argv[1], sys.argv[2]
ti = open(os.path.join(pac, 'roms', 'fdd3stavi.rom'), 'rb').read()
exe = open(os.path.join(pac, 'fuse.exe'), 'rb').read()
# a tabela fddROM: o principio do arranque (DI; LD SP,3EFFh; LD A,0; OUT (20h),A; LD A,D0h; OUT (C0h),A)
assin = bytes.fromhex('f331ff3e3e00d3203ed0d3c0')
i = exe.find(assin)
if i < 0 or len(ti) != 4096: sys.exit('nao encontrei as ROMs (outra versao do fuse.exe?)')
boot = exe[i:i + 2048]
os.makedirs(os.path.join(cartao, 'SYS', 'ROMS'), exist_ok=True)
for nome, d in (('FDD3TI.ROM', ti), ('FDD3BOOT.ROM', boot)):
    open(os.path.join(cartao, 'SYS', 'ROMS', nome), 'wb').write(d)
    print('SYS/ROMS/%s  %d bytes  md5 %s' % (nome, len(d), hashlib.md5(d).hexdigest()))
