; PT3: plugin do navegador (formato dos plugins do Bob Fossil) que toca um .PT3 no AY, com o leitor do
; NAVPT3 (Universal PT2/PT3/TS player, S. V. Bulba) incluido aqui. Fica no lugar do PT3 do Bob Fossil.
;   O navegador hi-res fica no ecra (o NAV v48 nao o limpa para o PT3); no canto de cima a' direita o tempo.
;   Teclas: P pausa / continua, N o seguinte, B o anterior, BREAK (Caps + Espaco) para e volta.
;   No fim (o ponteiro da posicao do leitor volta para tras: deu a volta) o seguinte da pasta.
;   /BIN/BPLUGINS/CFG/PT3.CFG: o mesmo do PT3 do Bob Fossil (e o PT3.INI dele serve): byte 0 bit 0 = repetir,
;   bit 1 = no fim o seguinte, bit 2 = as setas (6 / 7) passam ao seguinte / anterior; byte 1 (nosso, opcional)
;   = tempo maximo em minutos (0 = sem limite).
;   PT3 TurboSound (2 modulos no mesmo ficheiro, PT 3.7+): os dois AY (FFFD / BFFD com o FE / FF do TurboSound).
; Memoria: codigo e leitor em 8000h; o modulo em A3E0h-FCFFh (PLUGIN_RESTORE_BUFFERS); o IM 2 proprio
; (tabela em FE00h, salto em FDFDh) para o HALT de cada frame. O AY pelo FFFD/BFFD (no Timorphius em todas
; as maquinas).
; (Timorphius, 2026-11-01)

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_NAVIGATE     equ 8
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

MODBUF              equ 0A3E0h
MODMAX              equ 0FD00h-MODBUF

                    org 8000h
                    jr Inicio
                    db "BP",0,0
                    db 0                ; flags
                    db 0                ; flags2
                    db "PT3 (AY) - Timorphius",0

Inicio              push ix
                    push iy
                    ld a,i
                    ld (Ivelho),a
                    push hl             ; BC = os parametros do NAV: o 3.o byte 'H' = hi-res
                    ld h,b
                    ld l,c
                    inc hl
                    inc hl
                    ld a,(hl)
                    sub 'H'
                    jr z,IHr
                    ld a,1
IHr                 xor 1
                    ld (Hires),a
                    pop hl
                    ld a,2              ; sem CFG: o seguinte no fim, sem limite de tempo
                    ld (Opc),a
                    xor a
                    ld (Minutos),a
                    ld a,d              ; DE = o CFG (16 bytes) ou 0
                    or e
                    jr z,SemCfg
                    ld a,(de)
                    ld (Opc),a
                    inc de
                    ld a,(de)
                    ld (Minutos),a
SemCfg              ld a,'*'            ; HL = nome do ficheiro
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ld hl,MODBUF
                    ld bc,MODMAX
                    rst 08h
                    db F_READ
                    push af
                    push bc
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    pop bc
                    pop af
                    jp c,ErroLe
                    ld a,b
                    or c
                    jp z,ErroLe
                    ld hl,MODMAX        ; encheu tudo: grande demais
                    or a
                    sbc hl,bc
                    jp z,ErroGrande
                    ; o IM 2: FE00h-FF00h = FDh, em FDFDh o salto para Isr
                    ld hl,0FE00h
                    ld de,0FE01h
                    ld bc,256
                    ld (hl),0FDh
                    ldir
                    ld a,0C3h
                    ld (0FDFDh),a
                    ld hl,Isr
                    ld (0FDFEh),hl
                    ld a,0FEh
                    ld i,a
                    im 2
                    ; larga as teclas (o ENTER, ou o N / B que trouxe este)
Larga               xor a
                    in a,(0FEh)
                    cpl
                    and 1Fh
                    jr nz,Larga
                    ld a,20h            ; SETUP: bits 4-5 = %10, o TurboSound (2 AY) do PT3 3.7+ (AlCo) se o houver;
                    ld (SETUP),a        ; os outros so' num AY
                    ld hl,MODBUF
                    ld de,0
                    call INIT
                    ld hl,(VARS1+CrPsPtr)
                    ld (PosAnt),hl
                    xor a
                    ld (Frac),a
                    ld (Seg),a
                    ld (Min),a
                    call Relogio
; um frame: HALT, o leitor, o fim, o relogio, as teclas
Toca                ei
                    halt
                    di
                    call PT3ORG+3       ; PLAY
                    ld hl,(VARS1+CrPsPtr)   ; a posicao (ponteiro na lista): se voltou para tras, deu a volta
                    ld de,(PosAnt)
                    ld (PosAnt),hl
                    or a
                    sbc hl,de
                    jr nc,TNaoFim
                    ld a,(Opc)          ; a repetir: continua
                    rra
                    jp nc,Acabou
TNaoFim             ld hl,Frac
                    inc (hl)
                    ld a,(hl)
                    cp 50
                    jp c,TTeclas
                    ld (hl),0
                    call MaisSeg
                    ld a,(Minutos)      ; o tempo maximo, em minutos
                    or a
                    jp z,TTeclas
                    ld hl,Min
                    cp (hl)
                    jp z,Acabou
                    jp c,Acabou
TTeclas             call Teclas
                    jp Toca
; Z = nada; senao salta (N, B, BREAK) ou faz a pausa
Teclas              ld a,7Fh            ; B N M Sym Espaco
                    in a,(0FEh)
                    bit 3,a             ; N: o seguinte
                    jr z,SegueP
                    bit 4,a             ; B: o anterior
                    jr z,AnteriorP
                    rra                 ; Espaco + Caps Shift: BREAK
                    jr c,TSemBrk
                    ld a,0FEh
                    in a,(0FEh)
                    rra
                    jr nc,BrkP
TSemBrk             ld a,0EFh           ; 6 / 7 (setas baixo / cima) com o bit 2 do CFG: o seguinte / o anterior
                    in a,(0FEh)
                    cpl
                    and 18h
                    jr z,TSemSet
                    ld b,a
                    ld a,(Opc)
                    and 4
                    jr z,TSemSet
                    bit 4,b
                    jr nz,SegueP
                    jr AnteriorP
TSemSet             ld a,0DFh           ; P: pausa
                    in a,(0FEh)
                    rra
                    ret c
                    call PT3ORG+6       ; MUTE
PPsolta             ld a,0DFh
                    in a,(0FEh)
                    rra
                    jr nc,PPsolta
PPesp               ld a,7Fh
                    in a,(0FEh)
                    bit 3,a
                    jr z,SegueP
                    bit 4,a
                    jr z,AnteriorP
                    rra
                    jr c,PPsemBrk
                    ld a,0FEh
                    in a,(0FEh)
                    rra
                    jr nc,BrkP
PPsemBrk            ld a,0DFh
                    in a,(0FEh)
                    rra
                    jr c,PPesp
PPsolta2            ld a,0DFh
                    in a,(0FEh)
                    rra
                    jr nc,PPsolta2
                    ret                 ; continua (o PLAY seguinte volta a por o volume)
SegueP              pop hl              ; (sai da chamada do Teclas)
                    jr Seguinte
AnteriorP           pop hl
                    jr Anterior
BrkP                pop hl
                    jr Brk
Acabou              ld a,(Opc)          ; o seguinte (bit 1) ou so' parar
                    and 2
                    jr z,Brk
Seguinte            ld bc,1             ; o ficheiro seguinte
                    jr Navega
Anterior            ld bc,2             ; o anterior
Navega              ld (NavBC),bc
                    call Sai
                    ld bc,(NavBC)
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS|PLUGIN_NAVIGATE
                    ret
Brk                 call Sai
                    ld bc,0
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS
                    ret
; o AY calado, o IM 1 e o I de antes (com DI, como o NAV chamou), e a pilha do Inicio
Sai                 di
                    call PT3ORG+6       ; MUTE
                    im 1
                    ld a,(Ivelho)
                    ld i,a
                    pop hl              ; o retorno do Sai
                    pop iy
                    pop ix
                    jp (hl)
Isr                 ei
                    ret

ErroAbre            pop iy
                    pop ix
                    ld bc,TxtAbre
                    ld a,PLUGIN_ERROR|PLUGIN_MSG
                    ret
ErroLe              pop iy
                    pop ix
                    ld bc,TxtLe
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret
ErroGrande          pop iy
                    pop ix
                    ld bc,TxtGrande
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret

; mais um segundo e o relogio no ecra
MaisSeg             ld hl,Seg
                    inc (hl)
                    ld a,(hl)
                    cp 60
                    jr c,Relogio
                    ld (hl),0
                    ld hl,Min
                    ld a,(hl)
                    cp 99
                    jr nc,Relogio
                    inc (hl)
; "mm:ss" no canto de cima a' direita: colunas 27-31 (ecra normal) ou 59-63 (hi-res do NAVHR)
Relogio             ld a,(Hires)
                    or a
                    ld c,27
                    jr z,RLc
                    ld c,59
RLc                 ld a,(Min)
                    call Dois
                    ld a,10             ; ':'
                    call Letra
                    ld a,(Seg)
Dois                ld b,0              ; A -> dois algarismos nas colunas C e C+1
DSd                 cp 10
                    jr c,DSu
                    sub 10
                    inc b
                    jr DSd
DSu                 push af
                    ld a,b
                    call Letra
                    pop af
; a letra A (0-9, 10 = ':') na coluna C da linha 0; C avanca
Letra               push bc
                    add a,a
                    add a,a
                    add a,a
                    ld e,a
                    ld d,0
                    ld hl,Algarismos
                    add hl,de
                    ld a,(Hires)
                    or a
                    ld a,c
                    ld de,4000h
                    jr z,LTn
                    srl a               ; hi-res: as colunas pares em 4000h, as impares em 6000h
                    jr nc,LTn
                    ld d,60h
LTn                 add a,e
                    ld e,a
                    ld b,8
LTl                 ld a,(hl)
                    ld (de),a
                    inc hl
                    inc d               ; linha seguinte do ecra (+256)
                    djnz LTl
                    pop bc
                    inc c
                    ret
Algarismos          db 3Ch,66h,6Eh,76h,66h,66h,3Ch,00h   ; 0
                    db 18h,38h,18h,18h,18h,18h,3Ch,00h   ; 1
                    db 3Ch,66h,06h,0Ch,18h,30h,7Eh,00h   ; 2
                    db 3Ch,66h,06h,1Ch,06h,66h,3Ch,00h   ; 3
                    db 0Ch,1Ch,3Ch,6Ch,7Eh,0Ch,0Ch,00h   ; 4
                    db 7Eh,60h,7Ch,06h,06h,66h,3Ch,00h   ; 5
                    db 1Ch,30h,60h,7Ch,66h,66h,3Ch,00h   ; 6
                    db 7Eh,06h,0Ch,18h,30h,30h,30h,00h   ; 7
                    db 3Ch,66h,66h,3Ch,66h,66h,3Ch,00h   ; 8
                    db 3Ch,66h,66h,3Eh,06h,0Ch,38h,00h   ; 9
                    db 00h,18h,18h,00h,18h,18h,00h,00h   ; ':'
FH                  db 0
Opc                 db 2
Minutos             db 0
Frac                db 0
Seg                 db 0
Min                 db 0
Hires               db 0
Ivelho              db 0
NavBC               dw 0
PosAnt              dw 0
TxtAbre             db "PT3: nao abre o ficheiro",0
TxtLe               db "PT3: erro a ler o ficheiro",0
TxtGrande           db "PT3: grande demais (22K)",0

; o leitor (o mesmo do NAVPT3.BIN): PT3ORG+0 Inicia (HL), +3 PLAY, +6 MUTE
PT3ORG              equ $
                    DEFINE PT3DENTRO
                    include "../navpt3/navpt3.asm"
                    assert $ <= 0A000h
