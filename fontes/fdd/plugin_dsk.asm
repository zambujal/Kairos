; DSK (/BIN/BPLUGINS/DSK): plugin do navegador (formato dos plugins do Bob Fossil) que mete um disco TOS (.DSK de CPC
; normal ou EXTENDED, 16 sectores de 256 numerados 0-15; os .dsk do +3 / CPC sao recusados) na Timex FDD3000 (core 87+).
; So' le' o cartao.
; (v87) A FDD liga-se antes, no menu das maquinas do navegador, com a placa da maquina: FDD SPECTRUM (TIMEX 2048,
; ZX 48K: a ROM do TI da Stavi) ou FDD TC2068 (a ROM do TI da TMX); o /BIN/FDD3000 carrega a ROM do TI e o arranque da
; FDD. Sem a FDD ligada o plugin da' erro e nao faz nada.
;   - a FDD sem o TOS (acabada de ligar, a' espera de um disco): o disco para a memoria da FDD (a partir de 100000h,
;     no sitio ((pista*2 + face)*16 + sector)*256: 256 bytes por sector, sectores 0-15, ate' 84 pistas e 2 faces; o
;     fdd3000.vhd le-os dai'), o reset do Z80 da FDD (le' o disco novo), a espera do TOS e o reset do Timex: a
;     maquina arranca pelo Timex Interface e o TOS.
;   - (88e) com o TOS a correr na FDD, ENTER noutro .DSK so' troca o disco (a FDD em pausa) e volta-se ao jogo.
;     Num disco de duas faces em dois .DSK (o _2 e' o "lado B"): ENTER no outro .DSK.
;   - (88h) Com CAPS SHIFT + ENTER, ou num disco de sistema do CP/M (o sector 0 comeca por ED 56), a troca acaba com o
;     reset so' da FDD (o botao do controlador): o CP/M arranca com o Monitor Emulator (TMX Portugal).
; Para tirar a FDD: o RESET+NMI (Ctrl+Alt+Shift) ou outra maquina no menu.
; Os discos ficam na memoria: o que o TOS grava perde-se ao desligar (por agora nao volta ao cartao).
; So' no TIMEX 2048 e no TC2068 (no ZX 128K e no Pentagon a memoria de 8000h e' outra: recusa).
; (v89) O Z80 a 14 MHz enquanto passa o disco para a FDD (ZXUNO A6h = 4, como o plugin TZX; a leitura do cartao
; continua a 3,5 MHz: o core abranda sozinho perto do cartao) e a copia de cada sector desenrolada (25 T por byte em
; vez de 56). Uma barra de progresso no meio do ecra (o navegador deixa-o limpo enquanto o plugin corre).
; (Kairos, 2026-11-06)
; Monta-se com  sjasmplus -I../nav --raw=DSK plugin_dsk.asm

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

BUF                 equ 0A3E0h          ; uma pista inteira do .DSK (ate' 20K). (88f) nao em A000h-A3DFh: e' o trampolim do
                                        ; navegador (o plugin so' pode usar 8000h-9FFFh e A3E0h-FFFFh); com o BUF em A000h a
                                        ; troca do disco (e os erros) voltavam ao navegador por cima de dados e encravava
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
                    ld a,0FEh           ; (88h) CAPS SHIFT + ENTER no navegador: troca o disco e faz o reset da FDD
                    in a,(0FEh)         ; (o botao do controlador; o CP/M e outros sistemas arrancam assim)
                    cpl
                    and 1
                    ld (FddRst),a
                    in a,(0F4h)         ; so' no TIMEX 2048 (F4 = F0h e' o ZX 128K / Pentagon)
                    cp 0F0h
                    jp z,ErroMaq
                    ; (88e) o TOS ja' a correr na FDD (o jogo pediu outra disquete): so' se troca o disco, sem reset
                    call VeTOS
                    jr c,Arranque
                    ld a,1
                    ld (Troca),a
                    ld (Pausou),a
                    di
                    ld a,19h            ; A7h = 19h: a FDD com disco, em pausa (o Z80 dela parado sem reset)
                    call SetA7
                    jp Disco
                    ; o arranque: a FDD ligada (a placa do menu das maquinas) mas sem o TOS. Com a FDD em pausa
                    ; (A7h bit 0 = 1, a sessao do NMI) o 0008h e' do esxDOS (o TI nao entra)
Arranque            in a,(0EFh)         ; (v87) sem a FDD o porto EF da' FFh: a placa liga-se no menu das maquinas
                    inc a
                    jp z,ErroDesl
                    di
                    ld a,19h            ; A7h = 19h: a FDD com disco, em pausa (o Z80 dela parado) enquanto se carrega
                    call SetA7
                    ld a,1
                    ld (Pausou),a
                    ; ------------------------------------------------ o disco
Disco               ld hl,(Nome)
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ld a,1
                    ld (Aberto),a
                    ld a,4              ; (v89) o Z80 a 14 MHz enquanto passa o disco (A6h bit 2)
                    call SetA6
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
                    ld (TotP),hl
                    call BarraIni       ; (v89) a barra de progresso
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
                    call BarraPasso     ; (v89) mais uma pista
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
                    ld a,(PT)           ; (88h) o sector 0 da pista 0, face 0: o disco de sistema do CP/M (TMX Portugal)?
                    ld e,a
                    ld a,(PF)
                    or e
                    or (ix+2)
                    jr nz,SNaoCpm
                    ld a,(hl)           ; ED 56 3E 5F = IM 1; LD A,5Fh (o arranque do CP/M): a FDD tem de reiniciar
                    cp 0EDh
                    jr nz,SNaoCpm
                    inc hl
                    ld a,(hl)
                    dec hl
                    cp 56h
                    jr nz,SNaoCpm
                    ld a,1
                    ld (FddRst),a
SNaoCpm
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
                    jp Sector

; ---------------------------------------------------------------- o fim: a maquina com a FDD e o reset
Fim                 xor a               ; (v89) o Z80 a' velocidade dele
                    call SetA6
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    di
                    ld a,(Troca)        ; (88e) na troca: a FDD sai da pausa com o disco novo e volta-se ao jogo
                    or a
                    jr z,FimArr
                    ld a,9
                    call SetA7
                    ld bc,TxtTroca
                    ld a,(FddRst)       ; (88h) o reset da FDD: o Z80 dela volta a' ROM de arranque e le' o sector 0
                    or a
                    jp z,FimSai
                    ld a,1
                    call SetA0
                    ld b,0
FRw                 djnz FRw
                    xor a
                    call SetA0
                    ld bc,TxtTrocaR
                    jp FimSai
FimArr
                    ld a,9              ; A7h = 9: a FDD (o Z80 do GS e' o da FDD) com o disco (bit 3, core 88)
                    call SetA7
                    ld a,1              ; (v87) o reset do Z80 da FDD: volta a' ROM de arranque e le' o disco novo
                    call SetA0
                    ld b,0
FAw                 djnz FAw
                    xor a               ; A0h = 0: o Z80 da FDD arranca
                    call SetA0
                    ; (87f) espera que a FDD tenha o TOS pronto: com ele a espera do Timex o porto EF alterna 00 e 40h
                    ; (o navegador corre mais depressa que 3,5 MHz: uma espera contada em voltas nao serve). se nunca aparecer o 40h: o diagnostico (o que se leu) e sem reset
                    ld hl,0
                    ld (C00),hl
                    ld (C40),hl
                    ld a,1              ; (87f) o border azul: a espera pela FDD
                    out (0FEh),a
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
                    ld a,2              ; o border vermelho: a FDD nao ficou pronta
                    out (0FEh),a
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
FddPronta           ld a,4              ; o border verde: a FDD pronta
                    out (0FEh),a
                    ld bc,0FC3Bh
                    ld a,0A5h           ; A5h: o reset quando o navegador sair (o TC2048 arranca pelo TI; core 87)
                    out (c),a
                    inc b
                    out (c),a
                    ld a,0Dh            ; (88) A7h = 0Dh: FDD, disco e o reset ja' (bit 2): a maquina FDD3000
                    call SetA7          ; arranca logo pelo Timex Interface, sem voltar ao navegador
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
ErroDesl            ld hl,TxtDesl
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
                    xor a               ; (v89) o Z80 a' velocidade dele
                    call SetA6
                    ld a,(Aberto)
                    or a
                    jr z,ESemF
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
ESemF               ld a,(Pausou)       ; (v87) a FDD so' se mexe se o plugin a pos em pausa
                    or a
                    jr z,ESnada
                    ld a,(Troca)        ; (88e) na troca: a FDD continua (sai da pausa) com o disco
                    or a
                    ld a,9
                    jr nz,ESa7
                    ld a,1              ; (v87) no arranque: a FDD continua ligada, sem disco
ESa7                call SetA7
ESnada              xor a
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
; (88e) CF = 0 se o TOS ja' corre na FDD (o porto EF muda: a espera do Timex alterna 00h/40h); CF = 1 se nao
; (FFh: sem a FDD; sempre 00h: a FDD sem disco, o arranque dela a' espera)
VeTOS               in a,(0EFh)
                    cp 0FFh
                    scf
                    ret z
                    ld d,a
                    ld e,0
                    ld bc,0             ; 65536 leituras
VTl                 in a,(0EFh)
                    cp d
                    jr z,VTi
                    ld d,a
                    inc e
                    jr nz,VTi
                    dec e               ; satura em FFh
VTi                 dec bc
                    ld a,b
                    or c
                    jr nz,VTl
                    ld a,e
                    cp 4                ; CF = menos de 4 mudancas
                    ret
; (v89) ZXUNO A6h = A (bit 2: o Z80 a 14 MHz)
SetA6               push bc
                    push af
                    ld bc,0FC3Bh
                    ld a,0A6h
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    pop bc
                    ret
; (v89) a barra de progresso, no meio do ecra (durante o plugin o navegador deixa o ecra limpo): 8 linhas de pontos
; na linha de texto 12 (4880h-4F9Fh), com uma linha por cima (95: 4F60h) e outra por baixo (104: 48A0h). No hi-res
; (porta FF = xxxxx110) 64 colunas: as pares em 4000h, as impares em 6000h. Anda por Bresenham: em cada pista,
; Err += Larg; enquanto Err >= TotP: Err -= TotP e acende a coluna seguinte.
BarraIni            in a,(0FFh)         ; o modo do ecra (no TC2048 / TC2068 a FF le-se)
                    and 7
                    cp 6
                    ld a,32
                    jr nz,BIn
                    ld a,64
BIn                 ld (Larg),a
                    ld hl,0
                    ld (Err),hl
                    xor a
                    ld (Col),a
                    ld c,a              ; o fundo da barra limpo e as linhas de cima e de baixo, em todas as colunas
BIa                 ld a,c
                    call BarraEnd
                    ld a,48h
                    add a,d
                    ld h,a
                    ld a,80h
                    add a,e
                    ld l,a
                    ld b,8
BIz                 ld (hl),0
                    inc h
                    djnz BIz
                    ld a,4Fh            ; a linha de cima (95)
                    add a,d
                    ld h,a
                    ld a,60h
                    add a,e
                    ld l,a
                    ld (hl),0FFh
                    ld a,48h            ; a linha de baixo (104)
                    add a,d
                    ld h,a
                    ld a,0A0h
                    add a,e
                    ld l,a
                    ld (hl),0FFh
                    inc c
                    ld a,(Larg)
                    cp c
                    jr nz,BIa
                    ret
BarraPasso          ld a,(Larg)         ; Err += Larg
                    ld e,a
                    ld d,0
                    ld hl,(Err)
                    add hl,de
BPl                 ld de,(TotP)
                    or a
                    sbc hl,de
                    jr c,BPf            ; Err < TotP
                    push hl
                    ld a,(Col)
                    ld c,a
                    ld a,(Larg)
                    cp c
                    jr z,BPc            ; (ja' esta' cheia)
                    ld a,c
                    call BarraCol
                    ld hl,Col
                    inc (hl)
BPc                 pop hl
                    jr BPl
BPf                 add hl,de
                    ld (Err),hl
                    ret
; A = coluna: acende-a (as 8 linhas)
BarraCol            call BarraEnd
                    ld a,48h
                    add a,d
                    ld h,a
                    ld a,80h
                    add a,e
                    ld l,a
                    ld b,8
BCl                 ld (hl),0FFh
                    inc h
                    djnz BCl
                    ret
; A = coluna -> D = 0 ou 20h (no hi-res as impares em 6000h), E = a coluna no banco
BarraEnd            ld e,a
                    ld d,0
                    ld a,(Larg)
                    cp 64
                    ret nz
                    srl e
                    ret nc
                    ld d,20h
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
SetA0               push bc             ; (88h) A0h: bit 0 = o Z80 do GS (a FDD) parado em reset
                    push af
                    ld bc,0FC3Bh
                    ld a,0A0h
                    out (c),a
                    inc b
                    pop af
                    out (c),a
                    pop bc
                    ret
; DE bytes de HL para a memoria do GS / FDD (A1h, o ponteiro avanca sozinho)
; (v89) DE = 256 (um sector): 16 voltas de 16 bytes, 25 T por byte (antes 56)
Envia               ld bc,0FC3Bh
                    ld a,0A1h
                    out (c),a
                    inc b
                    ld e,16
EV16                rept 16
                    ld a,(hl)
                    out (c),a
                    inc hl
                    endr
                    dec e
                    jr nz,EV16
                    ret
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

TxtOk               db "FDD3000: o TOS arranca",0
TxtTroca            db "FDD3000: disco trocado",0
TxtTrocaR           db "FDD3000: disco trocado, FDD reiniciada",0
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
TxtDesl             db "FDD desligada: liga a placa no menu das maquinas",0
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
Pausou              db 0   ; (v87) 1 = a FDD foi posta em pausa pelo plugin
Troca               db 0
FddRst              db 0   ; (88h) 1 = reset da FDD no fim da troca
Ext                 db 0
Faces               db 0
NPist               dw 0
TotP                dw 0                ; (v89) a barra: as pistas todas, a largura (32 ou 64), o erro, a coluna
Larg                db 32
Err                 dw 0
Col                 db 0
TabP                dw 0
PT                  db 0
PF                  db 0
PN                  db 0
NSec                db 0
DiscoI              ds 256
