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
; v9 (2026-11-01): o tempo total da cancao ("mm:ss/mm:ss"): ao mandar o ficheiro le os efeitos Bxx (salto),
;   Dxx (quebra do padrao) e Fxx (velocidade / BPM, F00 = fim) de cada padrao (em 8800h-9FFFh) e depois
;   percorre a ordem da cancao (o E6x e o EEx nao contam: e' aproximado). So' MOD de 31 amostras com
;   M.K. / M!K! / FLT4 / 4CHN / 6CHN / 8CHN / FLT8 / OCTA; nos outros (ou com mais de ~2800 efeitos) fica
;   so' o tempo que passou.
;   Passado o tempo total + 2 s conta como o fim. CFG byte 0 bit 2 (como o PT3.CFG do Bob Fossil): as setas
;   (6 / 7) passam ao seguinte / anterior.
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
                    xor a               ; (v9) a analise comeca pelo cabecalho
                    ld (Fase),a
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
                    push bc
                    ld hl,BUF           ; (v9) o tempo da cancao: os Bxx / Dxx / Fxx dos padroes
                    ld d,b
                    ld e,c
                    call Analisa
                    pop bc
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
                    call Duracao        ; (v9) TotMin / TotSeg (TemTot = 0: nao se sabe)
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
Toca                ld de,1048          ; (v9) 1048 x 167 T = 50 ms a 3,5 MHz
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
                    ld a,0EFh           ; (v9) 6 / 7 (setas baixo / cima): o seguinte / o anterior, com o bit 2 do CFG
                    in a,(0FEh)
                    cpl
                    and 18h
                    jp nz,Setas
TSemSet             dec de
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
                    call PassouTot      ; (v9) passou o tempo da cancao + 2 s: acabou
                    jp c,Acabou
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
Setas               ld b,a
                    ld a,(Opc)
                    and 4
                    jp z,TSemSet        ; (sem o bit 2: nada)
                    bit 4,b             ; 6: baixo
                    jr nz,Seguinte
                    jr Anterior
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
RLc                 ld a,(TemTot)       ; (v9) com o tempo total: "mm:ss/mm:ss", 6 colunas mais a' esquerda
                    or a
                    jr z,RLsem
                    ld a,c
                    sub 6
                    ld c,a
                    push bc
                    ld a,c
                    add a,5
                    ld c,a
                    ld a,11             ; '/'
                    call Letra
                    ld a,(TotMin)
                    call Dois
                    ld a,10
                    call Letra
                    ld a,(TotSeg)
                    call Dois
                    pop bc
RLsem               ld a,(Min)
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

; ---------------------------------------------------------------- (v9) o tempo total da cancao
IDX                 equ 8800h           ; (v9) por padrao o inicio dos efeitos dele no POOL (mais um, o fim)
POOL                equ 8A04h           ; os efeitos: 2 bytes (linha + tipo << 6, parametro); tipo 0 = Fxx < 32
POOLFIM             equ 0A000h          ; (velocidade, F00 = fim), 1 = Fxx BPM, 2 = Bxx, 3 = Dxx
; HL = bocado, DE = bytes: Fase 0 = o cabecalho (no 1.o bocado), 1 = as celulas dos padroes, 2 = acabou
Analisa             ld a,(Fase)
                    cp 1
                    jp z,ANcel
                    ret nc              ; 2 = acabou, 3 = nao se sabe
                    ld (TemTot),a       ; (A = 0)
                    push hl             ; o cabecalho: 1084 bytes
                    ld bc,1084
                    ex de,hl
                    or a
                    sbc hl,bc
                    ex de,hl
                    pop hl
                    jp c,ANnao          ; ficheiro curto demais
                    push de
                    push hl
                    ld bc,950
                    add hl,bc
                    ld a,(hl)           ; o comprimento da cancao
                    ld (SongLen),a
                    inc hl
                    inc hl              ; 952: a ordem
                    ld de,Ordem
                    ld bc,128
                    ldir
                    ld a,(hl)           ; 1080: a assinatura
                    inc hl
                    ld e,(hl)
                    inc hl
                    ld d,(hl)
                    inc hl
                    ld l,(hl)           ; A, E, D, L = os 4 caracteres
                    ld c,4
                    cp 'M'
                    jr z,ANsig          ; M.K. / M!K!
                    cp 'F'
                    jr nz,AN2
                    ld a,l              ; FLT4 / FLT8
                    sub '0'
                    ld c,a
                    jr ANsig
AN2                 cp 'O'              ; OCTA
                    ld c,8
                    jr z,ANsig
                    ld c,a              ; 4CHN / 6CHN / 8CHN
                    ld a,d
                    cp 'H'
                    jr nz,ANnaoP
                    ld a,c
                    sub '0'
                    ld c,a
ANsig               ld a,c
                    cp 4
                    jr z,ANnc
                    cp 6
                    jr z,ANnc
                    cp 8
                    jr nz,ANnaoP
ANnc                ld (NCan),a
                    ld a,(SongLen)      ; 1..128
                    dec a
                    cp 128
                    jr nc,ANnaoP
                    ld hl,Ordem         ; o n.o de padroes: o maior da ordem + 1
                    ld b,128
                    xor a
ANmax               cp (hl)
                    jr nc,ANm2
                    ld a,(hl)
ANm2                inc hl
                    djnz ANmax
                    inc a
                    ld (NPad),a
                    xor a
                    ld (CCan),a
                    ld (CLin),a
                    ld (CPad),a
                    ld hl,POOL
                    ld (CPool),hl
                    ld (IDX),hl
                    ld a,1
                    ld (Fase),a
                    pop hl
                    pop de
                    ld bc,1084
                    add hl,bc           ; DE ja' tem menos 1084
                    jr ANcel
ANnaoP              pop hl
                    pop de
ANnao               ld a,3
                    ld (Fase),a
                    ret
; as celulas: 4 bytes (efeito no byte 2 bits 3-0, parametro no byte 3)
ANcel               ld a,d
                    or a
                    jr nz,ANc1
                    ld a,e
                    cp 4
                    ret c
ANc1                inc hl
                    inc hl
                    ld a,(hl)
                    and 0Fh
                    inc hl
                    ld c,0              ; C = o tipo << 6
                    cp 0Fh
                    jr z,ANf
                    ld c,80h
                    cp 0Bh
                    jr z,ANev
                    ld c,0C0h
                    cp 0Dh
                    jr z,ANev
                    jp ANprox
ANf                 ld a,(hl)
                    cp 32
                    jr c,ANev
                    ld c,40h
ANev                push hl
                    push de
                    ld b,(hl)           ; B = o parametro
                    ld a,(CLin)
                    or c
                    ld c,a              ; C = linha + tipo
                    ld hl,(CPool)
                    ld a,(CPad)         ; se o ultimo deste padrao e' a mesma linha e o mesmo tipo: so' o parametro
                    call IdxDe          ; DE = o inicio deste padrao
                    or a
                    push hl
                    sbc hl,de
                    pop hl
                    jr z,ANnovo
                    dec hl
                    dec hl
                    ld a,(hl)
                    inc hl
                    cp c
                    jr nz,ANnovo1
                    ld (hl),b
                    jr ANevf
ANnovo1             inc hl
ANnovo              push hl
                    ld de,POOLFIM-2
                    or a
                    sbc hl,de
                    pop hl
                    jr nc,ANcheio
                    ld (hl),c
                    inc hl
                    ld (hl),b
                    inc hl
                    ld (CPool),hl
ANevf               pop de
                    pop hl
                    jr ANprox
ANcheio             pop de              ; demais efeitos: nao se sabe
                    pop hl
                    jr ANnao
ANprox              inc hl
                    dec de
                    dec de
                    dec de
                    dec de
                    ld a,(NCan)
                    ld b,a
                    ld a,(CCan)
                    inc a
                    cp b
                    jr c,ANcok
                    ld a,(CLin)         ; linha seguinte
                    inc a
                    cp 64
                    jr c,ANlok
                    ld a,(CPad)         ; padrao seguinte: o inicio dele no IDX
                    inc a
                    ld (CPad),a
                    push hl
                    push de
                    ld l,a
                    ld h,0
                    add hl,hl
                    ld de,IDX
                    add hl,de
                    ld de,(CPool)
                    ld (hl),e
                    inc hl
                    ld (hl),d
                    pop de
                    pop hl
                    ld b,a
                    ld a,(NPad)
                    cp b
                    jr z,ANacab         ; acabaram os padroes (o resto sao as amostras)
                    xor a
ANlok               ld (CLin),a
                    xor a
ANcok               ld (CCan),a
                    jp ANcel
ANacab              ld a,2
                    ld (Fase),a
                    ret
; A = padrao -> DE = IDX[A]
IdxDe               push hl
                    ld l,a
                    ld h,0
                    add hl,hl
                    ld de,IDX
                    add hl,de
                    ld e,(hl)
                    inc hl
                    ld d,(hl)
                    pop hl
                    ret

; depois do ficheiro: percorre a ordem da cancao com os efeitos guardados
Duracao             ld a,(Fase)
                    cp 2
                    ret nz              ; os padroes nao chegaram todos, ou nao se sabe
                    ld a,6
                    ld (Veloc),a
                    ld a,125
                    ld (Bpm),a
                    call RecalcLinha
                    ld hl,0
                    ld (Tot),hl
                    ld (Tot+2),hl
                    xor a
                    ld (SPos),a
                    ld (SLin0),a
                    ld (Volta),a
DUpos               ld a,(SongLen)
                    ld b,a
                    ld a,(SPos)
                    cp b
                    jp nc,DUfim
                    ld hl,Volta         ; no maximo 255 posicoes (saltos em ciclo)
                    inc (hl)
                    jp z,DUfim
                    ld e,a              ; o padrao desta posicao
                    ld d,0
                    ld hl,Ordem
                    add hl,de
                    ld a,(hl)
                    push af
                    inc a
                    call IdxDe
                    ld (SFimEv),de      ; o fim dos efeitos dele
                    pop af
                    call IdxDe
                    ex de,hl            ; HL = o primeiro
                    ld a,(SLin0)
                    ld (SCur),a
                    ld a,(SPos)
                    inc a
                    ld (SProx),a
                    xor a
                    ld (SLinP),a
                    ld (SQue),a         ; bit 0 quebra / salto, bit 1 fim (F00), bit 2 houve salto B
                    ld a,0FFh
                    ld (SGrupo),a
DUev                ld de,(SFimEv)
                    or a
                    push hl
                    sbc hl,de
                    pop hl
                    jr z,DUevf
                    ld a,(SLin0)
                    ld c,a
                    ld a,(hl)
                    and 3Fh             ; a linha
                    cp c
                    jr c,DUsalta        ; antes de onde se entrou no padrao
                    ld c,a
                    ld a,(SGrupo)
                    cp c
                    jr z,DUmesma
                    ld a,(SQue)         ; linha nova: se a anterior quebrou, acaba aqui
                    or a
                    jr nz,DUquebra
                    ld a,c
                    ld (SGrupo),a
                    push hl
                    ld a,(SCur)
                    ld e,a
                    ld a,c
                    sub e
                    call MaisLinhas     ; as linhas ate' esta, com a velocidade de antes
                    pop hl
                    ld a,(SGrupo)
                    ld (SCur),a
DUmesma             ld a,(hl)           ; o tipo
                    inc hl
                    ld c,(hl)           ; o parametro
                    dec hl
                    push hl
                    call DUefeito
                    pop hl
DUsalta             inc hl
                    inc hl
                    jr DUev
DUevf               ld a,(SQue)
                    or a
                    jr nz,DUquebra
                    ld a,(SCur)         ; o resto do padrao
                    ld e,a
                    ld a,64
                    sub e
                    call MaisLinhas
                    ld a,(SPos)
                    inc a
                    ld (SPos),a
                    xor a
                    ld (SLin0),a
                    jp DUpos
DUquebra            ld a,1              ; a linha da quebra conta
                    call MaisLinhas
                    ld a,(SQue)
                    bit 1,a
                    jp nz,DUfim         ; F00
                    bit 2,a
                    jr z,DUsemB
                    ld a,(SPos)         ; salto para tras ou para a mesma: deu a volta
                    ld b,a
                    ld a,(SProx)
                    cp b
                    jp c,DUfim
                    jp z,DUfim
DUsemB              ld a,(SProx)
                    ld (SPos),a
                    ld a,(SLinP)
                    cp 64
                    jr c,DUl
                    xor a
DUl                 ld (SLin0),a
                    jp DUpos
; A = linha + tipo << 6, C = parametro
DUefeito            and 0C0h
                    jr nz,DUe1
                    ld a,c              ; tipo 0: velocidade (F00 = fim)
                    or a
                    jr nz,DUf1
                    ld hl,SQue
                    set 1,(hl)
                    ret
DUf1                ld (Veloc),a
                    jp RecalcLinha
DUe1                cp 40h
                    jr nz,DUe2
                    ld a,c              ; tipo 1: BPM
                    ld (Bpm),a
                    jp RecalcLinha
DUe2                cp 80h
                    jr nz,DUe3
                    ld a,c              ; Bxx: a posicao xx, linha 0 (ou a do Dxx da mesma linha)
                    ld (SProx),a
                    ld hl,SQue
                    set 0,(hl)
                    set 2,(hl)
                    ret
DUe3                ld a,c              ; Dxy: a linha x*10+y do padrao seguinte
                    and 0F0h
                    rrca
                    ld b,a              ; x * 8
                    rrca
                    rrca                ; x * 2
                    add a,b             ; x * 10
                    ld b,a
                    ld a,c
                    and 0Fh
                    add a,b
                    ld (SLinP),a
                    ld hl,SQue
                    set 0,(hl)
                    ret
DUfim               ld hl,(Tot)         ; Tot (decimas de ms) / 10000 = segundos
                    ld de,(Tot+2)
                    ld bc,0
DUdiv               ld a,l
                    sub 10000 & 0FFh
                    ld l,a
                    ld a,h
                    sbc a,10000 >> 8
                    ld h,a
                    ld a,e
                    sbc a,0
                    ld e,a
                    ld a,d
                    sbc a,0
                    ld d,a
                    jr c,DUdv2
                    inc bc
                    jr DUdiv
DUdv2               ld h,b              ; HL = segundos
                    ld l,c
                    ld a,h
                    or l
                    ret z
                    ld b,0              ; minutos
                    ld de,60
DUmin               or a
                    sbc hl,de
                    jr c,DUm2
                    inc b
                    jr DUmin
DUm2                add hl,de
                    ld a,l
                    ld (TotSeg),a
                    ld a,b
                    cp 100
                    jr c,DUm3
                    ld a,99
DUm3                ld (TotMin),a
                    ld a,1
                    ld (TemTot),a
                    ret
; RowT = Veloc x (25000 / Bpm) decimas de ms
RecalcLinha         ld hl,25000
                    ld a,(Bpm)
                    ld c,a
                    ld de,0             ; DE = quociente
RCd                 or a
                    ld b,0
                    sbc hl,bc
                    jr c,RCd2
                    inc de
                    jr RCd
RCd2                ld a,(Veloc)
                    ld b,a
                    ld hl,0
RCm                 add hl,de
                    djnz RCm
                    ld (RowT),hl
                    ret
; Tot += A x RowT
MaisLinhas          or a
                    ret z
                    ld b,a
MLs                 ld hl,(Tot)
                    ld de,(RowT)
                    add hl,de
                    ld (Tot),hl
                    jr nc,MLs2
                    ld hl,(Tot+2)
                    inc hl
                    ld (Tot+2),hl
MLs2                djnz MLs
                    ret
; CF = o tempo que passou ja' vai no total + 2 s
PassouTot           ld a,(TemTot)
                    or a
                    ret z               ; (CF = 0)
                    ld a,(TotMin)
                    ld b,a
                    ld a,(Min)
                    cp b
                    ccf
                    ret nz              ; minutos diferentes: CF = Min > TotMin
                    ld a,(TotSeg)
                    add a,2
                    ld b,a
                    ld a,(Seg)
                    cp b
                    ccf
                    ret
Fase                db 2
SongLen             db 0
NCan                db 4
NPad                db 0
CCan                db 0
CLin                db 0
CPad                db 0
CPool               dw 0
SFimEv              dw 0
Veloc               db 6
Bpm                 db 125
RowT                dw 0
Tot                 dw 0,0
SPos                db 0
SLin0               db 0
SCur                db 0
SProx               db 0
SLinP               db 0
SQue                db 0
SGrupo              db 0
Volta               db 0
Ordem               ds 128

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
                    db 00h,06h,0Ch,18h,30h,60h,00h,00h   ; '/' (v9)
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
TemTot              db 0                ; (v9) 1 = TotMin / TotSeg validos
TotMin              db 0
TotSeg              db 0
TxtOk               db "MOD a tocar no General Sound",0
TxtAbre             db "MOD: nao abre o ficheiro",0
TxtLe               db "MOD: erro a ler o ficheiro",0
TxtGS               db "O GS nao responde (F2: General Sound)",0
                    assert $ <= IDX     ; (v9) o codigo antes do IDX / POOL
