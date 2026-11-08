; GO2068: dot command para o DivTIESUS / Kairos: arranca o TC2068.
; Faz o mesmo que o NAV (menu das maquinas -> TC2068): carrega /BIN/2068.rom
;   24K: HOME 16K -> paginas 32,33 (e 34,35), EXROM 8K -> 36
;   32K: o mesmo e o firmware esxDOS do 2068 (ESX2068) -> 37
; (v2) Com a de 24K (a ROM original do TS2068) faz na RAM o que a de 32K trazia, a partir dos ficheiros
; originais do esxDOS 0.8.9 (ver Esx68): o firmware do 2068 na 37 e o DivMMC ligado.
; apaga a pagina 0, F3 = 0, FF = 0, F4 = 0, ZXUNO DDh = 1 (modo TC2068),
; DFh = 80h (ROM em RAM) ou C0h (com o firmware na 37: tambem o DivMMC), IM 1, salta para 0.
; Sai-se com RESET+NMI (volta o TC2048).
;   .go2068 [ficheiro]

                    include "esxdos.inc"

PILA                equ 3deah
DIVCTRL             equ 0E3h
CODIGO              equ 5B00h

                    org 2000h

Main                ld a,h
                    or l
                    jr z,SemArgs
                    ld de,Nome
CopiaNome           ld a,(hl)
                    cp " "+1
                    jr c,FimNome
                    cp ":"
                    jr z,FimNome
                    ld (de),a
                    inc hl
                    inc de
                    jr CopiaNome
FimNome             xor a
                    ld (de),a
                    ld a,(Nome)
                    or a
                    jr nz,Abre
SemArgs             ld hl,NomeDefeito
                    ld de,Nome
                    ld bc,LNomeDefeito
                    ldir
Abre                xor a
                    rst 08h
                    db M_GETSETDRV
                    ld hl,Nome
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (FHandle),a
                    ld hl,StatBuf
                    rst 08h
                    db F_FSTAT
                    jp c,MauTamanho
                    ld hl,(StatBuf+9)
                    ld a,h
                    or l
                    jr nz,MauTamanho
                    ld hl,(StatBuf+7)
                    ld (Tamanho),hl
                    ld a,l
                    or a
                    jr nz,MauTamanho
                    ld a,h
                    cp 60h
                    ld c,80h            ; DF: ROM em RAM, sem o DivMMC
                    jr z,TamOk
                    cp 80h
                    jr nz,MauTamanho
                    ld c,0C0h           ; 32K: firmware na pagina 37, com o DivMMC
TamOk               ld a,c
                    ld (ValorDF),a
                    di
                    ld (BackupSP),sp
                    ld sp,PILA
                    ld a,(FHandle)
                    ld hl,8000h
                    ld bc,(Tamanho)
                    rst 08h
                    db F_READ
                    jr c,ErroLeitura
                    ld hl,(Tamanho)
                    or a
                    sbc hl,bc
                    jr nz,ErroLeitura
                    ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    ld a,(Tamanho+1)    ; v2: 24K -> o esxDOS do 2068 feito dos originais
                    cp 60h
                    call z,Esx68
                    ld a,(Tamanho+1)
                    ld (CTam+1-CodigoEnRAM+CodigoSrc),a
                    ld a,(ValorDF)
                    ld (CDF+1-CodigoEnRAM+CodigoSrc),a
                    ld hl,CodigoSrc
                    ld de,CODIGO
                    ld bc,LCodigo
                    ldir
                    jp CODIGO

MauTamanho          ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    ld hl,MsgTamanho
                    jr Print
ErroLeitura         ld a,(FHandle)      ; a pilha do BASIC ja' foi escrita: nao se volta
                    rst 08h
                    db F_CLOSE
                    ld hl,MsgLeitura
                    call Print
                    di
                    halt
Print               ld a,(hl)
                    or a
                    ret z
                    rst 10h
                    inc hl
                    jr Print

; ---------------------------------------------------------------------------
; v2: a ROM de 24K (o TS2068 original) em 8000h-DFFFh. Faz na RAM o que a 2068.rom de 32K trazia,
; a partir dos ficheiros originais do esxDOS 0.8.9:
;  - /SYS/ROMS/ESXMMC.BIN -> E000h, 30 bytes: o firmware do 2068 (le' o ESXD68.SYS), para a pagina 37;
;  - /SYS/ESXD68.SYS: se nao houver, faz-se uma vez no cartao a partir do /SYS/ESXDOS.SYS (15 bytes, em
;    6000h; quem o le' e' o esxDOS a arrancar, nao o GO2068);
;  - EXROM (C000h): 7 bytes, o LD-BYTES entra no trap da cassete do esxDOS (o .tapein no LOAD "").
; Cada um so' se mexe se os bytes originais (do 0.8.9) estiverem todos la'. Com o firmware e o
; ESXD68.SYS: EXROM remendada, Tamanho = 8000h (E000h -> 37) e DF = C0h; senao fica tudo como antes
; (TC2068 sem esxDOS, a EXROM original).
Esx68               ld hl,NomeEsx       ; o firmware: 8192 bytes
                    ld de,0E000h
                    ld bc,2000h
                    call LeFich
                    ret c
                    ld hl,2000h
                    or a
                    sbc hl,bc
                    ret nz
                    ld hl,TabFw
                    ld ix,0E000h
                    call RemendaSe
                    ret nz
                    ld a,'*'            ; ja' ha' o ESXD68.SYS?
                    ld hl,NomeD68
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jr c,FazD68
                    rst 08h
                    db F_CLOSE
                    jr Liga68
FazD68              ld hl,NomeSys       ; o ESXDOS.SYS do 0.8.9: 4090 bytes
                    ld de,6000h
                    ld bc,1000h
                    call LeFich
                    ret c
                    ld hl,0FFAh
                    or a
                    sbc hl,bc
                    ret nz
                    ld hl,TabSys
                    ld ix,6000h
                    call RemendaSe
                    ret nz
                    ld a,'*'
                    ld hl,NomeD68
                    ld b,FA_WRITE+FA_CREATE_NEW
                    rst 08h
                    db F_OPEN
                    ret c
                    ld (FHandle),a
                    ld hl,6000h
                    ld bc,0FFAh
                    rst 08h
                    db F_WRITE
                    push af
                    push bc
                    ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    pop hl              ; bytes escritos
                    pop af
                    jr c,ApagaD68
                    ld bc,0FFAh
                    or a
                    sbc hl,bc
                    jr z,Liga68
ApagaD68            ld a,'*'            ; nao ficou inteiro: fora, senao da proxima vez parecia bom
                    ld hl,NomeD68
                    rst 08h
                    db F_UNLINK
                    ret
Liga68              ld hl,TabExrom      ; a EXROM so' com o esxDOS: sem ele o JP 0562 nao tem quem o apanhe
                    ld ix,0C000h
                    call RemendaSe
                    ld a,80h            ; como a de 32K: E000h -> pagina 37, com o DivMMC
                    ld (Tamanho+1),a
                    ld a,0C0h
                    ld (ValorDF),a
                    ret

; HL = tabela, IX = bloco: se os bytes originais estao todos la', remenda e da' Z; senao NZ e nao mexe
RemendaSe           push hl
                    xor a
                    call Remenda
                    pop hl
                    ret nz
                    ld a,1
; A = 0: so' compara (NZ = falta um byte original); A = 1: escreve os novos. Z no fim da tabela.
; Tabela: grupos "dw sitio / db n / n bytes originais / n bytes novos", acaba em dw FFFFh
Remenda             ld (RemModo),a
RemGrupo            ld e,(hl)
                    inc hl
                    ld d,(hl)
                    inc hl
                    ld a,d
                    and e
                    inc a
                    ret z               ; FFFFh: fim
                    ld c,(hl)           ; C = n
                    inc hl
                    push hl
                    push ix
                    pop hl
                    add hl,de
                    ex de,hl            ; DE = sitio no bloco
                    pop hl              ; HL = os n originais
                    ld b,0
                    ld a,(RemModo)
                    or a
                    jr nz,RemPoe
                    push bc
RemCmp              ld a,(de)
                    cp (hl)
                    jr nz,RemDif
                    inc de
                    inc hl
                    dec c
                    jr nz,RemCmp
                    pop bc
                    add hl,bc           ; salta os n novos
                    jr RemGrupo
RemDif              pop bc
                    ret                 ; NZ
RemPoe              add hl,bc           ; HL = os n novos
                    ldir
                    jr RemGrupo

; HL = ficheiro, DE = destino, BC = maximo: le'. Carry = erro, BC = bytes lidos
LeFich              push de
                    push bc
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    pop bc
                    pop hl
                    ret c
                    ld (FHandle),a
                    rst 08h
                    db F_READ
                    push af
                    push bc
                    ld a,(FHandle)
                    rst 08h
                    db F_CLOSE
                    pop bc
                    pop af
                    ret

; o que muda (tirado da diferenca entre os originais e a 2068.rom de 32K / o ESXD68.SYS que funcionam)
TabExrom
                    dw 00030h
                    db 4, 0FFh,0FFh,0FFh,0FFh, 01Fh,0C3h,00Bh,001h   ; RRA / JP 010B
                    dw 00108h
                    db 3, 0DBh,0FEh,01Fh, 0C3h,062h,005h              ; IN A,(FE) / RRA -> JP 0562
                    dw 0FFFFh
TabFw
                    dw 00175h
                    db 2, 0F4h,009h, 000h,005h   ; 09F4 -> 0500 (PRINT-OUT)
                    dw 00570h
                    db 2, 064h,005h, 030h,000h   ; 0564 -> 0030 (volta do trap da cassete, na EXROM)
                    dw 006B8h
                    db 2, 030h,025h, 089h,028h
                    dw 006C8h
                    db 2, 04Fh,053h, 036h,038h   ; "ESXDOS" -> "ESXD68": le' o /SYS/ESXD68.SYS
                    dw 00C29h
                    db 2, 030h,025h, 089h,028h
                    dw 00C2Ch
                    db 2, 0C5h,016h, 054h,013h
                    dw 00C42h
                    db 2, 0B0h,016h, 03Fh,013h
                    dw 00C49h
                    db 2, 06Eh,00Dh, 0A9h,008h
                    dw 00D0Fh
                    db 2, 0C5h,016h, 054h,013h
                    dw 00D5Dh
                    db 2, 0FBh,019h, 068h,017h
                    dw 00D69h
                    db 2, 06Eh,019h, 0D6h,016h
                    dw 00D79h
                    db 2, 08Bh,019h, 0F3h,016h
                    dw 00D80h
                    db 2, 0A7h,011h, 00Dh,00Dh
                    dw 00D83h
                    db 2, 0BFh,016h, 04Eh,013h
                    dw 00DF3h
                    db 2, 001h,016h, 030h,012h   ; 1601 -> 1230 (CHAN-OPEN)
                    dw 0FFFFh
TabSys
                    dw 00368h
                    db 2, 081h,00Fh, 0E7h,00Ah
                    dw 004C5h
                    db 2, 048h,020h, 0E7h,021h
                    dw 004DAh
                    db 2, 048h,020h, 0E7h,021h
                    dw 0057Fh
                    db 2, 08Ch,01Ch, 0EFh,01Bh
                    dw 00586h
                    db 2, 0F1h,02Bh, 0AFh,02Fh
                    dw 005A9h
                    db 2, 048h,020h, 0E7h,021h
                    dw 005BAh
                    db 1, 0F4h, 04Ah        ; 1BF4 -> 1B4A (STMT-NEXT)
                    dw 005C2h
                    db 2, 07Dh,01Bh, 0C0h,01Ah   ; 1B7D -> 1AC0 (STMT-R-1)
                    dw 0FFFFh


NomeD68             db "/SYS/ESXD68.SYS",0
NomeSys             db "/SYS/ESXDOS.SYS",0
NomeEsx             db "/SYS/ROMS/ESXMMC.BIN",0

; ---------------------------------------------------------------------------
CodigoSrc
                    disp CODIGO
CodigoEnRAM         di
                    ld sp,6000h
                    ld hl,8000h         ; HOME 0000-1FFF -> 32 e 34
                    ld a,80h+32
                    call Copia
                    ld hl,8000h
                    ld a,80h+34
                    call Copia
                    ld hl,0A000h        ; HOME 2000-3FFF -> 33 e 35
                    ld a,80h+33
                    call Copia
                    ld hl,0A000h
                    ld a,80h+35
                    call Copia
                    ld hl,0C000h        ; EXROM -> 36
                    ld a,80h+36
                    call Copia
CTam                ld a,60h
                    cp 80h
                    jr nz,SemEsx
                    ld hl,0E000h        ; ESX2068 -> 37
                    ld a,80h+37
                    call Copia
SemEsx              ld a,80h+0          ; apaga a pagina 0: o esxDOS reinicia-se
                    out (DIVCTRL),a
                    ld hl,2000h
                    ld de,2001h
                    ld (hl),l
                    ld bc,1FFFh
                    ldir
                    xor a
                    ld bc,00F3h         ; F3 = 0 (antes da FF: com o bit 5 a FF e' ignorada)
                    out (c),a
                    out (0FFh),a
                    ld bc,0FFF4h
                    out (c),a
                    ld bc,0FC3Bh        ; DDh = 1: modo TC2068 na DivTIESUS
                    ld a,0DDh
                    out (c),a
                    inc b
                    ld a,1
                    out (c),a
                    dec b
                    ld a,0DFh           ; modo ROM em RAM (C0h: tambem o DivMMC)
                    out (c),a
                    inc b
CDF                 ld a,80h
                    out (c),a
                    xor a
                    out (DIVCTRL),a
                    ld a,3Fh
                    ld i,a
                    im 1
                    jp 0
Copia               out (DIVCTRL),a     ; HL -> pagina A (8K em 2000h)
                    ld de,2000h
                    ld bc,2000h
                    ldir
                    xor a
                    out (DIVCTRL),a
                    ret
                    ent
LCodigo             equ $-CodigoSrc
                    assert LCodigo <= 256

NomeDefeito         db "/BIN/2068.rom",0
LNomeDefeito        equ $-NomeDefeito
MsgTamanho          db "GO2068: 2068.rom de 24K ou 32K",13,0
MsgLeitura          db "GO2068: erro a ler",13,0
FHandle             db 0
Tamanho             dw 0
ValorDF             db 0
RemModo             db 0
BackupSP            dw 0
StatBuf             ds 12
Nome                ds 64
