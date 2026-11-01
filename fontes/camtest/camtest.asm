; CAMTEST: teste da camada L (1280x720, 2 bits por ponto) pelo Z80, sem o ESP (core 71: EC3B / ED3B).
; Limpa a camada a azul, escreve texto com a letra Spleen 8x16 (160 x 45 letras) e enche o ecra todo de
; texto para medir o tempo. USR devolve os quadros (1/50 s) que levou a encher o ecra.
; Desligar: OUT 60475,64: OUT 60731,0
                    org 8000h
PSEL                equ 0EC3Bh
PDAT                equ 0ED3Bh
FONTE               equ 9000h
TAB                 equ 0A000h          ; 256 x 2 bytes: um byte da letra -> 8 pontos a 2 bits

Inicio              di
                    ld a,41h            ; cores: 1 azul escuro, 2 azul claro (seleccao), 3 branco
                    ld hl,Cores
                    ld b,9
                    call Regs
                    ld a,4Eh            ; tudo opaco
                    ld e,0
                    call Reg
                    ld a,26h            ; sem rectangulo
                    ld hl,Zero4
                    ld b,4
                    call Regs
                    ld e,0              ; ponteiro 600000h
                    ld d,60h
                    call Ptr
                    ld a,34h            ; limpa: 1280 x 720 / 4 = 230400 bytes de 55h (cor 1)
                    ld bc,PSEL
                    out (c),a
                    ld bc,PDAT
                    ld hl,900           ; 900 x 256
                    ld a,55h
Limpa1              ld e,0
Limpa2              out (c),a
                    dec e
                    jr nz,Limpa2
                    dec hl
                    ld d,a
                    ld a,h
                    or l
                    ld a,d
                    jr nz,Limpa1
                    ld a,40h            ; a camada L ligada, imagem 0 (600000h)
                    ld e,1
                    call Reg
                    ; texto
                    ld a,31h            ; tinta 3, papel 1
                    call Tabela
                    ld hl,Txt1
                    ld de,0102h         ; linha 1, coluna 2
                    call Escreve
                    ld hl,Txt2
                    ld de,0302h
                    call Escreve
                    ld a,12h            ; tinta 1, papel 2 (a linha seleccionada)
                    call Tabela
                    ld hl,Txt3
                    ld de,0502h
                    call Escreve
                    ld a,31h
                    call Tabela
                    ld hl,Txt4
                    ld de,0602h
                    call Escreve
                    ld hl,Txt5
                    ld de,0702h
                    call Escreve
                    ; o tempo de encher as linhas 10-44 (35 linhas x 160 letras)
                    ei
                    ld hl,(5C78h)
                    ld (T0),hl
                    ld a,0Ah
Cheio               push af
                    ld d,a
                    ld e,0
                    ld hl,Linha
                    call Escreve
                    pop af
                    inc a
                    cp 45
                    jr c,Cheio
                    ld hl,(5C78h)
                    ld de,(T0)
                    or a
                    sbc hl,de
                    ld b,h
                    ld c,l
                    ret

; A = registo, E = valor
Reg                 push bc
                    ld bc,PSEL
                    out (c),a
                    ld bc,PDAT
                    out (c),e
                    pop bc
                    ret
; A = 1.o registo, HL = valores, B = quantos
Regs                push bc
                    ld bc,PSEL
                    out (c),a
                    pop bc
Rg1                 ld a,(hl)
                    inc hl
                    push bc
                    ld bc,PDAT
                    out (c),a
                    pop bc
                    djnz Rg1
                    ret
; espera a fila vazia
Espera              push bc
                    ld bc,PSEL
Es1                 in a,(c)
                    rra
                    jr nc,Es1
                    pop bc
                    ret
; ponteiro = 60xxxxh: D = bits 22-16 (60h + ...), HL... aqui DE:HL? -> ponteiro = D<<16 | (PtrBaixo)
; E = bits 7-0, (PtrMeio) = bits 15-8
Ptr                 call Espera
                    ld a,30h
                    call Reg
                    ld a,(PtrMeio)
                    ld e,a
                    ld a,31h
                    call Reg
                    ld e,d
                    ld a,32h
                    jp Reg

; A = tinta (bits 7-4) e papel (bits 3-0): a tabela dos 256 bytes da letra
Tabela              ld b,a
                    and 0Fh
                    ld (Papel),a
                    ld a,b
                    rrca
                    rrca
                    rrca
                    rrca
                    and 0Fh
                    ld (Tinta),a
                    ld hl,TAB
                    ld c,0              ; C = o byte da letra
TBb                 ld a,c
                    ld (Byte),a
                    ld de,0             ; DE = os 16 bits (o ponto da esquerda nos bits 15-14)
                    ld b,8
TBp                 sla e
                    rl d
                    sla e
                    rl d
                    ld a,(Byte)
                    rlca
                    ld (Byte),a
                    ld a,(Papel)
                    jr nc,TBpa
                    ld a,(Tinta)
TBpa                or e
                    ld e,a
                    djnz TBp
                    ld (hl),d           ; o 1.o byte (os 4 pontos da esquerda)
                    inc hl
                    ld (hl),e
                    inc hl
                    inc c
                    jr nz,TBb
                    ret

; HL = texto (0 no fim), D = linha (0-44), E = coluna (0-159)
Escreve             push hl
                    ld (TxtP),hl
                    ld b,0              ; o comprimento
EScnt               ld a,(hl)
                    or a
                    jr z,EScf
                    inc hl
                    inc b
                    jr EScnt
EScf                ld a,b
                    ld (Comp),a
                    ; ponteiro = 600000h + D x 5120 + E x 2
                    push de
                    ld a,d
                    ld h,0
                    ld l,a              ; HL = linha
                    add hl,hl           ; x 2
                    add hl,hl           ; x 4
                    ld b,h
                    ld c,l              ; BC = linha x 4
                    add hl,hl           ; x 8
                    add hl,hl           ; x 16
                    add hl,bc           ; x 20 -> x 5120 = x 20 x 256
                    ld a,l              ; A:0 = linha x 5120 (bits 23-8 = HL)
                    ld (PtrMeio),a
                    ld d,h
                    pop bc              ; C = coluna
                    push de
                    ld l,c
                    ld h,0
                    add hl,hl           ; coluna x 2
                    ld a,(PtrMeio)
                    add a,h
                    ld (PtrMeio),a
                    pop de
                    ld a,d
                    adc a,60h
                    ld d,a              ; bits 22-16
                    ld e,l              ; bits 7-0
                    call Ptr
                    ld a,26h            ; rectangulo: largura = 2 x comprimento, passo 320
                    ld e,0
                    ld a,(Comp)
                    add a,a
                    ld e,a
                    ld a,0
                    adc a,0
                    push af
                    ld a,26h
                    call Reg
                    pop af
                    ld e,a
                    ld a,27h
                    call Reg
                    ld a,28h
                    ld e,320 & 255
                    call Reg
                    ld a,29h
                    ld e,320 >> 8
                    call Reg
                    ld a,34h
                    ld bc,PSEL
                    out (c),a
                    ; 16 linhas de pontos
                    ld a,0
ESlin               ld (Lin),a
                    ld hl,(TxtP)
                    ld a,(Comp)
                    ld b,a
ESc                 push bc
                    ld a,(hl)           ; a letra
                    inc hl
                    push hl
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl           ; x 16
                    ld a,(Lin)
                    add a,l
                    ld l,a
                    ld de,FONTE
                    add hl,de
                    ld l,(hl)           ; o byte da letra nesta linha
                    ld h,0
                    add hl,hl
                    ld de,TAB
                    add hl,de
                    ld bc,PDAT
                    ld a,(hl)
                    out (c),a
                    inc hl
                    ld a,(hl)
                    out (c),a
                    pop hl
                    pop bc
                    djnz ESc
                    ld a,(Lin)
                    inc a
                    cp 16
                    jr c,ESlin
                    pop hl
                    ret

Cores               db 00h,00h,60h,  20h,80h,0E0h,  0F0h,0F0h,0F0h
Zero4               db 0,0,0,0
Txt1                db "Timorphius - camada L pelo Z80, letra Spleen 8x16 (1280x720, 160 x 45 letras)",0
Txt2                db "/JOGOS/",0
Txt3                db " > Manic Miner.tap                                 48K ",0
Txt4                db "   Jet Set Willy.tap                               48K ",0
Txt5                db "   Chase H.Q..z80                                 128K ",0
Linha               db "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ !?.,:;()[]{}<>+-*/=_#@$%&",0
Papel               db 0
Tinta               db 0
PtrMeio             db 0
TxtP                dw 0
Comp                db 0
Lin                 db 0
Byte                db 0
T0                  dw 0
                    ds FONTE-$
                    incbin "font8x16.bin"
