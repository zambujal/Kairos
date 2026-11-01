; MOD: plugin do navegador (formato dos plugins do Bob Fossil) que toca um .MOD no General Sound.
; O ficheiro vai byte a byte para o GS pelas portas do Spectrum (xxBB comando/estado, xxB3 dados):
;   F3h (reinicio quente: liberta os modulos), 30h (carregar modulo; o GS responde o numero),
;   os bytes do ficheiro, D2h (fim), e o numero do modulo + 31h (tocar). O GS continua a tocar depois
;   de o plugin voltar ao navegador. Estado (IN xxBB): bit 7 = dado por tirar, bit 0 = comando por tirar.
; v2 (00:25): o ciclo de envio apertado (~72 T por byte, o dobro da velocidade).
; v3 (00:30): fica a' espera do fim (o GS da' a volta a' posicao da cancao: comando 60h) e pede o ficheiro
;   seguinte (PLUGIN_NAVIGATE, BC = 1); o BREAK (Caps + Espaco, tambem o F4/F6/F7 do ESP) para o modulo e volta.
; v5 (00:40): a espera por cada byte volta a contar so' esse byte (corrige o v2-v4).
; v4 (00:35): opcoes no /BIN/BPLUGINS/CFG/MOD.CFG (o navegador passa-o em DE; editar com o .plugcfg e o MOD.INI):
;   byte 0 bit 0 = repetir (nao acaba; so' o BREAK sai), bit 1 = no fim, o ficheiro seguinte (por omissao 1);
;   byte 1 = tempo maximo em minutos (0 = sem limite): ao fim desse tempo conta como o fim da musica.
; Memoria: codigo em 8000h; o ficheiro passa em bocados de 4K por A3E0h (PLUGIN_RESTORE_BUFFERS).
; v6 (2026-10-29): a posicao (60h) so' conta depois de o GS a por a 0 (a cancao nova a andar): logo a seguir
;   ao 31h a primeira leitura podia trazer a posicao do modulo anterior e a seguinte (0) parecia "voltou para
;   tras" -> o 2.o MOD acabava em 1-2 s. Espera ate' 2 s pelo 0; e no fim diz em que posicao acabou (mensagem).
; v7 (2026-11-01): a tocar, o N passa ao MOD seguinte da pasta (como no fim). Com o NAV v45 o navegador
;   hi-res fica no ecra enquanto o MOD toca (antes ficava tudo branco).
; v8 (2026-11-01): P pausa / continua (32h / 33h), B o anterior, N o seguinte; o tempo (mm:ss) no canto de
;   cima a' direita; o fim tambem quando a cancao fica parada 5 s (o F00 do MOD para o GS e a posicao nao
;   volta para tras: ficava a' espera para sempre). Sai o diagnostico do v6 (a posicao final no ecra).
; (Timorphius, 2026-10-26)

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_NAVIGATE     equ 8
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

BUF                 equ 0A3E0h
BOCADO              equ 4096
GS_CMD              equ 0BBh
GS_DAT              equ 0B3h

                    org 8000h
                    jr Inicio
                    db "BP",0,0
                    db 0                ; flags
                    db 0                ; flags2
                    db "MOD (GS) - Timorphius",0

Inicio              push ix
                    push iy
                    push hl             ; (v8) BC = os parametros do NAV: o 3.o byte 'H' = hi-res
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
SemCfg
                    ld a,'*'            ; HL = nome do ficheiro
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ; reinicio quente do GS (liberta o que estava carregado)
                    ld a,0F3h
                    call Comando
                    jp c,ErroGS
                    ld de,0             ; o INITVAR leva um bocadinho (~0,2 s; o plugin corre com DI: sem HALT)
Pausa               dec de
                    ld a,d
                    or e
                    jr nz,Pausa
                    ; carregar modulo: o GS responde o numero do modulo
                    ld a,30h
                    call Comando
                    jp c,ErroGS
                    in a,(GS_DAT)
                    ld (Modulo),a
                    ; os bytes do ficheiro
Bloco               ld a,(FH)
                    ld hl,BUF
                    ld bc,BOCADO
                    rst 08h
                    db F_READ
                    jp c,ErroLe
                    ld a,b
                    or c
                    jr z,Fim            ; acabou o ficheiro
                    ld hl,BUF
                    ld d,b              ; DE = bytes lidos
                    ld e,c
                    ld bc,0             ; BC = contador do tempo de espera
; (v2) o ciclo apertado: ~72 T por byte em vez de ~144 (o dobro da velocidade)
Byte                in a,(GS_CMD)       ; o GS ja' tirou o anterior? (bit 7 a 0)
                    rla
                    jr c,Espera
                    ld a,(hl)
                    out (GS_DAT),a
                    ld bc,0             ; (v5) o tempo de espera conta por byte (no v2-v4 era para o ficheiro todo:
                    inc hl              ;  num MOD grande acabava em "o GS nao responde" a meio)
                    dec de
                    ld a,d
                    or e
                    jr nz,Byte
                    jr Bloco
Espera              dec bc              ; o GS nao tira: desiste ao fim de ~65536 voltas
                    ld a,b
                    or c
                    jr nz,Byte
                    jp ErroGS
Fim                 ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    call EsperaDado     ; o ultimo byte ja' foi tirado?
                    jp c,ErroGS2
                    ld a,0D2h           ; fim do modulo
                    call Comando
                    jp c,ErroGS2
                    ; tocar o modulo
                    call EsperaDado
                    jp c,ErroGS2
                    ld a,(Modulo)
                    out (GS_DAT),a
                    ld a,31h
                    call Comando
                    jp c,ErroGS2
                    xor a
                    ld (Pos),a
                    ld (PosAnt),a
                    ld b,40             ; (v6) espera que o GS ponha a posicao a 0 (ate' 40 x 50 ms)
Esp0                push bc
                    ld de,4000
Esp0a               dec de
                    ld a,d
                    or e
                    jr nz,Esp0a
                    ld a,60h
                    call Comando
                    pop bc
                    jp c,ErroGS2
                    in a,(GS_DAT)
                    or a
                    jr z,Esp0ok
                    djnz Esp0
Esp0ok              xor a
                    ld (Frac),a
                    ld (Seg),a
                    ld (Min),a
                    ld (Parado),a
                    ld (Row),a
                    call Relogio        ; (v8) 00:00 no canto
; (v8) a tocar: passos de ~50 ms (1367 x 128 T a 3,5 MHz, com DI); em cada um as teclas, o relogio,
; a posicao (60h) e a linha do padrao (61h). Fim: a posicao volta para tras, ou a cancao parada 5 s
; (o F00 do MOD para o GS e a posicao fica na ultima).
Toca                ld de,1367
TEsp                ld a,7Fh            ; B N M Sym Espaco
                    in a,(0FEh)
                    bit 3,a             ; N: o seguinte
                    jp z,Seguinte
                    bit 4,a             ; B: o anterior
                    jp z,Anterior
                    rra                 ; Espaco + Caps Shift: BREAK
                    jr c,TSemBrk
                    ld a,0FEh
                    in a,(0FEh)
                    rra
                    jp nc,Brk
TSemBrk             ld a,0DFh           ; P: pausa
                    in a,(0FEh)
                    rra
                    jp nc,PausaP
                    dec de
                    ld a,d
                    or e
                    jr nz,TEsp
                    ld hl,Frac          ; o relogio: 20 passos = 1 s
                    inc (hl)
                    ld a,(hl)
                    cp 20
                    jr c,TPos
                    ld (hl),0
                    call MaisSeg
                    ld a,(Minutos)      ; (v4) o tempo maximo, em minutos
                    or a
                    jr z,TPos
                    ld hl,Min
                    cp (hl)
                    jp z,Acabou
                    jp c,Acabou
TPos                ld a,61h            ; a linha do padrao
                    call Comando
                    jp c,Fim2           ; o GS deixou de responder: sai
                    in a,(GS_DAT)
                    ld c,a
                    ld a,60h            ; a posicao na cancao
                    call Comando
                    jp c,Fim2
                    in a,(GS_DAT)
                    ld hl,Pos
                    cp (hl)
                    jr nz,TMudou
                    ld a,(Row)
                    cp c
                    jr nz,TMudouR
                    ld hl,Parado        ; nada mexeu
                    inc (hl)
                    ld a,(hl)
                    cp 100              ; 5 s parada: acabou
                    jp c,Toca
                    jp Acabou
TMudou              ld (hl),a           ; posicao nova
                    jr nc,TMudouR       ; para a frente
                    ld a,c
                    ld (Row),a
                    xor a
                    ld (Parado),a
                    ld a,(Opc)          ; voltou para tras: acabou. (v4) A repetir: continua
                    rra
                    jp c,Toca
                    jp Acabou
TMudouR             ld a,c
                    ld (Row),a
                    xor a
                    ld (Parado),a
                    jp Toca
; (v8) P: pausa (32h para o modulo, 33h continua); P outra vez continua, N / B / BREAK como a tocar
PausaP              ld a,32h
                    call Comando
PPsolta             ld a,0DFh
                    in a,(0FEh)
                    rra
                    jr nc,PPsolta
PPesp               ld a,7Fh
                    in a,(0FEh)
                    bit 3,a
                    jp z,Seguinte
                    bit 4,a
                    jp z,Anterior
                    rra
                    jr c,PPsemBrk
                    ld a,0FEh
                    in a,(0FEh)
                    rra
                    jp nc,Brk
PPsemBrk            ld a,0DFh
                    in a,(0FEh)
                    rra
                    jr c,PPesp
PPsolta2            ld a,0DFh
                    in a,(0FEh)
                    rra
                    jr nc,PPsolta2
                    ld a,33h
                    call Comando
                    xor a
                    ld (Parado),a
                    jp Toca
Acabou              ld a,(Opc)          ; o seguinte (bit 1) ou so' parar
                    and 2
                    jp z,Brk
Seguinte            ld bc,1             ; o ficheiro seguinte
                    jr Navega
Anterior            ld bc,2             ; (v8) o anterior
Navega              ld a,32h
                    call Comando
                    pop iy
                    pop ix
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS|PLUGIN_NAVIGATE
                    ret
Brk                 ld a,32h            ; BREAK: para o modulo e volta (quem carregou escolhe a seguir)
                    call Comando
Fim2                pop iy
                    pop ix
                    ld bc,0
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS
                    ret

; (v8) mais um segundo e o relogio no ecra
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

; manda o comando A e espera que o GS o tire (bit 0 a 0); CF = o GS nao respondeu
Comando             push bc
                    push af
                    call EsperaCmd
                    jr c,ComErro
                    pop af
                    out (GS_CMD),a
                    call EsperaCmd
                    pop bc
                    ret
ComErro             pop af
                    pop bc
                    scf
                    ret
; espera pelo bit 0 do estado a 0 (~1 s no maximo)
EsperaCmd           push de
                    ld de,0
ECv                 in a,(GS_CMD)
                    rra
                    jr nc,ECok
                    dec de
                    ld a,d
                    or e
                    jr nz,ECv
                    pop de
                    scf
                    ret
ECok                pop de
                    or a
                    ret
; espera pelo bit 7 do estado a 0 (o GS tirou o dado)
EsperaDado          push de
                    ld de,0
EDv                 in a,(GS_CMD)
                    rla
                    jr nc,EDok
                    dec de
                    ld a,d
                    or e
                    jr nz,EDv
                    pop de
                    scf
                    ret
EDok                pop de
                    or a
                    ret

ErroAbre            pop iy
                    pop ix
                    ld bc,TxtAbre
                    ld a,PLUGIN_ERROR|PLUGIN_MSG
                    ret
ErroLe              ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    pop iy
                    pop ix
                    ld bc,TxtLe
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret
ErroGS              ld a,(FH)
                    rst 08h
                    db F_CLOSE
ErroGS2             pop iy
                    pop ix
                    ld bc,TxtGS
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
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
                    db 00h,18h,18h,00h,18h,18h,00h,00h   ; ':' (v8)
FH                  db 0
PosAnt              db 0
                    db 0                ; (o ld (PosAnt),bc escreve 2 bytes)
Modulo              db 0
Pos                 db 0
Opc                 db 2
Minutos             db 0
Frac                db 0                ; (v8) passos de 50 ms, segundos, minutos
Seg                 db 0
Min                 db 0
Row                 db 0                ; (v8) a linha do padrao (61h)
Parado              db 0                ; (v8) passos sem mexer
Hires               db 0                ; (v8) 1 = o NAVHR (o bloco de parametros traz 'H')
TxtOk               db "MOD a tocar no General Sound",0
TxtAbre             db "MOD: nao abre o ficheiro",0
TxtLe               db "MOD: erro a ler o ficheiro",0
TxtGS               db "O GS nao responde (F2: General Sound)",0
