; leitor_gs.asm - o leitor de cassete que corre no Z80 do General Sound (core 81+), posto pelo plugin TZX.
; O plugin escreve este programa no principio da pagina 2 da memoria do GS e, logo a seguir, a lista da fita
; (o formato do plugin_tzx.asm). Com o modo "fita" do core, 0000h-3FFFh e' o principio da pagina 2: o programa
; corre daqui; a lista le-se pela janela 8000h-FFFFh (porta 0 = a pagina).
; Portas do leitor (gs.vhd): C escrita byte baixo / D escrita byte alto (a palavra vai para a cassete),
;   C leitura lugares livres, D leitura bit 0 F3, bit 1 F4, bit 2 a cassete a tocar,
;   E escrita o estado (bit 0 pausa pedida, 1 parada, 2 parada ja'; bit 7 acabou), F escrita o bloco.
; Teclas: F3 pede a pausa (fica na pausa seguinte da fita, depois dos dados do bloco); outro F3 continua.
;         F4 para ja' (o core para a cassete no sitio); outro F4, ou F3, continua.
; (82) Os avisos: o leitor escreve na camada L do ecra (as paginas 48-55, 1280x720 a 2 bits por ponto, 320 bytes
;   por linha; so' em 720p) um painel a' esquerda: CASSETE, o bloco, o estado e as teclas. Liga a camada (porta
;   E bit 3) so' depois de a limpar, e larga-a quando o ESP a usa (porta D bit 3); quando o ESP a larga, limpa-a
;   outra vez e volta a desenhar. Tudo isto so' enquanto a fila da cassete esta' cheia (nunca a deixa vazia).
; Monta-se com  sjasmplus --raw=LEITOR.BIN leitor_gs.asm  (o plugin junta-o com incbin)

                    org 0
                    di
                    ld sp,5FF0h         ; a pilha na pagina 1 (4000h-5FFFh: as leituras em 6000h-7FFFh vao para os canais)
                    ld hl,Ped           ; as variaveis a zero
                    ld de,Ped+1
                    ld bc,63
                    ld (hl),0
                    ldir
                    xor a
                    out (0Fh),a
                    call Estado
                    in a,(0Dh)
                    ld (TAnt),a
                    ld a,2
                    ld (Pag),a
                    out (0),a
                    ld hl,8000h+Lista
                    call Conta          ; (82) quantos blocos (para o painel)
                    ld a,48             ; (82) limpar a camada aos bocados, depois desenhar
                    ld (ClrP),a
                    ld de,8000h
                    ld (ClrA),de
LDesp               in a,(0Dh)          ; (83c) espera que o Z80 entre no LOAD da ROM (o core diz: D bit 4)
                    and 10h
                    jr nz,Ciclo
                    call Teclas
                    call Ecra           ; entretanto limpa a camada e desenha o painel
                    jr LDesp
; ---------------------------------------------------------------- as palavras
Ciclo               call GetW           ; DE = a palavra
                    ld a,d
                    cp 0F0h
                    jr c,Normal
                    ld a,e
                    cp 0FFh
                    jr nz,CNfim
                    ld a,d
                    inc a
                    jp z,Fim            ; FFFFh
CNfim               ld a,d
                    cp 0F0h
                    jr nz,Ciclo         ; outras Fxxx: ignoradas
                    ld a,e
                    cp 1
                    jr z,Rep
                    cp 2
                    jr z,Dados
                    cp 3
                    jr nz,Ciclo
                    call Resto          ; F003h: o TZX diz "parar a fita" (jogos com niveis): para, se ainda ha' mais
                    jp z,Fim
                    ld a,1
                    ld (Ped),a
                    call Pausa
                    jr Ciclo
Normal              and 0C0h            ; uma pausa (10xxxxxx) com a pausa pedida: fica aqui
                    cp 80h
                    jr nz,NEnv
                    ld a,(Ped)
                    or a
                    jr z,NEnv
                    ld a,d              ; so' nas pausas compridas (um bocado de 256 ms: 8000h + 14000), nao nas
                    cp 0B6h             ; curtas dentro do carregador do jogo
                    jr c,NEnv
                    jr nz,NLonga
                    ld a,e
                    cp 0B0h
                    jr c,NEnv
NLonga              call Resto          ; ja' nao ha' nada para tocar: a fita acaba aqui
                    jp z,Fim
                    call Pausa
NEnv                call Envia
                    jr Ciclo
; F001h L N: N impulsos de L
Rep                 call GetW
                    ld (Lrep),de
                    call GetW
RPl                 ld a,d
                    or e
                    jr z,Ciclo
                    push de
                    ld de,(Lrep)
                    call Envia
                    pop de
                    dec de
                    jr RPl
; F002h B0 B1 N U e os bytes (2 por palavra)
Dados               call GetW
                    ld (B0),de
                    call GetW
                    ld (B1),de
                    call GetW
                    ld (NBy),de
                    call GetW
                    ld a,e
                    ld (Ult),a
                    ld a,(Bloco)
                    inc a
                    ld (Bloco),a
                    out (0Fh),a
                    ld a,(Pend)         ; (82) a linha do bloco
                    or 2
                    ld (Pend),a
                    ld a,(NBy)          ; impar: o ultimo byte da lista fica por ler (o enchimento)
                    and 1
                    ld (Impar),a
DByte               ld bc,(NBy)
                    ld a,b
                    or c
                    jr z,DFim
                    dec bc
                    ld (NBy),bc
                    call GetB
                    ld c,a              ; C = o byte
                    ld b,8
                    ld a,(NBy)
                    ld e,a
                    ld a,(NBy+1)
                    or e
                    jr nz,DBits
                    ld a,(Ult)          ; o ultimo: so' U bits
                    ld b,a
DBits               ld a,b              ; B bits, do 7 para baixo; cada bit sao dois impulsos
                    or a
                    jr z,DByte
                    ld de,(B0)
                    bit 7,c
                    jr z,DB0
                    ld de,(B1)
DB0                 call Envia
                    call Envia
                    sla c
                    dec b
                    jr DBits
DFim                ld a,(Impar)
                    or a
                    call nz,GetB
                    jp Ciclo
; o fim: espera que a cassete acabe e devolve o GS
Fim                 in a,(0Dh)
                    and 4
                    jr nz,Fim
                    xor a               ; a camada desligada
                    ld (Cam),a
                    call Estado
                    ld a,80h
                    out (0Eh),a
                    jr $
; ---------------------------------------------------------------- a cassete
; manda a palavra DE (espera lugar na fila; trata das teclas)
Envia               in a,(0Ch)          ; (as teclas so' enquanto espera: a fila esta' quase sempre cheia, e
                    cp 5                ; assim o leitor aguenta a cassete a 27 MHz)
                    jr nc,EnvOk
                    call Teclas
                    call Ecra
                    jr Envia
EnvOk               ld a,e
                    out (0Ch),a
                    ld a,d
                    out (0Dh),a
                    ret
; espera ate' a pausa acabar (F3 outra vez, ou F4)
Pausa               ld a,1
                    ld (Par),a
                    call Estado
PAl                 call Teclas
                    call Ecra
                    ld a,(Ped)
                    or a
                    jr nz,PAl
                    xor a
                    ld (Par),a
                    jp Estado
; Z = da'qui ate' ao fim da lista so' ha' pausas (nenhum impulso nem bloco); nao muda nada
Resto               push de
                    push hl
                    ld a,(Pag)
                    push af
RSl                 call GetW
                    ld a,d
                    and e
                    inc a
                    jr z,RSfim          ; FFFFh: nada (Z)
                    bit 7,d
                    jr z,RSha           ; um impulso
                    ld a,d
                    cp 0F0h
                    jr nz,RSl           ; pausas e niveis
                    ld a,e
                    cp 1
                    jr z,RSha
                    cp 2
                    jr nz,RSl
RSha                or 1                ; NZ
RSfim               pop bc              ; (B = a pagina; os flags ficam)
                    ld a,b
                    ld (Pag),a
                    out (0),a
                    pop hl
                    pop de
                    ret
; as teclas novas (F3 bit 0, F4 bit 1)
Teclas              push bc
                    in a,(0Dh)
                    ld b,a
                    ld a,(TAnt)
                    cpl
                    and b
                    ld c,a              ; C = as que desceram agora
                    ld a,b
                    ld (TAnt),a
                    bit 1,c             ; F4: para ja' / continua
                    jr z,TF3
                    ld a,(Par)          ; em pausa (F3, parada entre blocos): o F4 tira a fita (acaba aqui)
                    or a
                    jp nz,Fim
                    ld a,(Gelo)
                    xor 1
                    ld (Gelo),a
                    xor a
                    ld (Ped),a
                    call Estado
                    jr TFim
TF3                 bit 0,c             ; F3: pausa no fim dos dados / continua
                    jr z,TFim
                    ld a,(Gelo)
                    or a
                    jr z,TF3p
                    xor a
                    ld (Gelo),a
                    call Estado
                    jr TFim
TF3p                ld a,(Ped)
                    xor 1
                    ld (Ped),a
                    call Estado
TFim                pop bc
                    ret
Estado              push bc
                    ld a,(Pend)         ; (82) a linha do estado
                    or 4
                    ld (Pend),a
                    ld a,(Cam)          ; bit 3 a camada
                    add a,a
                    ld b,a
                    ld a,(Gelo)
                    or b
                    add a,a
                    ld b,a
                    ld a,(Par)
                    or b
                    add a,a
                    ld b,a
                    ld a,(Ped)
                    or b
                    out (0Eh),a
                    pop bc
                    ret
; ---------------------------------------------------------------- a lista
GetB                ld a,(hl)
                    inc hl
                    push af
                    ld a,h
                    or l
                    jr nz,GBok
                    ld hl,8000h         ; a pagina seguinte
                    ld a,(Pag)
                    inc a
                    ld (Pag),a
                    out (0),a
GBok                pop af
                    ret
GetW                call GetB
                    ld e,a
                    call GetB
                    ld d,a
                    ret

; ---------------------------------------------------------------- (82) o painel na camada L
; Ecra: chamado com a fila cheia; faz um bocado de cada vez (nao mexe em nenhum registo)
Ecra                push af
                    push bc
                    push de
                    push hl
                    push ix
                    in a,(0Dh)
                    and 8
                    jr z,ELivre
                    ld a,(Cam)          ; o ESP tem a camada: larga-a
                    or a
                    jp z,ESai
                    xor a
                    ld (Cam),a
                    call Estado
                    ld a,1
                    ld (EspUsou),a
                    jp ESai
ELivre              ld a,(EspUsou)      ; o ESP largou-a: limpar outra vez
                    or a
                    jr z,ESemEsp
                    xor a
                    ld (EspUsou),a
                    ld a,48
                    ld (ClrP),a
                    ld hl,8000h
                    ld (ClrA),hl
ESemEsp             ld a,(ClrP)
                    or a
                    jr z,EDes
                    out (0),a           ; limpar 128 bytes
                    ld hl,(ClrA)
                    ld b,128
                    xor a
ECl                 ld (hl),a
                    inc hl
                    djnz ECl
                    ld a,h
                    or l
                    jr nz,ECst
                    ld hl,8000h
                    ld a,(ClrP)
                    inc a
                    ld (ClrP),a
                    cp 56
                    jr nz,ECst
                    xor a               ; limpa: liga a camada e desenha tudo
                    ld (ClrP),a
                    ld a,1
                    ld (Cam),a
                    ld a,3Fh            ; todas as linhas
                    ld (Pend),a
                    ld a,0FFh
                    ld (DLin),a
                    call Estado
ECst                ld (ClrA),hl
                    jp ESai
EDes                ld a,(Cam)          ; uma letra de cada vez (~0,3 ms): a fila nunca fica vazia, mesmo a 27 MHz
                    or a
                    jp z,ESai
                    ld a,(DLin)
                    cp 0FFh
                    jr nz,EDc
                    ld a,(Pend)         ; a linha seguinte por desenhar (bits 0-5)
                    or a
                    jp z,ESai
                    ld b,0
EDp                 rrca
                    jr c,EDq
                    inc b
                    jr EDp
EDq                 ld a,b
                    ld (DLin),a
                    ld c,1              ; tira o bit da linha
                    inc b
EDm                 dec b
                    jr z,EDm2
                    sla c
                    jr EDm
EDm2                ld a,c
                    cpl
                    ld hl,Pend
                    and (hl)
                    ld (hl),a
                    xor a
                    ld (DPos),a
                    ld a,(DLin)
                    cp 1
                    jr nz,EDc
                    ld ix,TBl+6         ; o bloco: "BLOCO nn/nn"
                    ld a,(Bloco)
                    call Dois
                    ld ix,TBl+9
                    ld a,(Tot)
                    call Dois
EDc                 call TxtLin         ; IX = o texto da linha, (TabC) = a cor
                    ld a,(DPos)
                    ld e,a
                    ld d,0
                    add ix,de
                    ld a,(ix+0)
                    or a
                    jr nz,EDl
                    ld a,0FFh           ; a linha acabou
                    ld (DLin),a
                    jp ESai
EDl                 push af
                    ld a,(DLin)         ; COff = (48 + linha x 16) x 320 + DPos x 4
                    ld b,a
                    ld hl,15360+16      ; (64 pontos da esquerda: a TV corta a margem)
                    ld de,5120
                    inc b
EDo                 dec b
                    jr z,EDo2
                    add hl,de
                    jr EDo
EDo2                ld a,(DPos)
                    add a,a
                    add a,a
                    ld e,a
                    ld d,0
                    add hl,de
                    ld (COff),hl
                    pop af
                    call DChar
                    ld hl,DPos
                    inc (hl)
ESai                ld a,(Pag)          ; a pagina da lista outra vez
                    out (0),a
                    pop ix
                    pop hl
                    pop de
                    pop bc
                    pop af
                    ret
; o texto da linha (DLin) em IX e a cor em (TabC)
TxtLin              ld hl,TabB
                    ld (TabC),hl
                    ld a,(DLin)
                    ld ix,TCas
                    or a
                    ret z
                    ld ix,TBl
                    dec a
                    ret z
                    dec a
                    jr z,TLest
                    ld ix,TF3a
                    dec a
                    ret z
                    ld ix,TF3b
                    dec a
                    ret z
                    ld ix,TF4
                    ret
TLest               ld hl,TabA          ; o estado, a amarelo
                    ld (TabC),hl
                    ld ix,TToca
                    ld a,(Ped)
                    or a
                    jr z,TL1
                    ld ix,TPed
TL1                 ld a,(Par)
                    or a
                    jr z,TL2
                    ld ix,TPausa
TL2                 ld a,(Gelo)
                    or a
                    ret z
                    ld ix,TParada
                    ret
; A (0-99) em duas letras em (IX)
Dois                ld b,'0'-1
DSl                 inc b
                    sub 10
                    jr nc,DSl
                    add a,'0'+10
                    ld (ix+0),b
                    ld (ix+1),a
                    ret
; a letra A em (COff), 16x16 (a 8x8 a dobrar), com a tabela (TabC); COff avanca 4 bytes
DChar               sub 32
                    ld l,a
                    ld h,0
                    add hl,hl
                    add hl,hl
                    add hl,hl
                    ld de,Fonte
                    add hl,de
                    ld de,(COff)
                    ld b,8
DCr                 push bc
                    ld a,(hl)
                    inc hl
                    push hl
                    ld c,a              ; 8 pontos -> 4 bytes (cada ponto 2 vezes, 2 bits cada)
                    ld hl,Lin
                    ld b,4
DCe                 ld a,c
                    rlca
                    rlca
                    ld c,a
                    and 3
                    push hl
                    ld hl,(TabC)
                    add a,l
                    ld l,a
                    jr nc,DCn
                    inc h
DCn                 ld a,(hl)
                    pop hl
                    ld (hl),a
                    inc hl
                    djnz DCe
                    call WLin           ; a linha e a de baixo
                    ld hl,320
                    add hl,de
                    ex de,hl
                    call WLin
                    ld hl,320
                    add hl,de
                    ex de,hl
                    pop hl
                    pop bc
                    djnz DCr
                    ld hl,(COff)
                    inc hl
                    inc hl
                    inc hl
                    inc hl
                    ld (COff),hl
                    ret
; os 4 bytes de Lin na camada, em DE (0-FFFFh: paginas 48 e 49)
WLin                push de
                    ld a,d
                    rlca
                    and 1
                    add a,48
                    out (0),a
                    ld a,d
                    or 80h
                    ld d,a
                    ld hl,Lin
                    ldi
                    ldi
                    ldi
                    ldi
                    pop de
                    ret
; quantos blocos de dados tem a lista (ate' 99); nao muda o HL nem a pagina da lista
Conta               push hl
                    ld a,(Pag)
                    push af
                    ld c,0
CTl                 call GetW
                    ld a,d
                    and e
                    inc a
                    jr z,CTfim          ; FFFFh
                    ld a,d
                    cp 0F0h
                    jr nz,CTl
                    ld a,e
                    cp 1
                    jr z,CT1
                    cp 2
                    jr z,CT2
                    jr CTl
CTfim               ld a,c
                    ld (Tot),a
                    pop af
                    ld (Pag),a
                    out (0),a
                    pop hl
                    ret
CT1                 call GetW
                    call GetW
                    jr CTl
CT2                 ld a,c
                    cp 99
                    jr nc,CT2a
                    inc c
CT2a                call GetW
                    call GetW
                    call GetW           ; N
                    push de
                    call GetW           ; U
                    pop de
                    inc de              ; (N + 1) / 2 palavras
                    srl d
                    rr e
CT2b                ld a,d
                    or e
                    jr z,CTl
                    push de
                    call GetW
                    pop de
                    dec de
                    jr CT2b

; 2 pontos (b1 b0 da letra) -> 1 byte: 1 a branco (01), 2 a amarelo (10), 3 o fundo (11)
TabB                db 0FFh,0F5h,05Fh,055h
TabA                db 0FFh,0FAh,0AFh,0AAh
TCas                db "CASSETE TZX ",0
TBl                 db "BLOCO 00/00 ",0
TToca               db "A TOCAR     ",0
TPed                db "PAUSA PEDIDA",0
TPausa              db "PAUSA F4 SAI",0
TParada             db "PARADA      ",0
TF3a                db "F3 PAUSA NO ",0
TF3b                db "FIM DO BLOCO",0
TF4                 db "F4 PARA JA  ",0
Fonte               incbin "../nav/font8ibm.bin"   ; 8x8, 32-127 (font8x8 de Daniel Hepper, dominio publico)

Lista                                   ; a lista comeca aqui (o plugin escreve-a logo a seguir)

; as variaveis na pagina 1 (abaixo de 6000h)
Ped                 equ 5F00h
Par                 equ 5F01h
Gelo                equ 5F02h
TAnt                equ 5F03h
Pag                 equ 5F04h
Bloco               equ 5F05h
Impar               equ 5F06h
Ult                 equ 5F07h
Lrep                equ 5F08h
B0                  equ 5F0Ah
B1                  equ 5F0Ch
NBy                 equ 5F0Eh
Cam                 equ 5F10h
EspUsou             equ 5F11h
ClrP                equ 5F12h
ClrA                equ 5F13h
Pend                equ 5F15h
DLin                equ 5F16h
DPos                equ 5F17h
Tot                 equ 5F18h
TabC                equ 5F19h
COff                equ 5F1Bh
Lin                 equ 5F1Dh
