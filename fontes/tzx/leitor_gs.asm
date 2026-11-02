; leitor_gs.asm - o leitor de cassete que corre no Z80 do General Sound (core 81+), posto pelo plugin TZX.
; O plugin escreve este programa no principio da pagina 2 da memoria do GS e, logo a seguir, a lista da fita
; (o formato do plugin_tzx.asm). Com o modo "fita" do core, 0000h-3FFFh e' o principio da pagina 2: o programa
; corre daqui; a lista le-se pela janela 8000h-FFFFh (porta 0 = a pagina).
; Portas do leitor (gs.vhd): C escrita byte baixo / D escrita byte alto (a palavra vai para a cassete),
;   C leitura lugares livres, D leitura bit 0 F3, bit 1 F4, bit 2 a cassete a tocar,
;   E escrita o estado (bit 0 pausa pedida, 1 parada, 2 parada ja'; bit 7 acabou), F escrita o bloco.
; Teclas: F3 pede a pausa (fica na pausa seguinte da fita, depois dos dados do bloco); outro F3 continua.
;         F4 para ja' (o core para a cassete no sitio); outro F4, ou F3, continua.
; Monta-se com  sjasmplus --raw=LEITOR.BIN leitor_gs.asm  (o plugin junta-o com incbin)

                    org 0
                    di
                    ld sp,5FF0h         ; a pilha na pagina 1 (4000h-5FFFh: as leituras em 6000h-7FFFh vao para os canais)
                    xor a
                    ld (Ped),a
                    ld (Par),a
                    ld (Gelo),a
                    ld (Bloco),a
                    out (0Fh),a
                    call Estado
                    in a,(0Dh)
                    ld (TAnt),a
                    ld a,2
                    ld (Pag),a
                    out (0),a
                    ld hl,8000h+Lista
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
                    ld a,80h
                    out (0Eh),a
                    jr $
; ---------------------------------------------------------------- a cassete
; manda a palavra DE (espera lugar na fila; trata das teclas)
Envia               call Teclas
                    in a,(0Ch)
                    cp 5
                    jr c,Envia
                    ld a,e
                    out (0Ch),a
                    ld a,d
                    out (0Dh),a
                    ret
; espera ate' a pausa acabar (F3 outra vez, ou F4)
Pausa               ld a,1
                    ld (Par),a
                    call Estado
PAl                 call Teclas
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
                    ld a,(Gelo)
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
