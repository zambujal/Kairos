; NAVL.EXT (2026-11-01): o espelho do navegador na camada L do core (72+), com a letra Spleen 8x16 (a mesma
; do menu do ESP). Vai para uma pagina do DivMMC (o NAVL.BIN carrega-a e chama-a em 2000h-3FFFh, com DI):
;   3000h Liga (HL = a letra 8x8 do NAV): cores, o quadrado do Spectrum com o papel, a camada ligada, e a
;         tabela para reconhecer as letras do ecra hi-res;
;   3003h Espelho: ve 2 linhas de letras do hi-res (soma de Fletcher) e copia no maximo 1 que mudou.
; Cada celula do hi-res (8x8) e' reconhecida pela tabela (soma rodada dos 8 bytes, conferida com a letra do
; NAV, normal ou invertida) e desenhada com a Spleen 8x16; a que nao se reconhece (o emblema, a gota) vai
; como esta', com cada linha de pontos duas vezes. 64 x 24 celulas = 512x384, ao meio do quadrado.
; Monta-se com  sjasmplus --raw=NAVL.EXT navl_ext.asm  (fica 2000h-3FFFh).
                    org 2000h
SPLEEN              incbin "spleen8x16_linhas.bin"  ; 2000h: a linha y da letra c em 2000h + y x 256 + c
                    assert $ = 3000h
                    jp Liga
                    jp Espelho

CPSEL               equ 0EC3Bh
CPDAT               equ 0ED3Bh
CQUAD               equ 600000h + 72 * 320 + 64     ; o quadrado: ponto 256, linha 72, 192 bytes x 576
CBASE               equ 600000h + 168 * 320 + 96    ; as letras: ponto 384, linha 168
HIRESFF             equ 36h                         ; como no nav.asm
CTINTA              equ (HIRESFF >> 3) & 7
CPAPEL              equ 7 - CTINTA
TAB                 equ 3800h           ; 256: a soma -> o codigo da letra (0 = nenhuma)
CEL                 equ 3900h           ; 64 x 2: (codigo, mascara) ou (0, coluna)

; A = registo, E = valor (nao mexe no BC)
Reg                 push bc
                    ld bc,CPSEL
                    out (c),a
                    ld bc,CPDAT
                    out (c),e
                    pop bc
                    ret
Espera              push bc             ; (mexe no HL e no A)
                    ld bc,CPSEL
                    ld hl,0
Es1                 in a,(c)
                    rra
                    jr c,Es2
                    dec hl
                    ld a,h
                    or l
                    jr nz,Es1
Es2                 pop bc
                    ret
; HL = os bits 15-0, A = os bits 22-16 do ponteiro; depois o rectangulo de DE bytes com passo 320
Ptr                 push af
                    push de
                    push hl
                    call Espera
                    pop hl
                    ld e,l
                    ld a,30h
                    call Reg
                    ld e,h
                    ld a,31h
                    call Reg
                    pop de
                    pop af
                    push de
                    ld e,a
                    ld a,32h
                    call Reg
                    pop de
                    ld a,26h
                    call Reg
                    ld e,d
                    ld a,27h
                    call Reg
                    ld e,320 & 255
                    ld a,28h
                    call Reg
                    ld e,320 >> 8
                    ld a,29h
                    jp Reg

Liga                ld (FonteNav),hl
                    ld a,40h            ; desligada enquanto se prepara
                    ld e,0
                    call Reg
                    ld hl,Cores         ; 41-49 (o registo avanca sozinho)
                    ld a,41h
                    ld e,(hl)
                    call Reg
                    ld bc,CPDAT
                    ld d,8
LG1                 inc hl
                    ld a,(hl)
                    out (c),a
                    dec d
                    jr nz,LG1
                    ld a,4Eh
                    ld e,0
                    call Reg
                    ld hl,0             ; a camada toda transparente (cor 0): o que la' ficou de antes
                    ld a,60h            ; (o ESP, os testes) via-se a' volta do quadrado
                    ld de,0             ; (sem rectangulo)
                    call Ptr
                    ld a,3Ch
                    ld e,0
                    call Reg
                    ld e,(1280 * 720 / 16) & 255
                    ld a,3Dh
                    call Reg
                    ld e,(1280 * 720 / 16) >> 8
                    ld a,3Eh
                    call Reg
                    ld hl,CQUAD & 0FFFFh   ; o quadrado todo com o papel (cor 1), pelo core
                    ld a,CQUAD >> 16
                    ld de,192
                    call Ptr
                    ld a,3Ch
                    ld e,55h
                    call Reg
                    ld e,(576 * 192 / 4) & 255
                    ld a,3Dh
                    call Reg
                    ld e,(576 * 192 / 4) >> 8
                    ld a,3Eh
                    call Reg
                    ld hl,Val           ; todas as linhas por copiar
                    ld b,24
LG2                 ld (hl),0
                    inc hl
                    djnz LG2
                    ; a tabela: a soma de cada letra do NAV (32-127) -> o codigo (a 1.a que cair la' fica)
                    ld hl,TAB
LG3                 ld (hl),0
                    inc l
                    jr nz,LG3
                    ld hl,(FonteNav)
                    ld c,32
LG4                 push hl
                    call SomaF          ; A = a soma dos 8 bytes em HL (seguidos)
                    ld l,a
                    ld h,TAB >> 8
LG6                 ld a,(hl)           ; ocupado: a seguinte livre (e o Procura anda igual)
                    or a
                    jr z,LG5
                    inc l
                    jr LG6
LG5                 ld (hl),c
                    pop hl
                    ld de,8
                    add hl,de
                    inc c
                    ld a,c
                    cp 128
                    jr c,LG4
                    ld a,40h
                    ld e,1
                    jp Reg
; A = soma rodada dos 8 bytes seguidos em HL
SomaF               xor a
                    ld b,8
SF1                 rlca
                    xor (hl)
                    inc hl
                    djnz SF1
                    ret

; HL = o 1.o byte (banco 4000h) da linha de letras A
Linha               ld l,a
                    and 18h
                    or 40h
                    ld h,a
                    ld a,l
                    and 7
                    rrca
                    rrca
                    rrca
                    ld l,a
                    ret

Espelho             ld b,2              ; 2 linhas vistas
ESv                 push bc
                    ld a,(Prox)
                    call Linha
                    ld de,0             ; Fletcher: E = soma, D = soma das somas
                    ld c,8
ESy                 push hl
                    ld b,32
ESb1                ld a,(hl)
                    add a,e
                    ld e,a
                    add a,d
                    ld d,a
                    inc l
                    djnz ESb1
                    pop hl
                    push hl
                    set 5,h
                    ld b,32
ESb2                ld a,(hl)
                    add a,e
                    ld e,a
                    add a,d
                    ld d,a
                    inc l
                    djnz ESb2
                    pop hl
                    inc h
                    dec c
                    jr nz,ESy
                    ld a,(Prox)         ; igual e ja' copiada: a seguinte
                    ld c,a
                    ld b,0
                    ld hl,Val
                    add hl,bc
                    ld a,(hl)
                    or a
                    ld (hl),1
                    ld hl,Soma
                    add hl,bc
                    add hl,bc
                    jr z,ESnova
                    ld a,(hl)
                    cp e
                    jr nz,ESnova
                    inc hl
                    ld a,(hl)
                    cp d
                    jr z,ESigual
                    dec hl
ESnova              ld (hl),e
                    inc hl
                    ld (hl),d
                    ld a,(Prox)
                    call Copia
                    call ESprox
                    pop bc
                    ret
ESigual             call ESprox
                    pop bc
                    djnz ESv
                    ret
ESprox              ld a,(Prox)
                    inc a
                    cp 24
                    jr c,ESp1
                    xor a
ESp1                ld (Prox),a
                    ret

; a linha de letras A para a camada L
Copia               ld (LinA),a
                    call Classifica
                    ld a,(LinA)
                    ld l,a              ; o ponteiro: CBASE + A x 16 x 320 = CBASE + (A x 20) << 8
                    ld h,0
                    add hl,hl
                    add hl,hl
                    ld d,h
                    ld e,l
                    add hl,hl
                    add hl,hl
                    add hl,de           ; HL = A x 20
                    ld a,(CBASE >> 8) & 0FFh
                    add a,l
                    ld d,a
                    ld a,CBASE >> 16
                    adc a,h
                    ld e,CBASE & 0FFh
                    ex de,hl
                    ld de,128
                    call Ptr
                    ld a,36h            ; tinta 3, papel 1
                    ld e,0Dh
                    call Reg
                    ld a,35h            ; daqui em diante: 1 OUT = 8 pontos
                    ld bc,CPSEL
                    out (c),a
                    ld bc,CPDAT
                    xor a               ; y = 0..15
CPy                 ld (Y),a
                    add a,SPLEEN >> 8
                    ld h,a              ; H = a linha y da Spleen
                    ld de,CEL
                    ld a,64
                    ld (K),a
CPk                 ld a,(de)           ; o codigo (0 = a celula como esta')
                    inc de
                    or a
                    jr z,CPraw
                    ld l,a
                    ld a,(de)           ; a mascara (FFh = invertida)
                    xor (hl)
CPout               out (c),a
                    inc de
                    ld a,(K)
                    dec a
                    ld (K),a
                    jr nz,CPk
                    ld a,(Y)
                    inc a
                    cp 16
                    jr c,CPy
                    ret
CPraw               push hl             ; a celula do hi-res, linha y / 2
                    ld a,(de)           ; a coluna
                    push af
                    ld a,(LinA)
                    call Linha
                    pop af
                    srl a
                    jr nc,CPr1
                    set 5,h
CPr1                add a,l
                    ld l,a
                    ld a,(Y)
                    srl a
                    add a,h
                    ld h,a
                    ld a,(hl)
                    pop hl
                    jr CPout

; as 64 celulas da linha (LinA) -> CEL
Classifica          ld a,(LinA)
                    call Linha
                    ld (Base),hl
                    ld ix,CEL
                    xor a
CLk                 ld (K),a
                    ld hl,(Base)        ; a celula K: (Base) + K / 2, e 2000h a mais nas impares
                    srl a
                    jr nc,CL1
                    set 5,h
CL1                 add a,l
                    ld l,a
                    ld de,Bytes         ; os 8 bytes da celula
                    ld b,8
CL2                 ld a,(hl)
                    ld (de),a
                    inc de
                    inc h
                    djnz CL2
                    ld hl,Bytes         ; normal?
                    call SomaF
                    ld c,0
                    call Procura
                    jr z,CLok
                    ld hl,Bytes         ; invertida?
                    ld b,8
CL3                 ld a,(hl)
                    cpl
                    ld (hl),a
                    inc hl
                    djnz CL3
                    ld hl,Bytes
                    call SomaF
                    ld c,0FFh
                    call Procura
                    jr z,CLok
                    ld (ix+0),0         ; nenhuma: como esta'
                    ld a,(K)
                    ld (ix+1),a
                    jr CLprox
CLok                ld (ix+0),a
                    ld (ix+1),c
CLprox              inc ix
                    inc ix
                    ld a,(K)
                    inc a
                    cp 64
                    jr c,CLk
                    ret
; A = a soma de Bytes: Z e A = o codigo se uma letra da tabela (a partir da soma, ate' uma livre) e' igual
Procura             ld l,a
                    ld h,TAB >> 8
PRc                 ld a,(hl)
                    or a
                    jr z,PRnao
                    push hl
                    push af
                    sub 32              ; a letra do NAV: (FonteNav) + (codigo - 32) x 8
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,(FonteNav)
                    add hl,de
                    ld de,Bytes
                    ld b,8
PR1                 ld a,(de)
                    cp (hl)
                    jr nz,PR2
                    inc hl
                    inc de
                    djnz PR1
                    pop af              ; igual (Z)
                    pop hl
                    cp a
                    ret
PR2                 pop af
                    pop hl
                    inc l               ; a seguinte com a mesma soma (ou outra)
                    jr PRc
PRnao               or 1                ; NZ
                    ret

NIVEL               macro c
                    db ((c >> 1) & 1) * 0D7h, ((c >> 2) & 1) * 0D7h, (c & 1) * 0D7h
                    endm
Cores               NIVEL CPAPEL        ; cor 1 = o papel, 2 = o papel, 3 = a tinta (R, G, B)
                    NIVEL CPAPEL
                    NIVEL CTINTA
FonteNav            dw 0
Prox                db 0
LinA                db 0
Y                   db 0
K                   db 0
Base                dw 0
Bytes               ds 8
Val                 ds 24
Soma                ds 48
                    assert $ <= TAB
