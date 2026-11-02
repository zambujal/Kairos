; TZX: plugin do navegador (formato dos plugins do Bob Fossil) que carrega um .TZX sem o ESP (core 78+).
; So' le' o cartao (nunca escreve nada nele).
;   1. le' o .TZX e converte-o numa lista de impulsos, escrita na SDRAM pelo core (ZXUNO A7h, um byte de
;      cada vez; formato em core/src/fita_sd.vhd):
;        0000h-7FFFh impulso de n T (e muda o EAR), 8000h+n pausa de n x 64 T, C000h / E000h EAR a 0 / a 1,
;        F001h L N  N impulsos de L T,  F002h B0 B1 N U  N bytes (U bits no ultimo), 2 por palavra,  FFFFh fim
;   2. liga a fita (A6h = 1): o core enche a cassete enquanto o jogo carrega (o EAR, sem as traps do esxDOS)
;   3. faz o LOAD "" como o stub68 (fontes/plug2068): no ZX 128K (o menu da Sinclair) o reset e o ENTER pelo
;      core (A5h); nos outros escreve LOAD "" na linha de edicao da copia da RAM do NMI e deixa um ENTER
;      pendente. Se a linha de edicao nao estiver vazia (um jogo a correr), nao liga a fita e diz porque.
; Blocos: 10 11 12 13 14 20 21 22 24 25 (ate' 8 KB dentro do ciclo) 2B, e os de texto / informacao
; (2A 30 31 32 33 34 35 5A 23 26 27 28) saltam-se. 15 18 19 e outros: erro (nao converte).
; A pausa 0 (bloco 20, "parar a fita") nao para: a fita continua.
; (Kairos, 2026-11-02)
; Monta-se com  sjasmplus -I../nav --raw=TZX plugin_tzx.asm

                    include "esxdos.inc"

PLUGIN_OK           equ 1
PLUGIN_RESTORE_BUFFERS equ 4
PLUGIN_MSG          equ 16
PLUGIN_ERROR        equ 128

LBUF                equ 0C000h          ; 8K: os blocos do ciclo (24h-25h), para os repetir
LBUFFIM             equ 0E000h
BUF                 equ 0E000h          ; 4K: a leitura do ficheiro
BUFTAM              equ 1000h

ELINE               equ 5C59h
KCUR                equ 5C5Bh
WORKSP              equ 5C61h
STKBOT              equ 5C63h
STKEND              equ 5C65h
LASTK               equ 5C08h
FLAGS               equ 5C3Bh

                    org 8000h
                    jr Inicio
                    db "BP",0,0
                    db 0                ; flags
                    db 0                ; flags2
                    db "TZX (core 78) - Kairos",0

Inicio              di                  ; sem interrupcoes enquanto escreve a lista
                    push ix
                    push iy
                    ld (SPerro),sp
                    ld (Nome),hl        ; HL = o nome do ficheiro
                    call Maquina        ; Maq: 0 = linha de edicao, 1 = ZX 128K (reset + ENTER)
                    ld a,(Maq)
                    or a
                    jr nz,IAbre
                    call VeLinha        ; a linha de edicao tem de estar vazia (o BASIC parado)
                    jp c,ErroJogo
IAbre               ld hl,(Nome)
                    ld a,'*'
                    ld b,FA_READ
                    rst 08h
                    db F_OPEN
                    jp c,ErroAbre
                    ld (FH),a
                    ld a,1
                    ld (Aberto),a
                    ; a fita: parada, escrever do principio
                    ld bc,0FC3Bh
                    ld a,0A6h
                    out (c),a
                    inc b
                    ld a,2
                    out (c),a
                    call SelA7
                    ; o cabecalho: "ZXTape!",1Ah, versao (2)
                    ld hl,Assin
                    ld b,8
ICab                call GetB
                    cp (hl)
                    jp nz,ErroNaoTZX
                    inc hl
                    djnz ICab
                    call GetW
                    ; antes da fita: o EAR a 0 e uma pausa (no 128K o reset e o menu demoram)
                    ld hl,0C000h
                    call PutW
                    ld hl,500
                    ld a,(Maq)
                    or a
                    jr z,IPausa
                    ld hl,3000
IPausa              call PausaMs
; ---------------------------------------------------------------- os blocos
Bloco               call GetB0
                    jp c,FimFich
                    ld hl,TabBlocos
BProc               ld c,(hl)           ; id, endereco (FFh = o fim da tabela)
                    inc c
                    jp z,ErroBloco
                    dec c
                    inc hl
                    ld e,(hl)
                    inc hl
                    ld d,(hl)
                    inc hl
                    cp c
                    jr nz,BProc
                    ex de,hl
                    ld de,Bloco
                    push de
                    jp (hl)

TabBlocos           db 10h : dw B10
                    db 11h : dw B11
                    db 12h : dw B12
                    db 13h : dw B13
                    db 14h : dw B14
                    db 20h : dw B20
                    db 21h : dw SaltaB
                    db 22h : dw Nada
                    db 23h : dw Salta2
                    db 24h : dw B24
                    db 25h : dw B25
                    db 26h : dw B26
                    db 27h : dw Nada
                    db 28h : dw SaltaW
                    db 2Ah : dw Salta4L
                    db 2Bh : dw B2B
                    db 30h : dw SaltaB
                    db 31h : dw B31
                    db 32h : dw SaltaW
                    db 33h : dw B33
                    db 34h : dw Salta8
                    db 35h : dw B35
                    db 5Ah : dw Salta9
                    db 0FFh : dw 0

; 10: o bloco normal da ROM. pausa, n, dados (o 1.o byte, o flag, escolhe o tom guia)
B10                 call GetW
                    ld (Pausa),hl
                    call GetW
                    ld (Len),hl
                    xor a
                    ld (Len+2),a
                    ld a,h
                    or l
                    jr z,B10p
                    call GetB
                    ld (Volta),a        ; o flag: volta a ser lido pelos dados
                    ld hl,Tem
                    ld (hl),1
                    ld hl,8063
                    rla
                    jr nc,B10g
                    ld hl,3223
B10g                ld (NPil),hl
                    ld hl,2168
                    ld (Pil),hl
                    call Guia
                    ld hl,667
                    call PutW
                    ld hl,735
                    call PutW
                    ld hl,855
                    ld (Bit0),hl
                    ld hl,1710
                    ld (Bit1),hl
                    ld a,8
                    ld (Usados),a
                    call Dados
B10p                ld hl,(Pausa)
                    jp PausaMs
; 11: turbo. guia, sync 1, sync 2, bit 0, bit 1, n do guia, bits do ultimo, pausa, n (3)
B11                 call GetW
                    ld (Pil),hl
                    call GetW
                    ld (Sinc1),hl
                    call GetW
                    ld (Sinc2),hl
                    call GetW
                    ld (Bit0),hl
                    call GetW
                    ld (Bit1),hl
                    call GetW
                    ld (NPil),hl
                    call GetB
                    ld (Usados),a
                    call GetW
                    ld (Pausa),hl
                    call Get3
                    call Guia
                    ld hl,(Sinc1)
                    call Impulso
                    ld hl,(Sinc2)
                    call Impulso
                    call Dados
                    ld hl,(Pausa)
                    jp PausaMs
; 12: tom. L, N
B12                 call GetW
                    ld (Pil),hl
                    call GetW
                    ld (NPil),hl
                    jp Guia
; 13: impulsos. n, n x L
B13                 call GetB
                    or a
                    ret z
                    ld b,a
B13l                call GetW
                    call Impulso
                    djnz B13l
                    ret
; 14: so' dados. bit 0, bit 1, bits do ultimo, pausa, n (3)
B14                 call GetW
                    ld (Bit0),hl
                    call GetW
                    ld (Bit1),hl
                    call GetB
                    ld (Usados),a
                    call GetW
                    ld (Pausa),hl
                    call Get3
                    call Dados
                    ld hl,(Pausa)
                    jp PausaMs
; 20: pausa (ms; 0 = parar a fita: aqui nao para)
B20                 call GetW
                    jp PausaMs
; 24: o principio do ciclo (n vezes): os bytes seguintes ficam guardados ate' ao 25
B24                 call GetW
                    ld a,(Grava)
                    or a
                    jp nz,ErroCiclo     ; um ciclo dentro do outro
                    ld a,(Repete)
                    or a
                    jp nz,ErroCiclo
                    ld a,h
                    or l
                    jr nz,B24n
                    inc hl
B24n                ld (NCiclo),hl
                    ld hl,LBUF
                    ld (CicloW),hl
                    ld a,1
                    ld (Grava),a
                    ret
; 25: o fim do ciclo (o 25 tambem ficou guardado: na repeticao volta aqui)
B25                 ld a,(Grava)        ; sem o 24 antes: ignora-se
                    ld hl,Repete
                    or (hl)
                    ret z
                    xor a
                    ld (Grava),a
                    ld hl,(NCiclo)
                    dec hl
                    ld (NCiclo),hl
                    ld a,h
                    or l
                    jr z,B25fim
                    ld hl,LBUF
                    ld (CicloR),hl
                    ld a,1
                    ld (Repete),a
                    ret
B25fim              ld (Repete),a       ; A = 0
                    ret
; 26: chamadas (n, n x 2): ignoradas
B26                 call GetW
                    add hl,hl
                    jr SaltaHL
; 2B: o nivel do sinal. comprimento (4) = 1, nivel
B2B                 call Salta4
                    call GetB
                    ld hl,0C000h
                    or a
                    jr z,B2Bp
                    ld hl,0E000h
B2Bp                jp PutW
; 31: mensagem. tempo, n, texto
B31                 call GetB
                    jr SaltaB
; 33: hardware. n, n x 3
B33                 call GetB
                    ld l,a
                    ld h,0
                    ld e,l
                    ld d,h
                    add hl,hl
                    add hl,de
                    jr SaltaHL
; 35: informacao. nome (16), comprimento (4), dados
B35                 ld hl,16
                    call SaltaHL
Salta4L             call Get3           ; comprimento (4): os 3 bytes baixos, o alto tem de ser 0
                    call GetB
                    or a
                    jp nz,ErroBloco
                    jr SaltaLen
Salta2              ld hl,2
                    jr SaltaHL
Salta4              ld hl,4
                    jr SaltaHL
Salta8              ld hl,8
                    jr SaltaHL
Salta9              ld hl,9
                    jr SaltaHL
SaltaW              call GetW
                    jr SaltaHL
SaltaB              call GetB
                    ld l,a
                    ld h,0
SaltaHL             ld (Len),hl
                    xor a
                    ld (Len+2),a
SaltaLen            ld hl,(Len)         ; salta Len (3) bytes
                    ld a,(Len+2)
                    ld c,a
SLl                 ld a,h
                    or l
                    or c
                    ret z
                    call GetB
                    ld a,h
                    or l
                    dec hl
                    jr nz,SLl
                    dec c
                    jr SLl
Nada                ret

; ---------------------------------------------------------------- o fim do ficheiro
FimFich             ld hl,0FFFFh        ; (um ciclo sem o fim: fica como foi lido)
                    call PutW
                    call EsperaW
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    xor a
                    ld (Aberto),a
                    ld bc,0FC3Bh        ; a fita a tocar
                    ld a,0A6h
                    out (c),a
                    inc b
                    ld a,1
                    out (c),a
                    call SelA7          ; o registo A6h nao fica escolhido (um OUT FD3B a seguir parava a fita)
                    ld a,(Maq)
                    or a
                    jp nz,Reset128
                    call PoeLoad        ; LOAD "" e o ENTER pendente, na copia da RAM
                    ld bc,TxtLoad
                    ld a,31h            ; OK + mensagem + 20h: sair do navegador
                    jp Fim
Reset128            ld bc,0FC3Bh        ; ZXUNO A5h: o core faz o reset quando o NMI acabar e carrega no ENTER
                    ld a,0A5h           ; 2 s depois: o Tape Loader do menu da Sinclair
                    out (c),a
                    inc b
                    out (c),a
                    ld bc,TxtRst
                    ld a,31h
Fim                 push af
                    xor a
                    out (0E3h),a
                    pop af
                    ld sp,(SPerro)
                    pop iy
                    pop ix
                    ret

; ---------------------------------------------------------------- os erros
ErroAbre            ld hl,TxtAbre
                    jr Erro
ErroNaoTZX          ld hl,TxtNaoTZX
                    jr Erro
ErroBloco           ld (TxtBlocoN),a    ; A = o id do bloco
                    call Hex
                    ld hl,TxtBloco
                    jr Erro
ErroCiclo           ld hl,TxtCiclo
                    jr Erro
ErroGrande          ld hl,TxtGrande
                    jr Erro
ErroCorte           ld hl,TxtCorte
                    jr Erro
ErroLe              ld hl,TxtLe
                    jr Erro
ErroJogo            ld hl,TxtJogo
                    jr Erro
ErroCore            ld hl,TxtCore
Erro                ld sp,(SPerro)
                    push hl
                    ld a,(Aberto)
                    or a
                    jr z,ESemF
                    ld a,(FH)
                    rst 08h
                    db F_CLOSE
                    ld bc,0FC3Bh        ; a fita parada
                    ld a,0A6h
                    out (c),a
                    inc b
                    xor a
                    out (c),a
ESemF               xor a
                    out (0E3h),a
                    pop bc
                    pop iy
                    pop ix
                    ld a,PLUGIN_ERROR|PLUGIN_MSG|PLUGIN_RESTORE_BUFFERS
                    ret
Hex                 ld a,(TxtBlocoN)    ; o id em hexadecimal, em TxtBlocoN (2 letras)
                    push af
                    rrca
                    rrca
                    rrca
                    rrca
                    call HexD
                    ld (TxtBlocoN),a
                    pop af
                    call HexD
                    ld (TxtBlocoN+1),a
                    ret
HexD                and 0Fh
                    add a,'0'
                    cp '9'+1
                    ret c
                    add a,7
                    ret

; ---------------------------------------------------------------- a lista (escrita no core)
; o tom: Pil, NPil (nada se NPil = 0)
Guia                ld hl,(NPil)
                    ld a,h
                    or l
                    ret z
                    ld hl,0F001h
                    call PutW
                    ld hl,(Pil)
                    call Max15
                    call PutW
                    ld hl,(NPil)
                    jp PutW
; um impulso de HL T (0 nao conta; mais de 32767 fica 32767)
Impulso             ld a,h
                    or l
                    ret z
                    call Max15
                    jp PutW
Max15               bit 7,h
                    ret z
                    ld hl,7FFFh
                    ret
; os dados: Len (3) bytes do ficheiro, Bit0, Bit1, Usados (no ultimo). Aos bocados de 32K.
Dados               ld a,(Usados)       ; 0 ou mais de 8: 8
                    dec a
                    cp 8
                    jr c,DOk
                    ld a,8
                    ld (Usados),a
DOk                 ld hl,(Len)
                    ld a,(Len+2)
                    ld c,a
                    or h
                    or l
                    ret z
                    ld a,c              ; ate' 32K: o ultimo bocado
                    or a
                    jr nz,DGrande
                    ld de,8001h
                    push hl
                    sbc hl,de
                    pop hl
                    jr nc,DGrande
                    ld a,(Usados)
                    ld c,a
                    call Bocado
                    ret
DGrande             ld de,8000h         ; Len -= 32K
                    or a
                    sbc hl,de
                    ld (Len),hl
                    ld a,(Len+2)
                    sbc a,0
                    ld (Len+2),a
                    ld hl,8000h
                    ld c,8
                    call Bocado
                    jr DOk
; HL bytes, C = bits do ultimo
Bocado              push hl
                    push bc
                    ld hl,0F002h
                    call PutW
                    ld hl,(Bit0)
                    call Max15
                    call PutW
                    ld hl,(Bit1)
                    call Max15
                    call PutW
                    pop bc
                    pop hl
                    call PutW           ; N
                    push hl
                    ld l,c
                    ld h,0
                    call PutW           ; U
                    pop hl
                    ld a,l
                    ld (Impar),a
Bcl                 ld a,h
                    or l
                    jr z,Bpad
                    call GetB
                    call PutB
                    dec hl
                    jr Bcl
Bpad                ld a,(Impar)        ; a acabar numa palavra inteira
                    rra
                    ret nc
                    xor a
                    jp PutB
; pausa de HL ms (0: nada), depois o EAR a 0
PausaMs             ld a,h
                    or l
                    ret z
PMgr                ld a,h              ; 256 ms de cada vez: 14000 x 64 T
                    or a
                    jr z,PMpeq
                    push hl
                    ld hl,8000h+14000
                    call PutW
                    pop hl
                    dec h
                    jr PMgr
PMpeq               ld a,l              ; o resto: n x 55 x 64 T (3520 T ~ 1 ms)
                    or a
                    jr z,PMfim
                    ld l,a
                    ld h,0
                    ld e,l
                    ld d,h
                    add hl,hl           ; x 55 = x 64 - x 8 - x 1
                    add hl,hl
                    add hl,hl
                    push hl             ; x 8
                    add hl,hl
                    add hl,hl
                    add hl,hl           ; x 64
                    pop bc
                    or a
                    sbc hl,bc
                    sbc hl,de
                    set 7,h
                    call PutW
PMfim               ld hl,0C000h
                    jp PutW
; uma palavra (HL), byte baixo primeiro
PutW                ld a,l
                    call PutB
                    ld a,h
; um byte para a lista (registo A7h ja' escolhido): espera que o anterior tenha ido para a SDRAM
; (o registo A7h escolhido outra vez a cada byte; sem resposta do core em ~65000 voltas: erro, nao pendura)
PutB                push bc
                    push de
                    push af
                    call Espera
                    pop af
                    out (c),a
                    pop de
                    pop bc
                    ret
EsperaW             push bc
                    push de
                    call Espera
                    pop de
                    pop bc
                    ret
; BC = FD3Bh com o A7h escolhido, o ultimo byte ja' na SDRAM (muda A, DE)
Espera              ld bc,0FC3Bh
                    ld a,0A7h
                    out (c),a
                    inc b
                    ld de,0
EWl                 in a,(c)
                    and 4
                    ret z
                    dec de
                    ld a,d
                    or e
                    jr nz,EWl
                    jp ErroCore
SelA7               push bc
                    push af
                    ld bc,0FC3Bh
                    ld a,0A7h
                    out (c),a
                    pop af
                    pop bc
                    ret

; ---------------------------------------------------------------- a leitura do ficheiro
; GetB0: A = o byte seguinte, CF = o ficheiro acabou (so' entre blocos). Guarda os bytes de um ciclo; na
; repeticao le' do LBUF. Nao mexe nos outros registos.
GetB0               push hl
                    push bc
                    ld a,(Repete)
                    or a
                    jr z,GBfich
                    ld hl,(CicloR)
                    ld a,(hl)
                    inc hl
                    ld (CicloR),hl
                    jr GBok
GBfich              ld bc,(BufN)
                    ld a,b
                    or c
                    jr nz,GBtem
                    call Enche
                    jr c,GBfim
GBtem               dec bc
                    ld (BufN),bc
                    ld hl,(BufP)
                    ld a,(hl)
                    inc hl
                    ld (BufP),hl
                    ld c,a
                    ld a,(Grava)
                    or a
                    ld a,c
                    jr z,GBok
                    ld hl,(CicloW)      ; a gravar o ciclo
                    ld (hl),a
                    inc hl
                    ld (CicloW),hl
                    ld a,h
                    cp LBUFFIM/256
                    jp z,ErroGrande
                    ld a,c
GBok                pop bc
                    pop hl
                    or a
                    ret
GBfim               pop bc
                    pop hl
                    scf
                    ret
; o byte seguinte, que tem de existir
GetB                push hl
                    ld hl,Tem           ; o byte devolvido (o flag do bloco 10)
                    ld a,(hl)
                    or a
                    jr z,GBnovo
                    ld (hl),0
                    ld a,(Volta)
                    pop hl
                    ret
GBnovo              pop hl
                    call GetB0
                    ret nc
                    jp ErroCorte
GetW                call GetB
                    ld l,a
                    call GetB
                    ld h,a
                    ret
Get3                call GetW           ; Len = 3 bytes
                    ld (Len),hl
                    call GetB
                    ld (Len+2),a
                    ret
; 4K do ficheiro para o BUF. CF = acabou. BC = quantos.
Enche               ld a,(FH)
                    ld hl,BUF
                    ld bc,BUFTAM
                    rst 08h
                    db F_READ
                    jp c,ErroLe
                    di                  ; (o esxDOS podia ter ligado as interrupcoes)
                    ld hl,BUF
                    ld (BufP),hl
                    ld (BufN),bc
                    ld a,b
                    or c
                    scf
                    ret z
                    or a
                    ret

; ---------------------------------------------------------------- a maquina e o LOAD "" (como o stub68)
; Maq = 1 no ZX 128K do NAV (o .go128 -divmenu deixa "M8" em 2000h da pagina 39), 0 nos outros
Maquina             xor a
                    ld (Maq),a
                    ld a,(5C50h)        ; TC2068 (CHANS alto 68h): linha de edicao
                    cp 68h
                    ret z
                    ld a,80h+39
                    out (0E3h),a
                    ld hl,(2000h)
                    xor a
                    out (0E3h),a
                    ld de,384Dh         ; "M8"
                    or a
                    sbc hl,de
                    ret nz
                    ld a,1
                    ld (Maq),a
                    ret
; CF = a linha de edicao da copia nao esta' vazia (ou fora do sitio): nao da' para escrever o LOAD ""
VeLinha             ld hl,ELINE
                    call LePal
                    ld (VELine),de
                    ld a,d              ; E_LINE tem de estar na RAM do BASIC
                    cp 5Ch
                    jr c,VLmal
                    ex de,hl
                    call LeByte
                    cp 0Dh
                    jr nz,VLmal
                    ld hl,STKEND
                    call LePal
                    ld (VStkend),de
                    ld a,d
                    cp 0FDh             ; a copia so' vai ate' FDFFh
                    jr nc,VLmal
                    ld hl,(VStkend)
                    ld de,(VELine)
                    or a
                    sbc hl,de
                    jr c,VLmal
                    xor a
                    out (0E3h),a
                    or a
                    ret
VLmal               xor a
                    out (0E3h),a
                    scf
                    ret
PoeLoad             ld hl,(VStkend)     ; BC = STKEND - E_LINE
                    ld de,(VELine)
                    or a
                    sbc hl,de
                    ld b,h
                    ld c,l
                    ld hl,(VStkend)
                    dec hl
PLmove              ld a,b              ; [E_LINE, STKEND) sobe 3 bytes, de cima para baixo
                    or c
                    jr z,PLescreve
                    call LeByte
                    inc hl
                    inc hl
                    inc hl
                    call PoeByte
                    dec hl
                    dec hl
                    dec hl
                    dec hl
                    dec bc
                    jr PLmove
PLescreve           ld hl,(VELine)
                    ld a,0EFh           ; LOAD
                    call PoeByte
                    inc hl
                    ld a,22h            ; "
                    call PoeByte
                    inc hl
                    call PoeByte
                    inc hl
                    ex de,hl            ; DE = E_LINE+3: o cursor antes do ENTER da linha
                    ld hl,KCUR
                    call PoePal
                    ld hl,WORKSP
                    call Mais3
                    ld hl,STKBOT
                    call Mais3
                    ld hl,STKEND
                    call Mais3
                    ld hl,LASTK
                    ld a,0Dh            ; ENTER a' espera
                    call PoeByte
                    ld hl,FLAGS
                    call LeByte
                    or 20h              ; KEYHIT
                    call PoeByte
                    xor a
                    out (0E3h),a
                    ret
; HL = endereco da RAM do BASIC -> HL = sitio na copia (2000h-3FFFh), pagina ligada (NMI: paginas 5-10)
Mapa                ld a,h
                    sub 40h
                    rlca
                    rlca
                    rlca
                    and 7
                    add a,5
                    out (0E3h),a
                    ld a,h
                    and 1Fh
                    or 20h
                    ld h,a
                    ret
LeByte              push hl
                    call Mapa
                    ld a,(hl)
                    pop hl
                    ret
PoeByte             push hl
                    push af
                    call Mapa
                    pop af
                    ld (hl),a
                    pop hl
                    ret
LePal               call LeByte
                    ld e,a
                    inc hl
                    call LeByte
                    ld d,a
                    dec hl
                    ret
PoePal              ld a,e
                    call PoeByte
                    inc hl
                    ld a,d
                    call PoeByte
                    dec hl
                    ret
Mais3               call LePal
                    inc de
                    inc de
                    inc de
                    jr PoePal

; ---------------------------------------------------------------- dados
Assin               db "ZXTape!",1Ah
TxtAbre             db "TZX: nao abre",0
TxtNaoTZX           db "Nao e' um TZX",0
TxtBloco            db "TZX: bloco "
TxtBlocoN           db "00 nao da'",0
TxtCiclo            db "TZX: ciclo dentro de ciclo",0
TxtGrande           db "TZX: ciclo maior que 8K",0
TxtCorte            db "TZX: o ficheiro acaba a meio",0
TxtLe               db "TZX: erro a ler",0
TxtCore             db "TZX: o core nao responde (core 78+)",0
TxtJogo             db "TZX: so' no BASIC (faz reset)",0
TxtLoad             db "LOAD \"\" (TZX)",0
TxtRst              db "Tape Loader (TZX)",0
SPerro              dw 0
Nome                dw 0
FH                  db 0
Aberto              db 0
Maq                 db 0
BufN                dw 0
BufP                dw 0
Tem                 db 0
Volta               db 0
Grava               db 0
Repete              db 0
CicloW              dw 0
CicloR              dw 0
NCiclo              dw 0
Len                 ds 3
Pausa               dw 0
Pil                 dw 0
NPil                dw 0
Sinc1               dw 0
Sinc2               dw 0
Bit0                dw 0
Bit1                dw 0
Usados              db 0
Impar               db 0
VELine              dw 0
VStkend             dw 0
