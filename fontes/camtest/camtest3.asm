; CAMTEST3 (core 72): o mesmo teste da camada L (core 71, EC3B / ED3B), so' no quadrado do meio (768x576, onde
; esta' a imagem do Spectrum: 96 x 36 letras 8x16) e mais depressa:
;   - so' as letras (papel transparente: o Spectrum ve-se por baixo; a seleccao com papel 2);
;   - o core faz os 2 bits por ponto (registo 35: 1 OUT = 8 pontos) e limpa a camada sozinho (3C-3E);
;   - a camada desligada enquanto desenha e ligada no fim (nao se ve a encher).
; USR devolve os quadros (1/50 s) do desenho todo. Desligar: OUT 60475,64: OUT 60731,0
                    org 8000h
PSEL                equ 0EC3Bh
PDAT                equ 0ED3Bh
FONTE               equ 9000h           ; 16 x 256: a linha y da letra c em 9000h + y x 256 + c
X0                  equ 64              ; o quadrado: a partir do byte 64 (ponto 256) e da linha 72
Y0                  equ 72
LARG                equ 192             ; 768 pontos = 192 bytes
BASE                equ 600000h + Y0 * 320 + X0

Inicio              di
                    ld hl,(5C78h)
                    ld (T0),hl
                    ld a,40h            ; desligada enquanto desenha
                    ld e,0
                    call Reg
                    ld a,41h
                    ld hl,Cores
                    ld b,9
                    call Regs
                    ld a,4Eh
                    ld e,0
                    call Reg
                    ; a camada toda transparente (cor 0), pelo core: 1280 x 720 / 4 = 230400 bytes = 57600 x 4
                    ld de,0
                    ld a,60h
                    ld (PtrAlto),a
                    call Ptr
                    ld de,0             ; sem rectangulo
                    call Rect
                    ld a,3Ch
                    ld hl,Enche
                    ld b,3
                    call Regs
                    ; so' as letras (papel 0 = transparente: o Spectrum ve-se por baixo)
                    ld hl,Txt1
                    ld de,0101h
                    ld a,0Ch            ; tinta 3, papel 0
                    call Escreve
                    ld hl,Txt2
                    ld de,0301h
                    ld a,0Ch
                    call Escreve
                    ld hl,Txt3
                    ld de,0501h
                    ld a,06h            ; tinta 1, papel 2 (a seleccao)
                    call Escreve
                    ld hl,Txt4
                    ld de,0601h
                    ld a,0Ch
                    call Escreve
                    ld hl,Txt5
                    ld de,0701h
                    ld a,0Ch
                    call Escreve
                    ld a,9
Cheio               push af
                    ld d,a
                    ld e,0
                    ld hl,Linha
                    ld a,0Ch
                    call Escreve
                    pop af
                    inc a
                    cp 36
                    jr c,Cheio
                    call Espera
                    ld a,40h            ; ligada: aparece tudo de uma vez
                    ld e,1
                    call Reg
                    ei
                    ld hl,(5C78h)
                    ld de,(T0)
                    or a
                    sbc hl,de
                    ld b,h
                    ld c,l
                    ret
Enche               db 0, 57600 & 255, 57600 >> 8

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
Espera              push bc
                    ld bc,PSEL
Es1                 in a,(c)
                    rra
                    jr nc,Es1
                    pop bc
                    ret
; ponteiro = (PtrAlto):DE
Ptr                 call Espera
                    ld a,30h
                    call Reg
                    ld e,d
                    ld a,31h
                    call Reg
                    ld a,(PtrAlto)
                    ld e,a
                    ld a,32h
                    jp Reg
; rectangulo: DE = largura (bytes), passo 320
Rect                ld a,26h
                    call Reg
                    ld e,d
                    ld a,27h
                    call Reg
                    ld a,28h
                    ld e,320 & 255
                    call Reg
                    ld a,29h
                    ld e,320 >> 8
                    jp Reg

; HL = texto (0 no fim), D = linha (0-35), E = coluna (0-95), A = as cores (36: bits 3-2 tinta, 1-0 papel)
Escreve             ld (CorE),a
                    ld (TxtP),hl
                    ld b,0
EScnt               ld a,(hl)
                    or a
                    jr z,EScf
                    inc hl
                    inc b
                    jr EScnt
EScf                ld a,b
                    ld (Comp),a
                    ; ponteiro = BASE + D x 5120 + E x 2
                    push de
                    ld l,d
                    ld h,0
                    add hl,hl
                    add hl,hl
                    ld b,h
                    ld c,l
                    add hl,hl
                    add hl,hl
                    add hl,bc           ; HL = linha x 20 (x 256 = x 5120)
                    pop de
                    push hl
                    ld l,e
                    ld h,0
                    add hl,hl           ; coluna x 2
                    ld bc,BASE & 0FFFFh
                    add hl,bc
                    ex de,hl
                    pop hl
                    ld a,BASE >> 16
                    adc a,0
                    ld b,a
                    ld a,d
                    add a,l
                    ld d,a
                    ld a,b
                    adc a,h
                    ld (PtrAlto),a
                    call Ptr
                    ld a,(Comp)
                    ld e,a
                    ld d,0
                    sla e
                    rl d
                    call Rect
                    ld a,(CorE)
                    ld e,a
                    ld a,36h
                    call Reg
                    ld a,35h            ; daqui em diante cada OUT = 8 pontos (2 bytes, feitos pelo core)
                    ld bc,PSEL
                    out (c),a
                    ld bc,PDAT
                    ld h,FONTE >> 8     ; a linha 0 da letra
ESlin               ld de,(TxtP)
                    ld a,(Comp)
                    ex af,af'
ESc                 ld a,(de)           ; a letra
                    inc de
                    ld l,a
                    ld a,(hl)           ; os 8 pontos desta linha
                    out (c),a
                    ex af,af'
                    dec a
                    jr z,ESf
                    ex af,af'
                    jr ESc
ESf                 inc h               ; a linha seguinte da letra
                    ld a,h
                    cp (FONTE >> 8) + 16
                    jr c,ESlin
                    ret

Cores               db 00h,00h,60h,  20h,80h,0E0h,  0F0h,0F0h,0F0h
Txt1                db "Kairos - camada L, so' no quadrado do meio: 96 x 36 letras 8x16",0
Txt2                db "/JOGOS/",0
Txt3                db " > Manic Miner.tap                                  48K ",0
Txt4                db "   Jet Set Willy.tap                                48K ",0
Txt5                db "   Chase H.Q..z80                                  128K ",0
Linha               db "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ !?.,:;()[]{}<>+-*/=_#@$%&",0
CorE                db 0
PtrAlto             db 0
TxtP                dw 0
Comp                db 0
T0                  dw 0
                    ds FONTE-$
                    incbin "fontrow.bin"
