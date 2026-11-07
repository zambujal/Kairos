# KTERM — o terminal do Kairos para o CP/M da FDD3000

No CP/M da Timex FDD3000 os programas correm no Z80 da FDD e o Timex é só o terminal: recebe as letras pela ligação
do Timex Interface (o porto EF) e devolve as teclas. Até agora o terminal era o **Monitor Emulator** da TMX
Portugal (o `MONITOR.TC` do disco, Version A1.1 de 1986). O **KTERM** faz o mesmo, escrito de novo
(`fontes/kterm/kterm.asm`), e acrescenta o VT100. É o primeiro passo para um terminal com gráficos.

## Usar

1. Fazer o disco a partir do disco do Monitor Emulator (o KTERM fica no lugar do `MONITOR.TC`; o resto do disco
   fica igual):
   ```
   python3 ferramentas/tos_disco.py codigo MONEMU.DSK MONITOR.TC kterm.bin 0x8000 KTERM.DSK
   ```
   (o `kterm.bin` sai do `sjasmplus --raw=kterm.bin kterm.asm`). O disco tem o TOS e os programas da TMX: não vai
   para o GitHub.
2. Como com o Monitor Emulator: ENTER no `KTERM.DSK`, responder **1**, e quando aparece "Mete o disco do CP/M":
   NMI e ENTER no `.DSK` do CP/M (o plugin troca o disco e faz o reset da FDD).

## O que o CP/M pode mandar

**VT52, como o Monitor Emulator** (64 colunas × 24 linhas, o modo de alta resolução do Timex):

| | |
|---|---|
| 07 BEL, 08 BS, 09 TAB, 0A/0B/0C LF, 0D CR, 18 CAN | |
| ESC A / B / C / D | o cursor para cima / baixo / direita / esquerda |
| ESC H | o cursor ao princípio |
| ESC I | para cima; na linha 0 o ecrã desce |
| ESC J | limpa o ecrã todo e o cursor vai ao princípio (como o Monitor Emulator; no VT52 seria só até ao fim) |
| ESC K | apaga até ao fim da linha |
| ESC Y l c | o cursor na linha l−32, coluna c−32 |
| ESC Z | responde ESC / K |
| ESC F / ESC G | liga / desliga os gráficos especiais (5Fh–7Eh: os da DEC, ┌ ─ ┐ │ ...) |
| ESC L / ESC M | liga / desliga o vídeo inverso |
| ESC N | o carácter seguinte com os acentos da TMX (61h á, 62h ã, 63h ç, 64h ê, 65h é, 66h õ, 67h ô, 68h à, 69h í, 6Ah â, 6Eh ñ, 6Fh ó, 75h ú) |

**VT100 (ANSI)**, o que não choca com o VT52:

| | |
|---|---|
| ESC [ l;c H (ou f) | o cursor (a contar de 1) |
| ESC [ n A / B / C / D | n posições |
| ESC [ n G / ESC [ n d | a coluna / a linha |
| ESC [ J / 1J / 2J | apaga até ao fim / do princípio / tudo (o cursor fica) |
| ESC [ K / 1K / 2K | o mesmo na linha |
| ESC [ m | 0 normal, 7 inverso, 27 normal (o resto ignora-se) |
| ESC [ s / u, ESC 7 / 8 | guarda / repõe o cursor |
| ESC [ 6n | responde ESC [ l;c R |
| ESC [ c | responde ESC [ ? 1 ; 0 c |
| ESC [ ? 25 l / h | esconde / mostra o cursor |
| ESC E, ESC c, ESC ( 0 / ESC ( B | CR LF; limpa tudo; os gráficos / as letras |

Os programas para VT100 contam com 80 colunas; aqui há 64.

## As teclas

Como o Monitor Emulator, com três diferenças:
- **CS+0 (o Backspace do teclado USB) manda 08h**: no CP/M apaga a letra. O Monitor Emulator mandava 7Fh, que o
  CP/M trata à moda antiga (repete a letra apagada). O 7Fh passou para o CS+4.
- SS+S `|`, SS+F `{`, SS+G `}`, SS+A `~` (no Monitor Emulator não davam nada).
- CS+1 TAB, CS+2 maiúsculas fixas, CS+ESPAÇO (Esc no teclado USB) ESC, CS+5/6/7/8 (as setas) ESC D / B / A / C,
  CS+3 ESC H, CS+9 ESC J; **CS+SS+letra = Ctrl** (no teclado USB: Ctrl+Shift+letra, por exemplo Ctrl+Shift+C).

## Outras diferenças para o Monitor Emulator

- Na última coluna a letra fica lá e só a seguinte passa à linha de baixo (como no VT100). O Monitor Emulator
  passava logo, e uma linha de 64 letras com CR LF a seguir deixava uma linha em branco.
- O TAB numa coluna múltipla de 8 avança para a seguinte (o Monitor Emulator ficava) e pára na coluna 63.
- O ESC Z responde ESC / K (um VT52); o Monitor Emulator punha "/Z." na fila das teclas.

## A ligação com o CP/M (vista no MONITOR.TC)

O Timex lê no `IN EF` o bit 7 como o bit 4 da FDD ("o fio do bit 4") e usa `and CFh`.
- O Timex diz o estado no `OUT EF`: C0h parado, 04h tem uma tecla; F0h no arranque.
- A FDD: 06h quer uma tecla, 0Ah quer mandar uma letra, 07h erro.
- **FDD → Timex**: o Timex põe 0Fh; chega a metade baixa com o bit 7 (80h+b) e o Timex devolve-a; chega a alta com
  o bit 6 (40h+a) e o Timex devolve-a; a FDD põe C0h e o Timex põe C0h.
- **Timex → FDD**: o Timex põe 05h até a FDD pôr 0Fh; 80h+b até a FDD o devolver; 40h+a, idem; C0h.
- 256 leituras sem resposta: o Timex põe 07h (erro) e tenta de novo.

O teclado lê-se na interrupção (IM 2, a tabela em FE00h), de 2 em 2 quadros, e a tecla repete ao fim de ~0,5 s.

## O disco do TOS

Visto nos discos da TMX (`ferramentas/tos_disco.py`): 16 sectores de 256 bytes por pista; as pistas 0–3 são o TOS;
o directório é como o do CP/M e ocupa os blocos 0–3; os blocos têm 1 K e contam-se a partir da pista 4; dentro de
cada pista o sector lógico n está no físico (n × 7) mod 16. Os ficheiros de código começam por 03, o comprimento e
o endereço. O TOS lê de 256 em 256 bytes: o número de registos de 128 bytes na entrada tem de chegar a sectores
inteiros (nos discos da TMX é sempre par; com um a menos dá "Read past end of file"). O disco do CP/M (o CPM22.DSK)
não tem o salto.

## Letras

`fontes/kterm/fontes.py` faz as três letras (normal, acentos, gráficos) a partir da font8x8 de Daniel Hepper
(domínio público): `python3 fontes.py <pasta da font8x8> > kterm_fontes.asm`.
