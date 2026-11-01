; AY: plugin do navegador (formato dos plugins do Bob Fossil) que toca um .AY (ZXAYEMUL, as musicas tiradas
; dos jogos, com o leitor original dentro) no AY do 128 (FFFD / BFFD).
;   Como o PT3: o navegador fica no ecra (se a musica nao usar a memoria do ecra), o tempo no canto
;   ("mm:ss/mm:ss" quando o .AY traz a duracao). P pausa, N / B a musica seguinte / anterior do ficheiro
;   (no fim do ficheiro o ficheiro seguinte / anterior), BREAK para e volta. O CFG e' o do PT3 do Bob Fossil
;   (bit 0 repetir, bit 1 no fim o seguinte, bit 2 as setas 6 / 7; byte 1 o tempo maximo em minutos).
; Como corre:
;   - o ficheiro (ate' 64K) vai para as paginas 42-49 do DivMMC (por 9000h, aos bocados de 4K);
;   - 4000h-7FFFh vai para as paginas 50-51 e volta no fim (o ecra e a RAM do programa parado);
;   - os blocos da musica vao para os enderecos deles; nao podem tocar em 0000h-3FFFh (ROM), no plugin
;     (8000h-PFIM), no trampolim do NAV (A000h-A3DFh) nem em FD00h-FFFFh (o IM 2 deste plugin);
;     8000h-9FFFh e A3E0h-FFFFh o NAV repoe (pagina 12 e PLUGIN_RESTORE_BUFFERS);
;   - o INIT corre com a pilha da musica e os registos HiReg/LoReg; depois, em cada frame (HALT com o IM 2
;     deste plugin), a rotina INTERRUPT, com os registos que ela deixou da vez anterior (como o leitor
;     de referencia). Sem INTERRUPT (0) nao da'.
; (Kairos, 2026-11-01)

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_NAVIGATE     equ 8
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

STAGE               equ 9000h           ; 4K para ler o ficheiro
PFICH               equ 42              ; o ficheiro nas paginas 42-49
PSALVA              equ 50              ; 4000h-7FFFh nas paginas 50-51

                    org 8000h
                    jr Inicio
                    db "BP",0,0
                    db 0                ; flags
                    db 0                ; flags2
                    db "AY (ZXAYEMUL) - Kairos",0

Inicio              push ix
                    push iy
                    ld (SPnav),sp       ; a pilha do NAV fica em 4000h-7FFFh: o plugin usa a dele
                    ld sp,Pilha
                    ld a,i
                    ld (Ivelho),a
                    push hl
                    ld h,b              ; BC = os parametros do NAV: o 3.o byte 'H' = hi-res
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
SemCfg              call SalvaEcra      ; 4000h-7FFFh para as paginas 50-51
                    ; o ficheiro para as paginas 42-49
                    ld a,'*'            ; HL = nome do ficheiro
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ld hl,0
                    ld (Tam),hl
LFbloco             ld a,(FH)
                    ld hl,STAGE
                    ld bc,1000h
                    rst 08h
                    db F_READ
                    jp c,ErroLeF
                    ld a,b
                    or c
                    jr z,LFfim
                    push bc
                    ld hl,(Tam)         ; a pagina e o sitio: 42 + Tam / 8K, 2000h + Tam mod 8K
                    ld a,h
                    rlca
                    rlca
                    rlca
                    and 7
                    add a,80h+PFICH
                    out (0E3h),a
                    ld a,h
                    and 1Fh
                    or 20h
                    ld d,a
                    ld e,l
                    ld hl,STAGE
                    ldir
                    xor a
                    out (0E3h),a
                    pop bc
                    ld hl,(Tam)
                    add hl,bc
                    ld (Tam),hl
                    jp c,ErroGrandeF    ; mais de 64K
                    ld a,b              ; um bocado incompleto: acabou
                    cp 10h
                    jr z,LFbloco
LFfim               ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    ; o cabecalho: "ZXAYEMUL"
                    ld hl,0
                    ld de,Assin
                    ld b,8
CAb                 call RdB
                    ex de,hl
                    cp (hl)
                    ex de,hl
                    jp nz,ErroNaoAY
                    inc hl
                    inc de
                    djnz CAb
                    ld hl,16            ; NumOfSongs (o n.o - 1), FirstSong
                    call RdB
                    inc a
                    ld (NMus),a
                    inc hl
                    call RdB
                    ld (Mus),a
                    ld hl,18            ; PSongsStructure
                    call RelPtr
                    ld (TabMus),hl
                    ; o IM 2 (tabela em FE00h, salto em FDFDh)
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
Larga               xor a               ; larga as teclas (o ENTER, ou o N / B que trouxe este)
                    in a,(0FEh)
                    cpl
                    and 1Fh
                    jr nz,Larga
                    ld a,(Mus)
                    ld hl,NMus
                    cp (hl)
                    jr c,Comeca
                    xor a
                    ld (Mus),a
Comeca              call Arranca        ; a musica Mus; CF = nao da'
                    jp c,ErroMus
; um frame: HALT, a rotina da musica, o fim, o relogio, as teclas
Toca                ei
                    halt
                    di
                    call Frame
                    ld hl,(Quadros)
                    inc hl
                    ld (Quadros),hl
                    ld a,(Opc)          ; a repetir: nunca acaba
                    rra
                    jr c,TNaoFim
                    ld de,(Dur)         ; a duracao (quadros; 0 = nao se sabe)
                    ld a,d
                    or e
                    jr z,TNaoFim
                    or a
                    sbc hl,de
                    jp nc,FimMus
TNaoFim             ld hl,Frac
                    inc (hl)
                    ld a,(hl)
                    cp 50
                    jr c,TTeclas
                    ld (hl),0
                    call MaisSeg
                    ld a,(Minutos)      ; o tempo maximo, em minutos
                    or a
                    jr z,TTeclas
                    ld hl,Min
                    cp (hl)
                    jp z,FimMus
                    jp c,FimMus
TTeclas             call Teclas
                    jr Toca

; a rotina da musica com os registos dela (os que deixou da vez anterior) e a pilha dela
Frame               ld (SPmeu),sp
                    ld sp,RegsMus
                    pop af
                    pop bc
                    pop de
                    pop hl
                    pop ix
                    pop iy
                    exx
                    ex af,af'
                    pop af
                    pop bc
                    pop de
                    pop hl
                    exx
                    ex af,af'
                    ld sp,(SPmus)
                    call Salto          ; = call (Intr)
                    ld (SPmus),sp
                    ld sp,RegsMusFim
                    exx
                    ex af,af'
                    push hl
                    push de
                    push bc
                    push af
                    exx
                    ex af,af'
                    push iy
                    push ix
                    push hl
                    push de
                    push bc
                    push af
                    ld sp,(SPmeu)
                    di                  ; (a musica pode ter feito EI)
                    ret
Salto               db 0C3h             ; jp nn
Intr                dw 0

; N / B / BREAK / P / setas
Teclas              ld a,7Fh            ; B N M Sym Espaco
                    in a,(0FEh)
                    bit 3,a             ; N: a seguinte
                    jp z,SegueP
                    bit 4,a             ; B: a anterior
                    jp z,AnteriorP
                    rra                 ; Espaco + Caps Shift: BREAK
                    jr c,TSemBrk
                    ld a,0FEh
                    in a,(0FEh)
                    rra
                    jp nc,BrkP
TSemBrk             ld a,0EFh           ; 6 / 7 (setas) com o bit 2 do CFG
                    in a,(0FEh)
                    cpl
                    and 18h
                    jr z,TSemSet
                    ld b,a
                    ld a,(Opc)
                    and 4
                    jr z,TSemSet
                    bit 4,b
                    jp nz,SegueP
                    jp AnteriorP
TSemSet             ld a,0DFh           ; P: pausa
                    in a,(0FEh)
                    rra
                    ret c
                    call Cala
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
                    ret
SegueP              pop hl              ; (sai da chamada do Teclas)
                    ld a,(Mus)          ; a seguinte do ficheiro, se houver
                    inc a
                    ld hl,NMus
                    cp (hl)
                    jr nc,Seguinte
TrocaMus            ld (Mus),a
                    call Cala
                    call Espera
                    call Arranca
                    jp nc,Toca
                    jp ErroMus
AnteriorP           pop hl
                    ld a,(Mus)
                    or a
                    jr z,Anterior
                    dec a
                    jp TrocaMus
BrkP                pop hl
                    jp Brk
FimMus              ld a,(Mus)          ; acabou: a seguinte do ficheiro; no fim, como o PT3
                    inc a
                    ld hl,NMus
                    cp (hl)
                    jr c,TrocaMus
                    ld a,(Opc)          ; o ficheiro seguinte (bit 1) ou so' parar
                    and 2
                    jr z,Brk
Seguinte            ld bc,1
                    jp Navega
Anterior            ld bc,2
Navega              ld (NavBC),bc
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS|PLUGIN_NAVIGATE
                    jp Sai
Brk                 ld bc,0
                    ld (NavBC),bc
                    ld a,PLUGIN_OK|PLUGIN_RESTORE_BUFFERS
; A = o retorno, (NavBC) = BC: o AY calado, 4000h-7FFFh de volta, o IM 1 e o I de antes, a pilha do NAV
Sai                 ld (Ret),a
                    di
                    call Cala
                    im 1
                    ld a,(Ivelho)
                    ld i,a
                    call RepoeEcra      ; (a pilha do plugin esta' fora de 4000h-7FFFh)
                    ld sp,(SPnav)
                    pop iy
                    pop ix
                    ld bc,(NavBC)
                    ld a,(Ret)
                    ret
Isr                 ei
                    ret

; ~0,3 s (deixar largar a tecla entre musicas)
Espera              ld b,15
Esp1                ei
                    halt
                    djnz Esp1
                    di
                    ret

; o AY calado: volumes a 0, misturador tudo desligado
Cala                ld bc,0FFFDh
                    ld a,7
                    out (c),a
                    ld b,0BFh
                    ld a,0FFh
                    out (c),a
                    ld e,8
Cl1                 ld b,0FFh
                    out (c),e
                    ld b,0BFh
                    xor a
                    out (c),a
                    inc e
                    ld a,e
                    cp 11
                    jr c,Cl1
                    ret

; ---------------------------------------------------------------- a musica Mus
; CF = nao da' (TxtMus diz porque)
Arranca             ld hl,(TabMus)      ; SongsStructure + 4 x Mus + 2: PSongData
                    ld a,(Mus)
                    add a,a
                    add a,a
                    add a,2
                    ld e,a
                    ld d,0
                    add hl,de
                    call RelPtr         ; HL = SongData
                    ld (SData),hl
                    ld de,4             ; SongLength (quadros)
                    add hl,de
                    call RdW
                    ld (Dur),de
                    ld hl,(SData)
                    ld de,8             ; HiReg, LoReg
                    add hl,de
                    call RdB
                    ld (RegVal+1),a
                    inc hl
                    call RdB
                    ld (RegVal),a
                    inc hl              ; PPoints
                    push hl
                    call RelPtr
                    ld (PPts),hl
                    pop hl
                    inc hl
                    inc hl              ; PAddresses
                    call RelPtr
                    ld (PEnd),hl
                    ld hl,(PPts)        ; Stack, INIT, INTERRUPT
                    call RdW
                    ld (SPmus),de
                    inc hl
                    inc hl
                    call RdW
                    ld (Init),de
                    inc hl
                    inc hl
                    call RdW
                    ld (Intr),de
                    ld a,d
                    or e
                    ld hl,TxtSemInt
                    scf
                    ret z               ; sem INTERRUPT: nao da'
                    ld hl,(SPmus)       ; a pilha: SP-64 .. SP-1 tem de poder ser escrita
                    ld de,-64
                    add hl,de
                    ld bc,64
                    call Proibido
                    ld hl,TxtPilha
                    ret c
                    ld hl,(SPmus)       ; a pilha no ecra: sem relogio
                    ld de,-64
                    add hl,de
                    ld bc,64
                    call NoEcra
                    ld (SemRel),a
                    ; os blocos: primeiro ver se todos podem, depois copiar
                    xor a
                    ld (Copia),a
ABpassa             ld hl,(PEnd)
ABbloco             call RdW            ; Address (0 = fim)
                    ld a,d
                    or e
                    jr z,ABfim
                    ld (BAddr),de
                    inc hl
                    inc hl
                    call RdW            ; Length
                    ld (BLen),de
                    inc hl
                    inc hl
                    push hl
                    call RelPtr         ; o sitio no ficheiro
                    ld (BOff),hl
                    pop hl
                    inc hl
                    inc hl
                    push hl
                    call AcertaBloco    ; o comprimento dentro do ficheiro e dos 64K
                    ld a,(Copia)
                    or a
                    jr nz,ABcopia
                    ld hl,(BAddr)
                    ld bc,(BLen)
                    call Proibido
                    jr c,ABnao
                    ld hl,(BAddr)
                    ld bc,(BLen)
                    call NoEcra
                    ld hl,SemRel
                    or (hl)
                    ld (hl),a
                    ld hl,(Init)        ; sem INIT: o 1.o bloco
                    ld a,h
                    or l
                    jr nz,ABprox
                    ld hl,(BAddr)
                    ld (Init),hl
                    jr ABprox
ABcopia             ld hl,(BOff)
                    ld de,(BAddr)
                    ld bc,(BLen)
                    call CopiaF
ABprox              pop hl
                    jr ABbloco
ABnao               pop hl
                    ld hl,TxtMem
                    scf
                    ret
ABfim               ld a,(Copia)
                    or a
                    jr nz,ABcorre
                    inc a
                    ld (Copia),a
                    jr ABpassa
ABcorre             ld hl,(Init)
                    ld a,h
                    or l
                    ld hl,TxtMem
                    scf
                    ret z
                    ; os registos: todos com HiReg/LoReg (AF, BC, DE, HL, IX, IY e os outros)
                    ld hl,(RegVal)
                    ld b,12
                    ld de,RegsMus
ARr                 ld a,l
                    ld (de),a
                    inc de
                    ld a,h
                    ld (de),a
                    inc de
                    djnz ARr
                    ld hl,(Init)        ; o INIT corre como a rotina do frame, uma vez
                    ld (Intr2),hl
                    ld hl,(Intr)
                    push hl
                    ld hl,(Intr2)
                    ld (Intr),hl
                    call Frame
                    pop hl
                    ld (Intr),hl
                    ld hl,0
                    ld (Quadros),hl
                    xor a
                    ld (Frac),a
                    ld (Seg),a
                    ld (Min),a
                    ld hl,(Dur)         ; o tempo total: Dur / 50
                    ld de,0
                    ld bc,50
ADd                 or a
                    sbc hl,bc
                    jr c,ADd2
                    inc de
                    jr ADd
ADd2                ex de,hl            ; HL = segundos
                    ld b,0
                    ld de,60
ADm                 or a
                    sbc hl,de
                    jr c,ADm2
                    inc b
                    jr ADm
ADm2                add hl,de
                    ld a,l
                    ld (TotSeg),a
                    ld a,b
                    cp 100
                    jr c,ADm3
                    ld a,99
ADm3                ld (TotMin),a
                    ld hl,(Dur)
                    ld a,h
                    or l
                    jr z,ADsemT
                    ld a,1
ADsemT              ld (TemTot),a
                    call Relogio
                    or a                ; CF = 0: deu
                    ret

; BLen acertado: dentro do ficheiro (BOff + BLen <= Tam) e dos 64K (BAddr + BLen <= 10000h)
AcertaBloco         ld hl,(Tam)
                    ld de,(BOff)
                    or a
                    sbc hl,de           ; o que ha' no ficheiro a partir de BOff
                    jr nc,AC1
                    ld hl,0
AC1                 ld de,(BLen)
                    call Menor
                    ld (BLen),hl
                    ld hl,(BAddr)       ; 10000h - BAddr
                    ld a,h
                    or l
                    ret z
                    xor a
                    sub l
                    ld l,a
                    ld a,0
                    sbc a,h
                    ld h,a
                    ld de,(BLen)
                    call Menor
                    ld (BLen),hl
                    ret
Menor               or a                ; HL = o menor de HL e DE
                    push hl
                    sbc hl,de
                    pop hl
                    ret c
                    ex de,hl
                    ret

; CF = a zona HL, BC bytes toca no que nao pode (ROM, plugin, trampolim, IM 2)
Proibido            ld a,b
                    or c
                    ret z
                    ld de,4000h         ; HL < 4000h: ROM
                    or a
                    push hl
                    sbc hl,de
                    pop hl
                    ret c
                    push hl
                    add hl,bc           ; HL = o fim (exclusivo); passou dos 64K: so' se chega a FD00h
                    jr c,PRfim64
                    ex de,hl            ; DE = fim
                    pop hl              ; HL = inicio
                    push hl
                    ld bc,8000h         ; [8000h, PFIM)
                    ld ix,PFIM
                    call Cruza
                    pop hl
                    ret c
                    push hl
                    ld bc,0A000h        ; [A000h, A3E0h)
                    ld ix,0A3E0h
                    call Cruza
                    pop hl
                    ret c
                    push hl
                    ex de,hl            ; fim > FD00h: o IM 2
                    ld bc,0FD01h
                    or a
                    sbc hl,bc
                    ccf
                    pop hl
                    ret
PRfim64             pop hl
                    scf
                    ret
; CF = [HL, DE) cruza [BC, IX): HL < IX e DE > BC (HL, DE, BC ficam)
Cruza               push hl
                    push de
                    push ix
                    pop de              ; DE = IX
                    or a
                    sbc hl,de           ; inicio - IX: CF = inicio < IX
                    pop de
                    pop hl
                    ret nc              ; inicio >= IX: nao cruza
                    push hl
                    ld h,b
                    ld l,c
                    or a
                    sbc hl,de           ; BC - fim: CF = BC < fim
                    pop hl
                    ret
; A = 1 se a zona HL, BC bytes toca no ecra (4000h-7FFFh), senao 0
NoEcra              ld a,b
                    or c
                    ret z
                    ld a,h
                    cp 80h
                    jr nc,NEnao
                    ld a,1              ; comeca abaixo de 8000h (e acima de 4000h: nao e' proibido)
                    ret
NEnao               xor a
                    ret

; ---------------------------------------------------------------- o ficheiro nas paginas 42-49
; A = byte no sitio HL do ficheiro
RdB                 push hl
                    ld a,h
                    rlca
                    rlca
                    rlca
                    and 7
                    add a,80h+PFICH
                    out (0E3h),a
                    ld a,h
                    and 1Fh
                    or 20h
                    ld h,a
                    ld a,(hl)
                    push af
                    xor a
                    out (0E3h),a
                    pop af
                    pop hl
                    ret
; DE = palavra (Motorola: o byte alto primeiro) no sitio HL
RdW                 call RdB
                    ld d,a
                    inc hl
                    call RdB
                    ld e,a
                    dec hl
                    ret
; HL = HL + a palavra com sinal que esta' em HL (os ponteiros do .AY sao relativos a eles proprios)
RelPtr              call RdW
                    add hl,de
                    ret
; copia BC bytes do sitio HL do ficheiro para DE (aos bocados, uma pagina de cada vez)
CopiaF              ld a,b
                    or c
                    ret z
                    push bc
                    ld a,h              ; a pagina
                    rlca
                    rlca
                    rlca
                    and 7
                    add a,80h+PFICH
                    out (0E3h),a
                    push hl             ; o que falta ate' ao fim desta pagina: 2000h - (HL and 1FFFh)
                    ld a,h
                    and 1Fh
                    ld h,a
                    push de
                    ex de,hl
                    ld hl,2000h
                    or a
                    sbc hl,de           ; HL = o que cabe nesta pagina
                    pop de
                    ld b,h
                    ld c,l              ; BC = o que cabe
                    pop hl              ; HL = sitio no ficheiro
                    ex (sp),hl          ; HL = o que falta copiar; (sp) = sitio
                    push hl
                    or a
                    sbc hl,bc
                    pop hl
                    jr nc,CF1           ; falta mais do que cabe: copia BC
                    ld b,h              ; senao copia o que falta
                    ld c,l
CF1                 or a                ; HL = o que falta - BC (fica para depois)
                    sbc hl,bc
                    ex (sp),hl          ; (sp) = o que fica; HL = sitio
                    push hl
                    push bc
                    ld a,h              ; a origem na janela: 2000h + (sitio and 1FFFh)
                    and 1Fh
                    or 20h
                    ld h,a
                    ldir
                    pop bc
                    pop hl
                    add hl,bc           ; o sitio seguinte
                    xor a
                    out (0E3h),a
                    pop bc              ; o que fica
                    jr CopiaF

; 4000h-7FFFh <-> paginas 50-51
SalvaEcra           ld a,80h+PSALVA
                    out (0E3h),a
                    ld hl,4000h
                    ld de,2000h
                    ld bc,2000h
                    ldir
                    ld a,80h+PSALVA+1
                    out (0E3h),a
                    ld hl,6000h
                    ld de,2000h
                    ld bc,2000h
                    ldir
                    xor a
                    out (0E3h),a
                    ret
RepoeEcra           ld a,80h+PSALVA
                    out (0E3h),a
                    ld hl,2000h
                    ld de,4000h
                    ld bc,2000h
                    ldir
                    ld a,80h+PSALVA+1
                    out (0E3h),a
                    ld hl,2000h
                    ld de,6000h
                    ld bc,2000h
                    ldir
                    xor a
                    out (0E3h),a
                    ret

; ---------------------------------------------------------------- os erros
ErroLeF             ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    ld hl,TxtLe
                    jp Erro
ErroGrandeF         ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    ld hl,TxtGrande
                    jp Erro
ErroAbre            ld hl,TxtAbre
                    jp Erro
ErroNaoAY           ld hl,TxtNaoAY
                    jp Erro
ErroMus             ; HL = o texto (do Arranca)
Erro                ld (NavBC),hl
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    jp Sai

; ---------------------------------------------------------------- o relogio (como no PT3)
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
; "mm:ss" (ou "mm:ss/mm:ss") no canto de cima a' direita; nada se a musica usa a memoria do ecra
Relogio             ld a,(SemRel)
                    or a
                    ret nz
                    ld a,(Hires)
                    or a
                    ld c,27
                    jr z,RLc
                    ld c,59
RLc                 ld a,(TemTot)
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
; a letra A (0-9, 10 = ':', 11 = '/') na coluna C da linha 0; C avanca
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
                    db 00h,06h,0Ch,18h,30h,60h,00h,00h   ; '/'

Assin               db "ZXAYEMUL"
TxtAbre             db "AY: nao abre o ficheiro",0
TxtLe               db "AY: erro a ler o ficheiro",0
TxtGrande           db "AY: mais de 64K",0
TxtNaoAY            db "AY: nao e' um ZXAYEMUL",0
TxtSemInt           db "AY: sem rotina de interrupcao",0
TxtPilha            db "AY: a pilha dele nao da'",0
TxtMem              db "AY: usa a memoria do navegador",0

FH                  db 0
Opc                 db 2
Minutos             db 0
Hires               db 0
Ivelho              db 0
Ret                 db 0
NavBC               dw 0
SPnav               dw 0
SPmeu               dw 0
SPmus               dw 0
Tam                 dw 0
NMus                db 1
Mus                 db 0
TabMus              dw 0
SData               dw 0
PPts                dw 0
PEnd                dw 0
Init                dw 0
Intr2               dw 0
Dur                 dw 0
Quadros             dw 0
RegVal              dw 0
BAddr               dw 0
BLen                dw 0
BOff                dw 0
Copia               db 0
SemRel              db 0
TemTot              db 0
TotMin              db 0
TotSeg              db 0
Frac                db 0
Seg                 db 0
Min                 db 0
RegsMus             ds 24               ; AF BC DE HL IX IY AF' BC' DE' HL' da musica, por esta ordem
RegsMusFim
                    ds 128
Pilha
PFIM                equ $
                    assert PFIM <= STAGE
