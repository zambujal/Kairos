#!/usr/bin/env python3
# fontes.py: faz as tres letras do KTERM (kterm_fontes.asm) a partir da font8x8 de Daniel Hepper (dominio publico,
# github.com/dhepper/font8x8). Cada letra: 96 caracteres (20h-7Fh) x 8 bytes, o bit 7 e' o ponto da esquerda.
#   FonteN  a normal (ASCII; 7Fh = (c))
#   FonteA  a do ESC N (so' o caracter seguinte): os acentos do Monitor Emulator da TMX nos sitios dele
#           (61 a' 62 a~ 63 c, 64 e^ 65 e' 66 o~ 67 o^ 68 a` 69 i' 6A a^ 6E n~ 6F o' 75 u'); o resto como a normal
#   FonteG  a do ESC F: 5Fh-7Eh = os graficos especiais da DEC (os do Monitor Emulator); 20h-5Eh como a normal
# Uso: python3 fontes.py <pasta da font8x8> > kterm_fontes.asm
import re, sys, os
pasta = sys.argv[1]
def le(nome):
    t = open(os.path.join(pasta, nome)).read()
    return [[int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', l)]
            for l in t.splitlines() if l.strip().startswith('{')]
basic, latin, box, block, greek = (le(n) for n in ('font8x8_basic.h', 'font8x8_ext_latin.h', 'font8x8_box.h',
                                                   'font8x8_block.h', 'font8x8_greek.h'))
def inv(g): return [int('{:08b}'.format(b)[::-1], 2) for b in g]      # a font8x8 tem o ponto da esquerda no bit 0
def lat(c): return latin[c - 0xA0]
def caixa(c): return box[c - 0x2500]
def desenho(linhas): return [int(l.replace('.', '0').replace('#', '1'), 2) for l in linhas]   # ja' com o bit 7 a' esquerda
normal = {c: inv(basic[c]) for c in range(0x20, 0x7F)}
normal[0x7F] = inv(lat(0xA9))
alt = dict(normal)
for c, u in {0x61: 0xE1, 0x62: 0xE3, 0x63: 0xE7, 0x64: 0xEA, 0x65: 0xE9, 0x66: 0xF5, 0x67: 0xF4, 0x68: 0xE0,
             0x69: 0xED, 0x6A: 0xE2, 0x6E: 0xF1, 0x6F: 0xF3, 0x75: 0xFA}.items():
    alt[c] = inv(lat(u))
graf = dict(normal)
linha = lambda n: [0xFF if i == n else 0 for i in range(8)]
dois = lambda a, b: desenho([a[0], a[1], a[2], '........', b[0], b[1], b[2], '........'])
graf.update({
    0x5F: [0] * 8,
    0x60: desenho(['...#....', '..###...', '.#####..', '#######.', '.#####..', '..###...', '...#....', '........']),
    0x61: inv(block[0x2592 - 0x2580]),
    0x62: dois(['#.#.....', '###.....', '#.#.....'], ['....###.', '.....#..', '.....#..']),   # HT
    0x63: dois(['###.....', '##......', '#.......'], ['....###.', '....##..', '....#...']),   # FF
    0x64: dois(['.##.....', '#.......', '.##.....'], ['....##..', '....#.#.', '....##..']),   # CR
    0x65: dois(['#.......', '#.......', '###.....'], ['....###.', '....##..', '....#...']),   # LF
    0x66: inv(lat(0xB0)), 0x67: inv(lat(0xB1)),
    0x68: dois(['#..#....', '##.#....', '#.##....'], ['....#...', '....#...', '....###.']),   # NL
    0x69: dois(['#.#.....', '#.#.....', '.#......'], ['....###.', '.....#..', '.....#..']),   # VT
    0x6A: inv(caixa(0x2518)), 0x6B: inv(caixa(0x2510)), 0x6C: inv(caixa(0x250C)), 0x6D: inv(caixa(0x2514)),
    0x6E: inv(caixa(0x253C)),
    0x6F: linha(0), 0x70: linha(2), 0x71: inv(caixa(0x2500)), 0x72: linha(5), 0x73: linha(7),
    0x74: inv(caixa(0x251C)), 0x75: inv(caixa(0x2524)), 0x76: inv(caixa(0x2534)), 0x77: inv(caixa(0x252C)),
    0x78: inv(caixa(0x2502)),
    0x79: desenho(['....##..', '..##....', '##......', '..##....', '....##..', '........', '######..', '........']),
    0x7A: desenho(['##......', '..##....', '....##..', '..##....', '##......', '........', '######..', '........']),
    0x7B: inv(greek[0x3C0 - 0x390]) if len(greek) > 0x30 else desenho(['........', '#######.', '.#...#..', '.#...#..', '.#...#..', '.#...#..', '.#...#..', '........']),
    0x7C: desenho(['........', '.....#..', '######..', '...#....', '######..', '.#......', '........', '........']),
    0x7D: inv(lat(0xA3)), 0x7E: inv(lat(0xB7)),
})
print('; kterm_fontes.asm: feito pelo fontes.py (a font8x8 de Daniel Hepper, dominio publico). Nao editar.')
for nome, f in (('FonteN', normal), ('FonteA', alt), ('FonteG', graf)):
    print(nome)
    for c in range(0x20, 0x80):
        print('                    db ' + ','.join('%03Xh' % b for b in f[c]) + '   ; %02Xh' % c)
