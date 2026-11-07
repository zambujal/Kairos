; kterm.asm - KTERM: o terminal do Kairos para o CP/M da Timex FDD3000 (no lugar do Monitor Emulator da TMX)
;
; No CP/M da FDD3000 os programas correm no Z80 da FDD; o Timex e' so' o terminal: recebe as letras pela ligacao
; do Timex Interface (o porto EF) e devolve as teclas. O KTERM faz o mesmo que o MONITOR.TC do disco "Monitor
; Emulator" da TMX (Version A1.1, 1986), escrito de novo: a mesma conversa com o CP/M, o mesmo VT52 e as mesmas
; teclas. Carrega-se no lugar do MONITOR.TC (em 8000h, RANDOMIZE USR 32768 pelo START do disco).
;
; Ecra: o modo de alta resolucao do Timex (porta FF = 3Eh: 512 x 192, branco no preto), 64 colunas x 24 linhas,
; letras 8 x 8 (a font8x8 de Daniel Hepper, dominio publico; kterm_fontes.asm, feito pelo fontes.py).
;
; O que o CP/M pode mandar. VT52 como o Monitor Emulator:
;   07 BEL (apito)  08 BS  09 TAB (a coluna seguinte multipla de 8, no maximo a 63)  0A 0B 0C LF  0D CR
;   18 CAN (desiste de um ESC a meio); os outros abaixo de 20h e o 7Fh nao fazem nada
;   ESC A B C D   o cursor uma posicao para cima, baixo, direita, esquerda (para nas margens)
;   ESC H         o cursor ao principio          ESC I   para cima; na linha 0 o ecra desce uma linha
;   ESC J         limpa o ecra todo e o cursor ao principio (como o Monitor Emulator; no VT52 seria so' ate' ao fim)
;   ESC K         apaga ate' ao fim da linha     ESC Y l c   o cursor na linha l-32 (0-23), coluna c-32 (0-63)
;   ESC Z         responde ESC / K (um VT52)     ESC F / ESC G   liga / desliga os graficos especiais (5Fh-7Eh)
;   ESC L / ESC M liga / desliga o video inverso ESC N   o caracter seguinte com os acentos da TMX (61h a', ...)
; e o VT100 (ANSI) que nao choca com o VT52 (os programas para VT100 contam com 80 colunas; aqui ha' 64):
;   ESC [ l;c H (ou f)  o cursor (de 1)          ESC [ n A B C D   n posicoes   ESC [ n G / d   a coluna / linha
;   ESC [ J / 1J / 2J   apaga ate' ao fim / do principio / tudo (o cursor fica); ESC [ K / 1K / 2K na linha
;   ESC [ m   0 normal, 7 inverso, 27 normal (o resto ignora-se)   ESC [ s / u   guarda / repoe o cursor
;   ESC [ 6n  responde ESC [ l;c R   ESC [ 5n  ESC [ 0 n   ESC [ c  ESC [ ? 1 ; 0 c   ESC [ ? 25 l / h  o cursor
;   ESC 7 / ESC 8   guarda / repoe o cursor      ESC E   CR LF   ESC c   limpa tudo   ESC ( 0 / ESC ( B  os graficos
; A ultima coluna: a letra fica la' e so' a seguinte passa a' linha de baixo (como no VT100; o Monitor Emulator
; passava logo e, com um CR LF a seguir, deixava uma linha em branco). Na ultima linha o ecra sobe.
;
; As teclas: letras, numeros, ENTER = 0Dh, ESPACO; SYMBOL SHIFT: os simbolos do Spectrum (e, a mais, SS+S |,
; SS+F {, SS+G }, SS+A ~); CAPS SHIFT: maiusculas, CS+1 TAB, CS+2 maiusculas fixas, CS+0 BS (08h: no CP/M apaga a
; letra; o Monitor Emulator mandava 7Fh, que o CP/M repete), CS+4 DEL (7Fh), CS+ESPACO ESC (1Bh), CS+5 6 7 8 =
; ESC D B A C, CS+3 ESC H, CS+9 ESC J; CAPS SHIFT + SYMBOL SHIFT + letra = Ctrl (01h-1Ah).
; No teclado USB: Shift = CS, Ctrl ou Alt = SS (Backspace = CS+0, as setas = CS+5 6 7 8, Esc = CS+ESPACO).
;
; A ligacao (vista no MONITOR.TC; o Timex le' no IN EF o bit 7 como o bit 4 da FDD, "o fio do bit 4"):
;   o Timex diz o estado no OUT EF: C0h parado, 04h tem uma tecla; F0h no arranque.
;   a FDD (IN EF and CFh): 06h quer uma tecla, 0Ah quer mandar uma letra, 07h erro.
;   FDD -> Timex: o Timex poe 0Fh; chega a metade baixa com o bit 7 (80h+b), o Timex devolve-a; chega a alta
;     com o bit 6 (40h+a), o Timex devolve-a; a FDD poe C0h, o Timex poe C0h.
;   Timex -> FDD: o Timex poe 05h ate' a FDD por 0Fh; 80h+b ate' a FDD o devolver; 40h+a idem; C0h.
;   256 leituras sem resposta: o Timex poe 07h (erro) e tenta de novo.
;
; (Kairos, 2026-11-07)

                    org 8000h

TAB_IM2             equ 0FE00h          ; a tabela do IM 2 (257 bytes FDh) e o salto em FDFDh
SALTO_IM2           equ 0FDFDh
PILHA               equ 0FD00h

Inicio              di
                    ld sp,PILHA
                    ld hl,TAB_IM2
                    ld de,TAB_IM2+1
                    ld bc,256
                    ld (hl),0FDh
                    ldir
                    ld a,0C3h
                    ld (SALTO_IM2),a
                    ld hl,Isr
                    ld (SALTO_IM2+1),hl
                    ld a,TAB_IM2/256
                    ld i,a
                    im 2
                    ld hl,Vars          ; as variaveis a zero
                    ld de,Vars+1
                    ld bc,VarsFim-Vars-1
                    ld (hl),0
                    ldir
                    ld a,0FFh
                    ld (TUlt),a
                    ld a,3Eh            ; alta resolucao, branco no preto (como o Monitor Emulator)
                    out (0FFh),a
                    call LimpaEcra
                    ld hl,TxtBoas
                    call Texto
                    ld a,0F0h
                    out (0EFh),a
                    ei
; ---------------------------------------------------------------------------------------------------------------
; o ciclo: o estado para a FDD, o cursor, a tecla pedida, e o que a FDD quer
Ciclo               call Sinal
                    call Pisca
                    ld a,(Pede)
                    or a
                    call nz,MandaTecla
                    in a,(0EFh)
                    and 0CFh
                    cp 06h
                    jr z,CPede
                    cp 0Ah
                    jr nz,Ciclo
                    xor a               ; a FDD vai mandar uma letra (e deixa de pedir a tecla)
                    ld (Pede),a
                    call EscondeCursor
                    di
                    call RecebeByte
                    ei
                    push af
                    call Sinal
                    pop af
                    call Mostra
                    jr Ciclo
CPede               ld a,1
                    ld (Pede),a
                    jr Ciclo

; OUT EF: 04h se ha' tecla a' espera, senao C0h
Sinal               ld a,(KEnt)
                    ld b,a
                    ld a,(KSai)
                    cp b
                    ld a,0C0h
                    jr z,Si1
                    ld a,04h
Si1                 out (0EFh),a
                    ret

; manda a tecla mais antiga (a FDD pediu-a)
MandaTecla          ld a,(KEnt)
                    ld b,a
                    ld a,(KSai)
                    cp b
                    ret z
                    ld e,a
                    ld d,0
                    ld hl,KBuf
                    add hl,de
                    ld c,(hl)
                    di
                    call EnviaByte
                    ld a,(KSai)
                    inc a
                    and 1Fh
                    ld (KSai),a
                    xor a
                    ld (Pede),a
                    ei
                    ret

; ---------------------------------------------------------------------------------------------------------------
; a ligacao com a FDD
; EnviaByte: C = o byte; tenta ate' conseguir (num erro espera que a FDD volte a pedir, 06h, ou diga 07h)
EnviaByte           call Envia1
                    ret z
EB1                 in a,(0EFh)
                    and 0CFh
                    cp 06h
                    jr z,EnviaByte
                    cp 07h
                    jr nz,EB1
                    jr EnviaByte
Envia1              ld a,c
                    and 0Fh
                    ld e,a              ; E = a metade baixa
                    ld a,c
                    rrca
                    rrca
                    rrca
                    rrca
                    and 0Fh
                    ld d,a              ; D = a alta
                    ld b,0
E1a                 ld a,05h            ; quero mandar
                    out (0EFh),a
                    in a,(0EFh)
                    dec b
                    jr z,ErroLig
                    and 0CFh
                    cp 0Fh
                    jr nz,E1a
                    ld a,e
                    or 80h
                    ld l,a
                    out (0EFh),a
                    ld b,0
E1b                 in a,(0EFh)
                    dec b
                    jr z,ErroLig
                    and 0CFh
                    cp l
                    jr nz,E1b
                    ld a,d
                    or 40h
                    ld l,a
                    out (0EFh),a
                    ld b,0
E1c                 in a,(0EFh)
                    dec b
                    jr z,ErroLig
                    and 0CFh
                    cp l
                    jr nz,E1c
                    ld a,0C0h
                    out (0EFh),a
                    xor a
                    ret
ErroLig             ld a,07h
                    out (0EFh),a
                    or a                ; NZ
                    ret

; RecebeByte: A = o byte que a FDD manda (7 bits); tenta ate' conseguir
RecebeByte          call Recebe1
                    jr z,RB1
RB2                 in a,(0EFh)
                    and 0CFh
                    cp 07h
                    jr z,RB2
                    jr RecebeByte
RB1                 ld a,b
                    and 7Fh
                    ret
Recebe1             ld c,0
R1a                 ld a,0Fh            ; pronto a receber
                    out (0EFh),a
                    in a,(0EFh)
                    dec c
                    jr z,ErroLig
                    ld e,a
                    and 0C0h
                    cp 80h
                    jr nz,R1a
                    ld a,e              ; a metade baixa: devolve-se
                    out (0EFh),a
                    and 0Fh
                    ld e,a
                    ld c,0
R1b                 in a,(0EFh)
                    dec c
                    jr z,ErroLig
                    bit 6,a
                    jr z,R1b
                    out (0EFh),a        ; a alta: devolve-se
                    and 0Fh
                    rlca
                    rlca
                    rlca
                    rlca
                    or e
                    ld b,a
R1c                 in a,(0EFh)
                    and 0CFh
                    cp 07h
                    jr z,ErroLig
                    cp 0C0h
                    jr nz,R1c
                    ld a,0C0h
                    out (0EFh),a
                    xor a
                    ret

; ---------------------------------------------------------------------------------------------------------------
; o que chega da FDD: A = o caracter
Mostra              ld c,a
                    ld a,(EscY)
                    or a
                    jp nz,TrataY
                    ld a,(Parens)
                    or a
                    jp nz,TrataParens
                    ld a,c
                    cp 20h
                    jr c,Controlo
                    cp 7Fh
                    jr nc,Controlo
                    ld a,(Csi)
                    or a
                    jp nz,TrataCsi
                    ld a,(Esc)
                    or a
                    jp nz,TrataEsc
                    ld a,c
                    jp Imprime

Controlo            ld b,a
                    xor a
                    ld (Wrap),a
                    ld a,b
                    cp 1Bh
                    jr z,CEsc
                    cp 09h
                    jp z,Tab
                    cp 0Ah
                    jp z,Desce
                    cp 0Bh
                    jp z,Desce
                    cp 0Ch
                    jp z,Desce
                    cp 0Dh
                    jr z,Cr
                    cp 08h
                    jr z,Bs
                    cp 07h
                    jp z,Bip
                    cp 18h
                    jr z,Can
                    xor a               ; os outros: so' desistem de um ESC a meio
                    ld (Esc),a
                    ret
CEsc                ld a,1
                    ld (Esc),a
                    xor a
                    ld (Csi),a
                    ret
Can                 xor a
                    ld (Esc),a
                    ld (EscY),a
                    ld (Csi),a
                    ld (Parens),a
                    ret
Cr                  xor a
                    ld (Col),a
                    ret
Bs                  ld a,(Col)          ; na coluna 0 vai para o fim da linha de cima
                    or a
                    jr z,Bs1
                    dec a
                    ld (Col),a
                    ret
Bs1                 ld a,63
                    ld (Col),a
                    ld a,(Lin)
                    or a
                    ret z
                    dec a
                    ld (Lin),a
                    ret
Tab                 ld a,(Col)
                    and 0F8h
                    add a,8
                    cp 64
                    jr c,Tab1
                    ld a,63
Tab1                ld (Col),a
                    ret

; ESC <letra>
TrataEsc            xor a
                    ld (Esc),a
                    ld (Wrap),a
                    ld a,c
                    cp '['
                    jp z,EscCsi
                    cp 'A'
                    jr z,EscA
                    cp 'B'
                    jr z,EscB
                    cp 'C'
                    jr z,EscC
                    cp 'D'
                    jr z,EscD
                    cp 'H'
                    jr z,EscH
                    cp 'I'
                    jr z,EscI
                    cp 'J'
                    jp z,LimpaEcra
                    cp 'K'
                    jp z,ApagaFim
                    cp 'Y'
                    jr z,EscYy
                    cp 'Z'
                    jr z,EscZ
                    cp 'F'
                    jr z,EscF
                    cp 'G'
                    jr z,EscG
                    cp 'L'
                    jr z,EscL
                    cp 'M'
                    jr z,EscM
                    cp 'N'
                    jr z,EscN
                    cp '7'
                    jp z,Guarda
                    cp '8'
                    jp z,Repoe
                    cp 'E'
                    jr z,EscE
                    cp 'c'
                    jr z,EscRst
                    cp '('
                    jr z,EscPar
                    ret
EscA                ld a,(Lin)
                    or a
                    ret z
                    dec a
                    ld (Lin),a
                    ret
EscB                ld a,(Lin)
                    cp 23
                    ret z
                    inc a
                    ld (Lin),a
                    ret
EscC                ld a,(Col)
                    cp 63
                    ret z
                    inc a
                    ld (Col),a
                    ret
EscD                ld a,(Col)
                    or a
                    ret z
                    dec a
                    ld (Col),a
                    ret
EscH                xor a
                    ld (Lin),a
                    ld (Col),a
                    ret
EscI                ld a,(Lin)
                    or a
                    jr nz,EscA
                    jp DesceEcra
EscYy               ld a,1
                    ld (EscY),a
                    ret
EscZ                ld hl,RespVt52      ; ESC / K: "sou um VT52"
                    jp Responde
EscF                ld a,1
                    ld (Graf),a
                    ret
EscG                xor a
                    ld (Graf),a
                    ret
EscL                ld a,0FFh
                    ld (Inv),a
                    ret
EscM                xor a
                    ld (Inv),a
                    ret
EscN                ld a,1
                    ld (Alt1),a
                    ret
EscE                xor a
                    ld (Col),a
                    jp Desce
EscRst              xor a
                    ld (Inv),a
                    ld (Graf),a
                    ld (CurOff),a
                    jp LimpaEcra
EscPar              ld a,1
                    ld (Parens),a
                    ret
TrataParens         xor a               ; ESC ( x: 0 = os graficos, B (ou A) = as letras
                    ld (Parens),a
                    ld a,c
                    cp '0'
                    jr z,EscF
                    cp 'B'
                    jr z,EscG
                    cp 'A'
                    jr z,EscG
                    ret
Guarda              ld a,(Lin)
                    ld (GLin),a
                    ld a,(Col)
                    ld (GCol),a
                    ret
Repoe               ld a,(GLin)
                    ld (Lin),a
                    ld a,(GCol)
                    ld (Col),a
                    ret

; ESC Y: a linha, depois a coluna (+32)
TrataY              xor a
                    ld (Wrap),a
                    ld a,c
                    sub 20h
                    ld c,a
                    ld a,(EscY)
                    cp 1
                    jr nz,TY2
                    ld a,c
                    ld (YLin),a
                    ld a,2
                    ld (EscY),a
                    ret
TY2                 xor a
                    ld (EscY),a
                    ld a,c
                    cp 64
                    ret nc
                    ld b,a
                    ld a,(YLin)
                    cp 24
                    ret nc
                    ld (Lin),a
                    ld a,b
                    ld (Col),a
                    ret

; ESC [ : os parametros (ate' 4, de 0 a 255), um ? antes, e a letra do fim (40h-7Eh)
EscCsi              ld a,1
                    ld (Csi),a
                    xor a
                    ld (CsiN),a
                    ld (CsiPriv),a
                    ld hl,CsiP
                    ld (hl),a
                    inc hl
                    ld (hl),a
                    inc hl
                    ld (hl),a
                    inc hl
                    ld (hl),a
                    ret
TrataCsi            ld a,c
                    cp '0'
                    jr c,TC1
                    cp '9'+1
                    jr nc,TC1
                    sub '0'
                    ld b,a
                    ld hl,CsiP
                    ld a,(CsiN)
                    add a,l
                    ld l,a
                    jr nc,TC0
                    inc h
TC0                 ld a,(hl)           ; P = P*10 + o algarismo (no maximo 255)
                    cp 26
                    jr nc,TCmax
                    ld e,a
                    add a,a
                    add a,a
                    add a,e
                    add a,a
                    add a,b
                    jr c,TCmax
                    ld (hl),a
                    ret
TCmax               ld (hl),255
                    ret
TC1                 cp ';'
                    jr nz,TC2
                    ld a,(CsiN)
                    cp 3
                    ret z
                    inc a
                    ld (CsiN),a
                    ret
TC2                 cp '?'
                    jr nz,TC3
                    ld a,1
                    ld (CsiPriv),a
                    ret
TC3                 cp 40h
                    ret c               ; os intermedios (20h-2Fh) ignoram-se
                    xor a
                    ld (Csi),a
                    ld (Wrap),a
                    ld a,c
                    cp 'H'
                    jp z,CsiH
                    cp 'f'
                    jp z,CsiH
                    cp 'A'
                    jp z,CsiA
                    cp 'B'
                    jp z,CsiB
                    cp 'C'
                    jp z,CsiC
                    cp 'D'
                    jp z,CsiD
                    cp 'G'
                    jp z,CsiG
                    cp 'd'
                    jp z,CsiDd
                    cp 'J'
                    jp z,CsiJ
                    cp 'K'
                    jp z,CsiK
                    cp 'm'
                    jp z,CsiM
                    cp 's'
                    jp z,Guarda
                    cp 'u'
                    jp z,Repoe
                    cp 'n'
                    jp z,CsiN6
                    cp 'c'
                    jp z,CsiDa
                    cp 'h'
                    jp z,CsiHl
                    cp 'l'
                    jp z,CsiHl
                    ret
; P de 0 vale 1
Def1                or a
                    ret nz
                    inc a
                    ret
CsiH                ld a,(CsiP)
                    call Def1
                    dec a
                    cp 24
                    jr c,CH1
                    ld a,23
CH1                 ld (Lin),a
                    ld a,(CsiP+1)
                    call Def1
                    dec a
                    cp 64
                    jr c,CH2
                    ld a,63
CH2                 ld (Col),a
                    ret
CsiA                ld a,(CsiP)
                    call Def1
                    ld b,a
                    ld a,(Lin)
                    sub b
                    jr nc,CA1
                    xor a
CA1                 ld (Lin),a
                    ret
CsiB                ld a,(CsiP)
                    call Def1
                    ld b,a
                    ld a,(Lin)
                    add a,b
                    jr c,CB0
                    cp 24
                    jr c,CB1
CB0                 ld a,23
CB1                 ld (Lin),a
                    ret
CsiC                ld a,(CsiP)
                    call Def1
                    ld b,a
                    ld a,(Col)
                    add a,b
                    jr c,CC0
                    cp 64
                    jr c,CC1
CC0                 ld a,63
CC1                 ld (Col),a
                    ret
CsiD                ld a,(CsiP)
                    call Def1
                    ld b,a
                    ld a,(Col)
                    sub b
                    jr nc,CD1
                    xor a
CD1                 ld (Col),a
                    ret
CsiG                ld a,(CsiP)
                    call Def1
                    dec a
                    cp 64
                    jr c,CD1
                    ld a,63
                    jr CD1
CsiDd               ld a,(CsiP)
                    call Def1
                    dec a
                    cp 24
                    jr c,CA1
                    ld a,23
                    jr CA1
CsiJ                ld a,(CsiP)
                    or a
                    jr z,CJ0
                    dec a
                    jr z,CJ1
                    jp LimpaBits        ; 2: tudo (o cursor fica)
CJ0                 call ApagaFim       ; 0: do cursor ao fim do ecra
                    ld a,(Lin)
CJ0a                inc a
                    cp 24
                    ret nc
                    push af
                    call LimpaLinha
                    pop af
                    jr CJ0a
CJ1                 call ApagaInicio    ; 1: do principio ao cursor
                    ld a,(Lin)
CJ1a                or a
                    ret z
                    dec a
                    push af
                    call LimpaLinha
                    pop af
                    jr CJ1a
CsiK                ld a,(CsiP)
                    or a
                    jp z,ApagaFim
                    dec a
                    jp z,ApagaInicio
                    ld a,(Lin)
                    jp LimpaLinha
CsiM                ld hl,CsiP          ; ESC [ ... m: os parametros um a um
                    ld a,(CsiN)
                    inc a
                    ld b,a
CM1                 ld a,(hl)
                    or a
                    jr z,CM0
                    cp 27
                    jr z,CM0
                    cp 7
                    jr nz,CM2
                    ld a,0FFh
                    ld (Inv),a
                    jr CM2
CM0                 xor a
                    ld (Inv),a
CM2                 inc hl
                    djnz CM1
                    ret
CsiN6               ld a,(CsiP)
                    cp 5
                    jr nz,CN1
                    ld hl,RespOk        ; ESC [ 0 n
                    jp Responde
CN1                 cp 6
                    ret nz
                    di                  ; ESC [ linha ; coluna R
                    ld a,1Bh
                    call PoeTecla
                    ld a,'['
                    call PoeTecla
                    ld a,(Lin)
                    inc a
                    call PoeNum
                    ld a,';'
                    call PoeTecla
                    ld a,(Col)
                    inc a
                    call PoeNum
                    ld a,'R'
                    call PoeTecla
                    ei
                    ret
CsiDa               ld hl,RespVt100     ; ESC [ ? 1 ; 0 c: um VT100 sem opcoes
                    jp Responde
CsiHl               ld b,a              ; ESC [ ? 25 h / l: o cursor
                    ld a,(CsiPriv)
                    or a
                    ret z
                    ld a,(CsiP)
                    cp 25
                    ret nz
                    ld a,b
                    cp 'h'
                    ld a,0
                    jr z,CHl1
                    inc a
CHl1                ld (CurOff),a
                    ret
; Responde: HL = a resposta (acabada em 0) para a fila das teclas
Responde            di
Rs1                 ld a,(hl)
                    or a
                    jr z,Rs2
                    call PoeTecla
                    inc hl
                    jr Rs1
Rs2                 ei
                    ret
; PoeNum: A (1-99) em decimal na fila das teclas
PoeNum              ld b,'0'-1
PN1                 inc b
                    sub 10
                    jr nc,PN1
                    add a,10+'0'
                    ld c,a
                    ld a,b
                    cp '0'
                    call nz,PoeTecla
                    ld a,c
                    jp PoeTecla
RespVt52            db 1Bh,"/K",0
RespOk              db 1Bh,"[0n",0
RespVt100           db 1Bh,"[?1;0c",0

; ---------------------------------------------------------------------------------------------------------------
; o ecra
; Imprime: A = 20h-7Eh na posicao do cursor; o cursor avanca (na ultima coluna fica la' e a letra seguinte e'
; que passa a' linha de baixo)
Imprime             ld b,a
                    ld a,(Wrap)
                    or a
                    jr z,Im0
                    xor a
                    ld (Wrap),a
                    ld (Col),a
                    push bc
                    call Desce
                    pop bc
Im0                 ld a,b
                    sub 20h
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,FonteG
                    ld a,(Graf)
                    or a
                    jr nz,Im1
                    ld de,FonteA
                    ld a,(Alt1)
                    or a
                    jr nz,Im1
                    ld de,FonteN
Im1                 add hl,de
                    ex de,hl            ; DE = o desenho
                    xor a
                    ld (Alt1),a
                    ld a,(Col)
                    ld c,a
                    ld a,(Lin)
                    call EndCel         ; HL = o ecra
                    ld a,(Inv)
                    ld c,a
                    ld b,8
Im2                 ld a,(de)
                    xor c
                    ld (hl),a
                    inc de
                    inc h
                    djnz Im2
                    ld a,(Col)
                    cp 63
                    jr z,Im3
                    inc a
                    ld (Col),a
                    ret
Im3                 ld a,1
                    ld (Wrap),a
                    ret
; Desce: a linha seguinte (na ultima o ecra sobe)
Desce               ld a,(Lin)
                    cp 23
                    jp z,SobeEcra
                    inc a
                    ld (Lin),a
                    ret

; EndCel: A = linha (0-23), C = coluna (0-63) -> HL = o primeiro byte da letra no ecra (as colunas pares em
; 4000h, as impares em 6000h)
EndCel              call LinhaEnd
                    ld a,c
                    srl a
                    jr nc,EC1
                    set 5,h
EC1                 or l
                    ld l,a
                    ret
; LinhaEnd: A = linha -> HL = a coluna 0 da primeira linha de pontos (em 4000h)
LinhaEnd            ld b,a
                    and 18h
                    or 40h
                    ld h,a
                    ld a,b
                    and 7
                    rrca
                    rrca
                    rrca
                    ld l,a
                    ret

; LimpaEcra: tudo a zero e o cursor ao principio
LimpaEcra           call LimpaBits
                    xor a
                    ld (Lin),a
                    ld (Col),a
                    ld (Wrap),a
                    ret
LimpaBits           ld hl,4000h
                    ld de,4001h
                    ld bc,17FFh
                    ld (hl),0
                    ldir
                    ld hl,6000h
                    ld de,6001h
                    ld bc,17FFh
                    ld (hl),0
                    ldir
                    ret

; ApagaFim: da coluna do cursor ate' ao fim da linha
ApagaFim            ld a,(Col)
                    ld c,a
AF1                 ld a,(Lin)
                    call EndCel
                    ld b,8
AF2                 ld (hl),0
                    inc h
                    djnz AF2
                    inc c
                    ld a,c
                    cp 64
                    jr nz,AF1
                    ret
; ApagaInicio: da coluna 0 ate' a' do cursor
ApagaInicio         ld c,0
AI1                 ld a,(Lin)
                    call EndCel
                    ld b,8
AI2                 ld (hl),0
                    inc h
                    djnz AI2
                    ld a,(Col)
                    cp c
                    ret z
                    inc c
                    jr AI1

; SobeEcra: as linhas 1-23 sobem uma, a 23 fica limpa
SobeEcra            xor a
SE1                 push af
                    call LinhaEnd
                    ex de,hl            ; DE = a linha A
                    pop af
                    push af
                    inc a
                    call LinhaEnd       ; HL = a linha A+1
                    call CopiaLinha
                    pop af
                    inc a
                    cp 23
                    jr nz,SE1
                    ld a,23
                    jr LimpaLinha
; DesceEcra: as linhas 0-22 descem uma, a 0 fica limpa
DesceEcra           ld a,22
DE1                 push af
                    inc a
                    call LinhaEnd
                    ex de,hl            ; DE = a linha A+1
                    pop af
                    push af
                    call LinhaEnd       ; HL = a linha A
                    call CopiaLinha
                    pop af
                    dec a
                    jp p,DE1
                    xor a
; LimpaLinha: A = linha
LimpaLinha          call LinhaEnd
                    ld b,8
LL1                 push bc
                    push hl
                    call Limpa32
                    pop hl
                    push hl
                    set 5,h
                    call Limpa32
                    pop hl
                    inc h
                    pop bc
                    djnz LL1
                    ret
Limpa32             ld d,h
                    ld e,l
                    inc de
                    ld (hl),0
                    ld bc,31
                    ldir
                    ret
; CopiaLinha: as 8 linhas de pontos (64 colunas) de HL para DE
CopiaLinha          ld b,8
CL1                 push bc
                    push hl
                    push de
                    ld bc,32
                    ldir
                    pop de
                    pop hl
                    push hl
                    push de
                    set 5,h
                    set 5,d
                    ld bc,32
                    ldir
                    pop de
                    pop hl
                    inc h
                    inc d
                    pop bc
                    djnz CL1
                    ret

; o cursor: a ultima linha de pontos da letra trocada, a piscar (~0,6 s)
Pisca               ld a,(CurOff)       ; ESC [ ? 25 l: sem cursor
                    or a
                    jr nz,EscondeCursor
                    ld a,(Quadros)
                    and 10h
                    jr z,EscondeCursor
MostraCursor        ld a,(CurVis)
                    or a
                    ret nz
                    ld a,(Col)
                    ld c,a
                    ld a,(Lin)
                    call EndCel
                    ld a,h
                    add a,7
                    ld h,a
                    ld (CurEnd),hl
                    ld a,(hl)
                    cpl
                    ld (hl),a
                    ld a,1
                    ld (CurVis),a
                    ret
EscondeCursor       ld a,(CurVis)
                    or a
                    ret z
                    ld hl,(CurEnd)
                    ld a,(hl)
                    cpl
                    ld (hl),a
                    xor a
                    ld (CurVis),a
                    ret

; Bip: o apito do BEL
Bip                 ld b,60
BP1                 push bc
                    ld a,10h
                    out (0FEh),a
                    ld b,90
BP2                 djnz BP2
                    xor a
                    out (0FEh),a
                    ld b,90
BP3                 djnz BP3
                    pop bc
                    djnz BP1
                    ret

; Texto: HL = texto acabado em 0, como se viesse da FDD
Texto               ld a,(hl)
                    or a
                    ret z
                    push hl
                    call Mostra
                    pop hl
                    inc hl
                    jr Texto

; ---------------------------------------------------------------------------------------------------------------
; o teclado: na interrupcao (50 por segundo), lido de 2 em 2 quadros; a tecla repete ao fim de ~0,5 s, ~8 por segundo
Isr                 push af
                    push bc
                    push de
                    push hl
                    ld hl,Quadros
                    inc (hl)
                    ld a,(hl)
                    and 1
                    jr nz,IsrFim
                    call LeTeclado      ; A = o codigo, FFh = nada
                    ld hl,TUlt
                    cp (hl)
                    jr z,IsrIgual
                    ld (hl),a
                    xor a
                    ld (TRep),a
                    ld a,(hl)
                    call NovaTecla
                    jr IsrFim
IsrIgual            cp 0FFh
                    jr z,IsrFim
                    ld hl,TRep
                    inc (hl)
                    ld a,(hl)
                    cp 12               ; 12 leituras = ~0,5 s
                    jr c,IsrFim
                    ld (hl),9           ; depois de 3 em 3 leituras
                    ld a,(TUlt)
                    call NovaTecla
IsrFim              pop hl
                    pop de
                    pop bc
                    pop af
                    ei
                    reti

; NovaTecla: A = o codigo da tecla
NovaTecla           cp 0FFh
                    ret z
                    cp 85h              ; CS+2: maiusculas fixas
                    jr nz,NT1
                    ld a,(Caps)
                    xor 1
                    ld (Caps),a
                    ret
NT1                 cp 86h
                    jr c,PoeTecla
                    sub 86h             ; 86h-8Bh: ESC e uma letra
                    ld e,a
                    ld d,0
                    ld hl,TabEsc
                    add hl,de
                    ld a,1Bh
                    call PoeTecla
                    ld a,(hl)
; PoeTecla: A no fim da fila (32; cheia: perde-se)
PoeTecla            push hl
                    push bc
                    ld c,a
                    ld a,(KEnt)
                    ld b,a
                    inc a
                    and 1Fh
                    ld hl,KSai
                    cp (hl)
                    jr z,PT1
                    ld (KEnt),a
                    ld a,b
                    ld hl,KBuf
                    add a,l
                    ld l,a
                    jr nc,PT2
                    inc h
PT2                 ld (hl),c
PT1                 pop bc
                    pop hl
                    ret

; LeTeclado: A = o codigo da primeira tecla carregada (sem contar o CS e o SS), FFh = nenhuma
LeTeclado           ld bc,0FEFEh
                    ld e,0              ; E = o numero da tecla (0-39)
                    ld d,0FFh           ; D = a tecla encontrada
                    ld hl,0             ; H = CS, L = SS
LT1                 in a,(c)
                    cpl
                    and 1Fh
                    push bc
                    ld b,5
LT2                 rrca
                    jr nc,LT4
                    push af
                    ld a,e
                    or a
                    jr nz,LT3a
                    ld h,1              ; o CAPS SHIFT
                    jr LT3
LT3a                cp 36
                    jr nz,LT3b
                    ld l,1              ; o SYMBOL SHIFT
                    jr LT3
LT3b                ld a,d
                    inc a
                    jr nz,LT3
                    ld d,e              ; a primeira outra
LT3                 pop af
LT4                 inc e
                    djnz LT2
                    pop bc
                    rlc b
                    jr c,LT1
                    ld a,d
                    cp 0FFh
                    ret z               ; nenhuma: FFh
                    ld e,a
                    ld d,0
                    ld a,h
                    and l
                    jr nz,LTCtrl
                    ld a,h
                    or a
                    jr nz,LTCs
                    ld a,l
                    or a
                    jr nz,LTSs
                    ld hl,TabN
                    add hl,de
                    ld a,(hl)
                    ld b,a
                    ld a,(Caps)
                    or a
                    ld a,b
                    ret z
                    cp 'a'
                    ret c
                    cp 'z'+1
                    ret nc
                    and 0DFh
                    ret
LTCs                ld hl,TabC
                    add hl,de
                    ld a,(hl)
                    ret
LTSs                ld hl,TabS
                    add hl,de
                    ld a,(hl)
                    ret
LTCtrl              ld hl,TabN          ; CS + SS + letra: Ctrl
                    add hl,de
                    ld a,(hl)
                    and 0DFh
                    sub 40h
                    cp 20h
                    ret c
                    ld a,0FFh
                    ret

; as teclas pela ordem das filas (FEFE: CS Z X C V, FDFE: A S D F G, FBFE: Q W E R T, F7FE: 1 2 3 4 5,
; EFFE: 0 9 8 7 6, DFFE: P O I U Y, BFFE: ENT L K J H, 7FFE: ESPACO SS M N B)
TabN                db 84h,"zxcv","asdfg","qwert","12345","09876","poiuy",0Dh,"lkjh",' ',83h,"mnb"
TabS                db 0FFh,":`?/","~|",5Ch,"{}",0FFh,0FFh,0FFh,"<>","!@#$%","_)('&",'"',";",0FFh,"][",0Dh,"=+-^",' ',83h,".,*"
TabC                db 84h,"ZXCV","ASDFG","QWERT",09h,85h,86h,7Fh,87h,08h,88h,89h,8Ah,8Bh,"POIUY",0Dh,"LKJH",1Bh,83h,"MNB"
TabEsc              db "HDJCAB"         ; 86h-8Bh: ESC H, D (esquerda), J, C (direita), A (cima), B (baixo)

TxtBoas             db "KTERM v0 - o terminal VT52 do Kairos para o CP/M da FDD3000",0Dh,0Ah
                    db "Mete o disco do CP/M: NMI e ENTER no .DSK do CP/M",0Dh,0Ah,0Ah,0

                    include "kterm_fontes.asm"

; ---------------------------------------------------------------------------------------------------------------
Vars
Lin                 db 0
Col                 db 0
Esc                 db 0                ; 1 = chegou um ESC
EscY                db 0                ; 1 = ESC Y a' espera da linha, 2 = da coluna
YLin                db 0
Graf                db 0                ; ESC F
Inv                 db 0                ; ESC L: FFh
Alt1                db 0                ; ESC N: so' o caracter seguinte
Caps                db 0
Pede                db 0                ; a FDD pediu uma tecla
CurVis              db 0
CurEnd              dw 0
Quadros             db 0
TUlt                db 0
TRep                db 0
KEnt                db 0
KSai                db 0
KBuf                ds 32
Wrap                db 0                ; 1 = a ultima letra ficou na coluna 63
Csi                 db 0                ; 1 = dentro de um ESC [
CsiN                db 0                ; o parametro em curso (0-3)
CsiPriv             db 0                ; 1 = ESC [ ?
CsiP                ds 4
Parens              db 0                ; 1 = ESC ( a' espera da letra
GLin                db 0                ; ESC 7 / ESC [ s
GCol                db 0
CurOff              db 0                ; 1 = sem cursor (ESC [ ? 25 l)
VarsFim

                    assert $ < 0FD00h - 64
Fim
