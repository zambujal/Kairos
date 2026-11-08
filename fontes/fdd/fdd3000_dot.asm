; FDD3000: comando do esxDOS (/BIN/FDD3000) que liga a Timex FDD3000 a' maquina que esta' a correr (core 88+), como
; quem encaixa a placa do Timex Interface no computador. Ha' duas placas, cada uma com a sua ROM (v87):
;   .fdd3000        FDD SPECTRUM: a interface do Spectrum e do TC2048 (a toda preta). /SYS/ROMS/FDD3TI.ROM, a ROM
;                   da Stavi (fdd3stavi.rom, chama a ROM do 48K). So' no TIMEX 2048 e no ZX 48K.
;   .fdd3000 2068   FDD TC2068: a interface do TC2068 (a preta com o botao de reset prateado). /SYS/ROMS/FDD3TI68.ROM,
;                   a ROM da TMX Portugal (fdd3timex.rom, chama a ROM do TC2068). So' no TC2068.
; O menu das maquinas do navegador corre-o (a' direita: FDD SPECTRUM, FDD TC2068) e so' na maquina certa.
; Sem disco: a FDD fica a' espera de um (o arranque dela le' o sector 0 ate' haver); o disco mete-se depois com ENTER
; num .DSK no navegador (o plugin DSK).
;   1. a ROM do TI (4K) para a memoria do TI no core (ZXUNO A7h = 2);
;   2. /SYS/ROMS/FDD3BOOT.ROM (2K, o arranque da FDD) para a memoria do Z80 da FDD (A0h = 1, A1h);
;   3. A7h = 1 (a FDD, sem disco), A0h = 0 (o Z80 da FDD arranca) e A5h: o reset quando o esxDOS acabar o comando
;      (v89d; era o A7h = 5, o reset ja', com o esxDOS a meio). A maquina e' a mesma (o F3 nao muda, o modo TC2068
;      fica) e arranca pelo Timex Interface.
; Com erro (a maquina errada, falta uma ROM): a mensagem, uma tecla e o reset sem a FDD (A7h = 4).
; Monta-se com  sjasmplus -I../nav --raw=FDD3000 fdd3000_dot.asm
                    include "esxdos.inc"
BUF_TI              equ 0C000h          ; 4K
BUF_BOOT            equ 0D000h          ; 2K

                    org 2000h
Inicio              ld a,h              ; HL = os argumentos (0 = nenhum): "2068" = a placa do TC2068
                    or l
                    jr z,ArgFim
ArgEsp              ld a,(hl)
                    cp ' '
                    jr nz,ArgVe
                    inc hl
                    jr ArgEsp
ArgVe               ld de,Txt2068
                    ld b,4
ArgC                ld a,(de)
                    cp (hl)
                    jr nz,ArgFim
                    inc de
                    inc hl
                    djnz ArgC
                    ld a,1
                    ld (Placa68),a
ArgFim
                    ; ------------------------------------------------ a placa tem de ser da maquina
                    in a,(0F4h)         ; ZX 128K / Pentagon (o F4 da' F0h): nenhuma das placas
                    cp 0F0h
                    jr nz,Nao128
                    ld a,(Placa68)
                    or a
                    ld hl,TxtMaqZX
                    jp z,Erro
                    ld hl,TxtMaq68
                    jp Erro
Nao128              ld hl,(5C4Fh)       ; o CHANS: 6840h com a ROM do TC2068 (5CB6h na do 48K)
                    ld de,6840h
                    or a
                    sbc hl,de
                    ld a,(Placa68)
                    jr z,Eh2068
                    or a                ; a ROM do 48K: so' a placa do Spectrum
                    ld hl,TxtMaq68
                    jp nz,Erro
                    ld hl,TxtTI
                    jr Carrega
Eh2068              or a                ; a ROM do TC2068: so' a placa do TC2068
                    ld hl,TxtMaqZX
                    jp z,Erro
                    ld hl,TxtTI68
Carrega             ld (NomeTI),hl
                    di
                    xor a               ; a FDD desligada e o Z80 dela parado enquanto se carrega
                    call SetA7
                    ld a,1
                    call SetA0
                    ld hl,(NomeTI)
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
                    xor a               ; (v87) o F3 fica: a maquina e' a mesma (TIMEX 2048, ZX 48K ou TC2068)
                    out (0FFh),a        ; o ecra normal
                    ld a,1              ; A7h = 1: a FDD, sem disco
                    call SetA7
                    xor a               ; A0h = 0: o Z80 da FDD arranca
                    call SetA0
                    ; (v89d) o reset quando o esxDOS acabar o comando (A5h), como um Ctrl+Alt+AltGr. O reset ja'
                    ; (A7h = 5) vinha com o esxDOS a meio e o NMI so' funcionava depois de um Ctrl+Alt+AltGr
                    ld bc,0FC3Bh
                    ld a,0A5h
                    out (c),a
                    inc b
                    out (c),a
                    ei
                    xor a               ; sem erro: volta ao BASIC e o reset vem logo a seguir
                    ret

ErroRom             ld hl,TxtErro
                    ld de,(NomeTI)      ; o nome da ROM do TI que se pediu
                    jr ErroEsc
Erro                ld de,TxtVazio
ErroEsc             push de
                    ld iy,5C3Ah
                    call Esc
                    pop hl
                    call Esc
                    ld hl,TxtTecla
                    call Esc
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
                    di
                    ld a,4              ; A7h = 4: o reset, sem a FDD (a mesma maquina, sem a placa)
                    call SetA7
                    jr $
Esc                 ld a,(hl)
                    or a
                    ret z
                    rst 10h
                    inc hl
                    jr Esc

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
Placa68             db 0                ; 1 = a placa do TC2068
NomeTI              dw TxtTI
Txt2068             db "2068"
TxtTI               db "/SYS/ROMS/FDD3TI.ROM",0
TxtTI68             db "/SYS/ROMS/FDD3TI68.ROM",0
TxtBoot             db "/SYS/ROMS/FDD3BOOT.ROM",0
TxtErro             db 13,"FDD3000: falta /SYS/ROMS/FDD3BOOT.ROM",13,"ou ",0
TxtMaqZX            db 13,"FDD3000: esta placa e' a do",13,"Spectrum (TIMEX 2048, ZX 48K)",0
TxtMaq68            db 13,"FDD3000: esta placa e' a do",13,"TC2068 (.fdd3000 2068)",0
TxtTecla            db 13,"Uma tecla: sem a FDD",0
TxtVazio            db 0
