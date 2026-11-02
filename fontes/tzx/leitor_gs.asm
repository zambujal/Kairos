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
                    jr Ciclo
Normal              and 0C0h            ; uma pausa (10xxxxxx) com a pausa pedida: fica aqui
                    cp 80h
                    jr nz,NEnv
                    ld a,(Ped)
                    or a
                    call nz,Pausa
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
                    ld a,1
                    ld (RedB),a
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
                    ld a,1
                    ld (RedE),a
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
                    ld (RedAll),a
                    call Estado
ECst                ld (ClrA),hl
                    jr ESai
EDes                ld a,(Cam)
                    or a
                    jr z,ESai
                    ld a,(RedAll)
                    or a
                    jr z,EBl
                    xor a
                    ld (RedAll),a
                    ld (RedB),a
                    ld (RedE),a
                    call Painel
                    jr ESai
EBl                 ld a,(RedB)
                    or a
                    jr z,EEs
                    xor a
                    ld (RedB),a
                    call LinBloco
                    jr ESai
EEs                 ld a,(RedE)
                    or a
                    jr z,ESai
                    xor a
                    ld (RedE),a
                    call LinEst
ESai                ld a,(Pag)          ; a pagina da lista outra vez
                    out (0),a
                    pop ix
                    pop hl
                    pop de
                    pop bc
                    pop af
                    ret
Painel              ld b,0
                    ld ix,TCas
                    call LinB
                    call LinBloco
                    call LinEst
                    ld b,3
                    ld ix,TF3a
                    call LinB
                    ld b,4
                    ld ix,TF3b
                    call LinB
                    ld b,5
                    ld ix,TF4
                    jr LinB
LinBloco            ld ix,TBl+6         ; "BLOCO nn DE nn"
                    ld a,(Bloco)
                    call Dois
                    ld ix,TBl+12
                    ld a,(Tot)
                    call Dois
                    ld b,1
                    ld ix,TBl
                    jr LinB
LinEst              ld ix,TToca
                    ld a,(Ped)
                    or a
                    jr z,LE1
                    ld ix,TPed
LE1                 ld a,(Par)
                    or a
                    jr z,LE2
                    ld ix,TPausa
LE2                 ld a,(Gelo)
                    or a
                    jr z,LE3
                    ld ix,TParada
LE3                 ld b,2
                    ld hl,TabA          ; a amarelo
                    jr LinC
; uma linha (B = 0-5) com o texto IX, a branco
LinB                ld hl,TabB
LinC                ld (TabC),hl
                    ld hl,15360         ; (48 + linha x 16) x 320
                    ld de,5120
                    inc b
LCl                 dec b
                    jr z,LCs
                    add hl,de
                    jr LCl
LCs                 ld (COff),hl
LCc                 ld a,(ix+0)
                    or a
                    ret z
                    call DChar
                    inc ix
                    jr LCc
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
TCas                db "CASSETE (TZX)   ",0
TBl                 db "BLOCO 00 DE 00  ",0
TToca               db "A TOCAR         ",0
TPed                db "PAUSA PEDIDA    ",0
TPausa              db "EM PAUSA (F3)   ",0
TParada             db "PARADA (F4)     ",0
TF3a                db "F3 PAUSA NO FIM ",0
TF3b                db "   DO BLOCO     ",0
TF4                 db "F4 PARA JA      ",0
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
RedAll              equ 5F15h
RedB                equ 5F16h
RedE                equ 5F17h
Tot                 equ 5F18h
TabC                equ 5F19h
COff                equ 5F1Bh
Lin                 equ 5F1Dh
