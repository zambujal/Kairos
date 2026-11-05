; FDD3000: comando do esxDOS (/BIN/FDD3000) que arranca a maquina "TIMEX FDD3000" (core 88+): o TC2048
; com a Timex FDD3000 ligada, como se a disquete estivesse desligada. O menu das maquinas do navegador
; corre-o (".fdd3000"). Sem disco: a FDD fica a' espera de um (o arranque dela le' o sector 0 ate' haver);
; o disco mete-se depois com ENTER num .DST no navegador (o plugin DST).
;   1. /SYS/ROMS/FDD3TI.ROM (4K, a ROM do Timex Interface) para a memoria do TI no core (ZXUNO A7h = 2);
;   2. /SYS/ROMS/FDD3BOOT.ROM (2K, o arranque da FDD) para a memoria do Z80 da FDD (A0h = 1, A1h);
;   3. F3 = 0 (TIMEX 2048), A7h = 1 (a FDD, sem disco), A0h = 0 (o Z80 da FDD arranca) e A7h = 5:
;      o reset ja' (bit 2, core 88): o TC2048 arranca pelo Timex Interface.
; Com erro (falta uma ROM): a mensagem, uma tecla e o reset para o TC2048 normal (A7h = 4: sem a FDD).
; Monta-se com  sjasmplus -I../nav --raw=FDD3000 fdd3000_dot.asm
                    include "esxdos.inc"
BUF_TI              equ 0C000h          ; 4K
BUF_BOOT            equ 0D000h          ; 2K

                    org 2000h
Inicio              di
                    xor a               ; a FDD desligada e o Z80 dela parado enquanto se carrega
                    call SetA7
                    ld a,1
                    call SetA0
                    ld hl,TxtTI
                    ld de,BUF_TI
                    ld bc,4096
                    call LeFich
                    jr c,ErroRom
                    ld hl,TxtBoot
                    ld de,BUF_BOOT
                    ld bc,2048
                    call LeFich
                    jr c,ErroRom
                    di
                    ld a,2              ; A7h = 2: as escritas em 0000h-1FFFh vao para a ROM do TI
                    call SetA7
                    ld hl,BUF_TI
                    ld de,0
                    ld bc,4096
                    ldir
                    xor a
                    call SetA7
                    ld a,1              ; A0h = 1: o Z80 da FDD parado, o ponteiro da carga a 0
                    call SetA0
                    ld bc,0FC3Bh
                    ld a,0A1h
                    out (c),a
                    inc b
                    ld hl,BUF_BOOT
                    ld de,2048
Envia               ld a,(hl)
                    out (c),a
                    inc hl
                    dec de
                    ld a,d
                    or e
                    jr nz,Envia
                    ld bc,00F3h         ; F3 = 0: o TIMEX 2048 (a ROM do TI so' da' com a do TC2048)
                    xor a
                    out (c),a
                    out (0FFh),a        ; o ecra normal
                    ld a,1              ; A7h = 1: a FDD, sem disco
                    call SetA7
                    xor a               ; A0h = 0: o Z80 da FDD arranca
                    call SetA0
                    ld a,5              ; A7h = 5: e o reset ja'
                    call SetA7
                    jr $

ErroRom             ld iy,5C3Ah
                    ld hl,TxtErro
EscL                ld a,(hl)
                    or a
                    jr z,EscF
                    rst 10h
                    inc hl
                    jr EscL
EscF                xor a               ; espera que larguem as teclas e depois por uma
                    in a,(0FEh)
                    cpl
                    and 1Fh
                    jr nz,EscF
EscT                xor a
                    in a,(0FEh)
                    cpl
                    and 1Fh
                    jr z,EscT
                    ld a,4              ; A7h = 4: o reset, sem a FDD (o TC2048 normal)
                    call SetA7
                    jr $

; DE = destino, BC = tamanho, HL = nome: le' o ficheiro todo. CF = erro (falta ou e' mais curto)
LeFich              push de
                    push bc
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    pop bc
                    pop hl
                    ret c
                    ld (FH),a
                    push bc
                    rst 08h
                    db F_READ
                    pop de              ; o que se pediu
                    push af
                    push bc             ; o que se leu
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    pop bc
                    pop af
                    ret c
                    ld a,b              ; leu tudo?
                    cp d
                    jr nz,LFcurto
                    ld a,c
                    cp e
                    ret z
LFcurto             scf
                    ret

SetA7               push af
                    ld bc,0FC3Bh
                    ld a,0A7h
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    ret
SetA0               push af
                    ld bc,0FC3Bh
                    ld a,0A0h
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    ret

FH                  db 0
TxtTI               db "/SYS/ROMS/FDD3TI.ROM",0
TxtBoot             db "/SYS/ROMS/FDD3BOOT.ROM",0
TxtErro             db 13,"FDD3000: falta /SYS/ROMS/",13,"FDD3TI.ROM ou FDD3BOOT.ROM",13,"Uma tecla: TC2048",0
