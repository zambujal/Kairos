; DSK: plugin do navegador (formato dos plugins do Bob Fossil) que arranca a Timex FDD3000 com um disco TOS (.DSK de CPC normal
; ou EXTENDED, 16 sectores de 256 numerados 0-15; os .dsk do +3 / CPC sao recusados) (core 87+). So' le' o cartao.
;   1. a ROM do Timex Interface (/SYS/ROMS/FDD3TI.ROM, 4K: a fdd3stavi.rom do Fuse com a FDD3000, a que da' com
;      o TC2048; a fdd3timex.rom nao arranca o TOS com a ROM do TC2048) para a ROM do
;      TI no core (ZXUNO A7h = 2: as escritas em 0000h-1FFFh vao para ela);
;   2. o arranque da FDD (/SYS/ROMS/FDD3BOOT.ROM, ate' 2K) para a pagina 0 da memoria do Z80 do GS (A0h = 1, A1h);
;   3. o disco: os sectores do .DSK (o normal "MV - CPC" e o "EXTENDED") para a memoria da FDD a partir de 100000h,
;      no sitio ((pista*2 + face)*16 + sector)*256 (o fdd3000.vhd le-os dai'): 256 bytes por sector, sectores 0-15,
;      ate' 84 pistas e 2 faces (o TOS: 140K de 3" e 620K de 3,5");
;   Num disco de duas faces em dois .DSK (o _2 e' o "lado B"): ENTER no outro .DSK = virar a disquete e reset.
;   4. a maquina com a FDD (A7h = 1: o Z80 do GS passa a ser o da FDD, o GS calado), o Z80 da FDD a correr
;      (A0h = 0) e o reset quando o navegador sair (A5h): o TC2048 arranca pelo Timex Interface e o TOS.
; Para voltar ao TC2048 normal: o RESET+NMI (Ctrl+Alt+Shift).
; Os discos ficam na memoria: o que o TOS grava perde-se ao desligar (por agora nao volta ao cartao).
; So' no TIMEX 2048 e no TC2068 (no ZX 128K e no Pentagon a memoria de 8000h e' outra: recusa).
; (Kairos, 2026-11-05)
; Monta-se com  sjasmplus -I../nav --raw=DSK plugin_dsk.asm

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

BUF                 equ 0A000h          ; uma pista inteira do .DSK (ate' 20K)
BUFTAM              equ 5000h

                    org 8000h
                    jr Inicio
                    db "BP",0,0
                    db 0                ; flags
                    db 0                ; flags2
                    db "DSK (FDD3000) - Kairos",0

Inicio              push ix
                    push iy
                    ld (SPerro),sp
                    ld (Nome),hl        ; HL = o nome do ficheiro
                    in a,(0F4h)         ; so' no TIMEX 2048 (F4 = F0h e' o ZX 128K / Pentagon)
                    cp 0F0h
                    jp z,ErroMaq
                    ; ja' na FDD (outro disco, ou o outro lado): o Z80 da FDD parado e a FDD desligada antes de
                    ; usar o esxDOS (com a FDD o 0008h e' do Timex Interface, sem o automap da DivMMC)
                    di
                    ld bc,0FC3Bh
                    ld a,0A0h
                    out (c),a
                    inc b
                    ld a,1
                    out (c),a
                    xor a
                    call SetA7
                    ; ------------------------------------------------ 1. a ROM do Timex Interface
                    ld hl,TxtTI
                    ld de,BUF
                    ld bc,4096
                    call LeFich
                    jp c,ErroTI
                    di
                    ld a,2              ; A7h = 2: carga da ROM do TI
                    call SetA7
                    ld hl,BUF
                    ld de,0
                    ld bc,4096
                    ldir
                    xor a
                    call SetA7
                    ; ------------------------------------------------ 2. o arranque da FDD
                    ld hl,TxtBoot
                    ld de,BUF
                    ld bc,2048
                    call LeFich
                    jp c,ErroBoot
                    ld (BootN),bc
                    di
                    ld bc,0FC3Bh        ; A0h = 1: o Z80 do GS parado, o ponteiro da carga a 0
                    ld a,0A0h
                    out (c),a
                    inc b
                    ld a,1
                    out (c),a
                    ld a,1
                    ld (Comecou),a
                    ld hl,BUF
                    ld de,(BootN)
                    call Envia
                    ; ------------------------------------------------ 3. o disco
                    ld hl,(Nome)
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ld a,1
                    ld (Aberto),a
                    ld hl,DiscoI        ; o cabecalho do disco (256 bytes)
                    ld bc,256
                    call Le
                    jp c,ErroCorte
                    ld a,(DiscoI)       ; "MV - CPC..." ou "EXTENDED CPC DSK..."
                    cp 'M'
                    jr z,DNormal
                    cp 'E'
                    jp nz,ErroNaoDSK
                    ld a,1
                    ld (Ext),a
DNormal             ld a,(DiscoI+30h)   ; pistas x faces
                    ld e,a
                    ld a,(DiscoI+31h)
                    ld (Faces),a
                    ld d,a
                    ld hl,0
DNt                 ld a,d              ; HL = pistas x faces
                    or a
                    jr z,DNtf
                    push de
                    ld d,0
                    add hl,de
                    pop de
                    dec d
                    jr DNt
DNtf                ld (NPist),hl
                    ld hl,DiscoI+34h    ; a tabela das pistas (EXTENDED)
                    ld (TabP),hl
                    xor a
                    ld (NSec),a
; ---------------------------------------------------------------- uma pista de cada vez
Pista               ld hl,(NPist)
                    ld a,h
                    or l
                    jp z,Fim
                    dec hl
                    ld (NPist),hl
                    ld a,(Ext)          ; o tamanho do bloco da pista no ficheiro
                    or a
                    jr z,PNorm
                    ld hl,(TabP)
                    ld b,(hl)           ; EXTENDED: byte alto (x 256); 0 = pista por formatar (nao esta' no ficheiro)
                    inc hl
                    ld (TabP),hl
                    ld c,0
                    ld a,b
                    or a
                    jr z,Pista
                    jr PLe
PNorm               ld bc,(DiscoI+32h)
PLe                 ld a,b              ; ate' 20K
                    cp BUFTAM/256 + 1
                    jp nc,ErroGrande
                    ld hl,BUF
                    call Le
                    jp c,ErroCorte
                    ld a,(BUF)          ; "Track-Info"
                    cp 'T'
                    jp nz,ErroNaoDSK
                    ld a,(BUF+10h)      ; a pista e a face fisicas (do cabecalho da pista)
                    cp 84
                    jp nc,ErroGeo
                    ld (PT),a
                    ld a,(BUF+11h)
                    and 1
                    ld (PF),a
                    ld a,(BUF+15h)      ; sectores nesta pista
                    ld (PN),a
                    ld ix,BUF+18h       ; a lista dos sectores (8 bytes: C H R N ST1 ST2 tamanho)
                    ld hl,BUF+100h      ; os dados
Sector              ld a,(PN)
                    or a
                    jr z,Pista
                    dec a
                    ld (PN),a
                    ld e,(ix+6)         ; o tamanho no ficheiro: EXTENDED o da lista; o normal 128 << N
                    ld d,(ix+7)
                    ld a,(Ext)
                    or a
                    jr nz,STam
                    ld a,(BUF+14h)
                    ld de,128
STn                 or a
                    jr z,STam
                    sla e
                    rl d
                    dec a
                    jr STn
STam                ld a,(ix+3)         ; so' sectores de 256 bytes (N = 1) com o numero 0-15
                    cp 1
                    jp nz,ErroGeo
                    ld a,(ix+2)
                    cp 16
                    jp nc,ErroGeo
                    push de
                    push hl
                    ; o sitio: S = (pista*2 + face)*16 + R; pagina = 4 + S/128 (A8h), resto (A9h)
                    ld a,(PT)
                    ld l,a
                    ld h,0
                    add hl,hl
                    ld a,(PF)
                    or l
                    ld l,a
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld a,(ix+2)
                    or l
                    ld l,a              ; HL = S (0 - 2687)
                    ld a,l
                    and 7Fh
                    ld e,a              ; E = S mod 128
                    add hl,hl           ; H = S / 128
                    ld a,h
                    add a,32            ; (87d) o disco em 100000h da memoria da FDD (pagina 32)
                    ld bc,0FC3Bh
                    ld d,a
                    ld a,0A8h
                    out (c),a
                    inc b
                    out (c),d
                    dec b
                    ld a,0A9h
                    out (c),a
                    inc b
                    out (c),e
                    pop hl
                    push hl
                    ld de,256
                    call Envia
                    ld hl,NSec
                    inc (hl)
                    pop hl
                    pop de
                    add hl,de           ; o sector seguinte no bloco
                    ld de,8
                    add ix,de
                    jr Sector

; ---------------------------------------------------------------- o fim: a maquina com a FDD e o reset
Fim                 ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    di
                    ld a,1              ; A7h = 1: a FDD (o Z80 do GS e' o da FDD)
                    call SetA7
                    ld bc,0FC3Bh        ; A0h = 0: o Z80 da FDD arranca
                    ld a,0A0h
                    out (c),a
                    inc b
                    xor a
                    out (c),a
                    ; (87f) espera que a FDD tenha o TOS pronto: com ele a espera do Timex o porto EF alterna 00 e 40h
                    ; (o navegador corre mais depressa que 3,5 MHz: uma espera contada em voltas nao serve). se nunca aparecer o 40h: o diagnostico (o que se leu) e sem reset
                    ld hl,0
                    ld (C00),hl
                    ld (C40),hl
                    ld e,32             ; 32 x 65536 leituras: ~40 s a 3,5 MHz, ~5 s a 27 MHz (a FDD precisa de ~2 s)
EspFdd              ld bc,0
EFl                 in a,(0EFh)
                    cp 40h
                    jr z,FddPronta
                    push hl
                    ld hl,CFF
                    cp 0FFh
                    jr z,EConta
                    ld hl,C00
                    or a
                    jr z,EConta
                    ld hl,COut
                    ld (DUlt),a
EConta              inc (hl)
                    jr nz,ENs
                    dec (hl)            ; satura em FF
ENs                 pop hl
                    dec bc
                    ld a,b
                    or c
                    jr nz,EFl
                    dec e
                    jr nz,EspFdd
                    ld hl,TxtD00        ; a FDD nao ficou pronta: o que se leu, sem reset
                    ld a,(C00)
                    call Hex2
                    ld hl,TxtD40
                    ld a,(C40)
                    call Hex2
                    ld hl,TxtDFF
                    ld a,(CFF)
                    call Hex2
                    ld hl,TxtDUlt
                    ld a,(DUlt)
                    call Hex2
                    ld bc,TxtDiag
                    ld a,31h
                    jr FimSai
FddPronta           ld bc,0FC3Bh
                    ld a,0A5h           ; A5h: o reset quando o navegador sair (o TC2048 arranca pelo TI)
                    out (c),a
                    inc b
                    out (c),a
                    ld bc,TxtOk
                    ld a,31h
FimSai
                    ld a,31h
                    push af
                    xor a
                    out (0E3h),a
                    pop af
                    ld sp,(SPerro)
                    pop iy
                    pop ix
                    ret

; ---------------------------------------------------------------- os erros
ErroMaq             ld hl,TxtMaq
                    jr Erro
ErroTI              ld hl,TxtSemTI
                    jr Erro
ErroBoot            ld hl,TxtSemBoot
                    jr Erro
ErroAbre            ld hl,TxtAbre
                    jr Erro
ErroNaoDSK          ld hl,TxtNaoDSK
                    jr Erro
ErroCorte           ld hl,TxtCorte
                    jr Erro
ErroGrande          ld hl,TxtGrande
                    jr Erro
ErroGeo             ld hl,TxtGeo
Erro                ld sp,(SPerro)
                    push hl
                    ld a,(Aberto)
                    or a
                    jr z,ESemF
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
ESemF               xor a               ; o GS fica parado (a ROM dele foi-se: o NAV volta a carrega-la quando for preciso)
                    call SetA7
                    xor a
                    out (0E3h),a
                    pop bc
                    pop iy
                    pop ix
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret

; ---------------------------------------------------------------- utilitarios
; A em hexadecimal em (HL), 2 letras
Hex2                push af
                    rrca
                    rrca
                    rrca
                    rrca
                    call Hex1
                    pop af
Hex1                and 0Fh
                    add a,'0'
                    cp '9'+1
                    jr c,H1
                    add a,7
H1                  ld (hl),a
                    inc hl
                    ret
; ZXUNO A7h = A
SetA7               push bc
                    push af
                    ld bc,0FC3Bh
                    ld a,0A7h
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    pop bc
                    ret
; DE bytes de HL para a memoria do GS / FDD (A1h, o ponteiro avanca sozinho)
Envia               ld bc,0FC3Bh
                    ld a,0A1h
                    out (c),a
                    inc b
EVl                 ld a,d
                    or e
                    ret z
                    ld a,(hl)
                    out (c),a
                    inc hl
                    dec de
                    jr EVl
; le BC bytes do ficheiro aberto para HL. CF = erro ou acabou antes
Le                  push bc
                    ld a,(FH)
                    rst 08h
                    db F_READ
                    pop de
                    di                  ; (o esxDOS podia ter ligado as interrupcoes)
                    ret c
                    ld a,b              ; leu menos do que pedia?
                    cp d
                    jr nz,LeCurto
                    ld a,c
                    cp e
                    ret z
LeCurto             scf
                    ret
; abre o ficheiro HL (nome no Spectrum), le ate' BC bytes para DE e fecha. CF = nao ha'. BC = quantos leu
LeFich              push de
                    push bc
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    pop bc
                    pop hl
                    ret c
                    ld (FH2),a
                    rst 08h
                    db F_READ
                    push af
                    push bc
                    ld a,(FH2)
                    rst 08h
                    db F_CLOSE
                    pop bc
                    pop af
                    ret

TxtTI               db "/SYS/ROMS/FDD3TI.ROM",0
TxtBoot             db "/SYS/ROMS/FDD3BOOT.ROM",0
TxtOk               db "FDD3000: o TOS arranca",0
TxtDiag             db "FDD parada 00:"
TxtD00              db "xx 40:"
TxtD40              db "xx FF:"
TxtDFF              db "xx ?"
TxtDUlt             db "xx (sem TOS)",0
C00                 db 0
C40                 db 0
CFF                 db 0
COut                db 0
DUlt                db 0
TxtMaq              db "DSK: so' no TIMEX 2048 / 2068",0
TxtSemTI            db "Falta /SYS/ROMS/FDD3TI.ROM",0
TxtSemBoot          db "Falta /SYS/ROMS/FDD3BOOT.ROM",0
TxtAbre             db "DSK: nao abre",0
TxtNaoDSK           db "Nao e' um .DSK",0
TxtCorte            db "DSK: o ficheiro acaba a meio",0
TxtGrande           db "DSK: pista grande demais",0
TxtGeo              db "DSK: nao e' um disco TOS",0
SPerro              dw 0
Nome                dw 0
FH                  db 0
FH2                 db 0
Aberto              db 0
Comecou             db 0
Ext                 db 0
Faces               db 0
NPist               dw 0
TabP                dw 0
PT                  db 0
PF                  db 0
PN                  db 0
NSec                db 0
BootN               dw 0
DiscoI              ds 256
