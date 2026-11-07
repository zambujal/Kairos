# Kairos — Timex TC2068 e TC2048 num Tang Nano 20K

*In English: [README.en.md](README.en.md)*

Core em VHDL para a **Sipeed Tang Nano 20K** (Gowin GW2AR-18). Faz de Timex **TC2048** e **TC2068**, ZX Spectrum
48K e 128K, e Pentagon 128/512/1024. HDMI 720p50, esxDOS no cartão microSD, teclado USB. Só precisa do Tang,
do cartão e do teclado.

- **Timex a sério:** EXROM, hi-colour, hi-res 512×192, contenção e barramento flutuante, do modelo do SCLD que
  reparei e testei num TC2068 verdadeiro.
- **Som:** TurboSound (2 AY), General Sound, beeper, pelo HDMI. ULAplus.
- **Z80:** T80 corrigido (registo Q), de 3,5 a 27 MHz com F9/F10.
- **Cartão:** navegador próprio (menu das máquinas, rato; nomes compridos se o `cartao.py` correr no cartão), plugins TAP, TZX, Z80, SNA, TRD,
  PT3, AY, MOD. O TZX toca na própria FPGA, com o `LOAD ""` escrito sozinho e pausa/paragem em F3/F4.
- **ROMs no cartão:** ao ligar lê do cartão a ROM do TC2048 e o esxDOS. A pasta `cartao/` já traz as ROMs do
  TC2048 e do 2068 ([porquê](#as-roms-do-timex-no-cartão)); o esxDOS mete-o cada um.

A placa com ESP32-S3 (capas, rede, NAS, MP3) é outro projecto; nada aqui depende dela. Até 1 de Novembro
de 2026 chamou-se Timorphius; antes, Timextenso e Timmy.

**De onde veio:** o Kairos nasceu do **Timmy**, uma máquina real: um clone do TC2048 com Z80 verdadeiro, a
RAM de vídeo 4464 do Timex e o SCLD num CPLD (XC95288XL). Ligada a ele, como **addon**, está uma interface
**DivTIESUS** (DivMMC, num EPM240), à qual foi trocada a SRAM por uma de **512K**; essa SRAM passou a servir
também de memória para o Timmy (bancos do 128K, ROM em RAM, sombra da RAM de vídeo). Sem o addon o Timmy
funciona normalmente, como um TC2048. Foi aí que se fizeram o
128K, o Pentagon, o TC2068 e o navegador; o Kairos levou esse código para a FPGA e juntou o que um CPLD não
comporta. O SCLD e a DivTIESUS estão em https://github.com/zambujal/divtiesus-scld-timex . O navegador e os
programas do cartão servem nas duas.

## Pôr a funcionar

Os pormenores estão em [docs/instalacao.md](docs/instalacao.md); as teclas em [docs/teclas.md](docs/teclas.md).

1. **Core.** O `kairos.fs` dos *Releases* grava-se na flash com o Gowin Programmer (External Flash Mode,
   `0x000000`) ou com `openFPGALoader -b tangnano20k -f kairos.fs`. Para compilar: Gowin EDA 1.9.11+,
   `gw_sh kairos.tcl` em `core/` (`faz_576p.sh` dá a versão 576p).
2. **Teclado.** O BL616 do Tang leva o **FPGA Companion + Partner** de Till Harbaum (placa 3921 ou 3923:
   firmware diferente). Com ele a placa é teclado quando está sem PC e programador quando está numa porta
   directa do PC.
3. **Cartão** (FAT32): `BIN`, `SYS` e `TMP` do esxDOS; o zip do Bob Fossil por cima (traz o `NMI.SYS` e os
   plugins, que o esxDOS não traz); a pasta `cartao/` deste repositório por cima (traz a `SYS/ROMS/TC2048.ROM` e
   a `BIN/2068.rom`); o `SYS/ROMS/ESXMMC.BIN` do esxDOS. Opcionais, para as outras máquinas: `BIN/128.rom`,
   `BIN/GS105B.ROM` e o `BIN/PLUG2068/TAP` feito com `fontes/plug2068/faz_plug2068.py`. Em Linux,
   `ferramentas/faz_cartao.sh` faz tudo menos o `ESXMMC.BIN` e as ROMs opcionais.
4. **Índices.** Sem eles o navegador mostra nomes 8.3 (`JETSETW~1.TAP`) e o menu das máquinas só abre com as
   teclas 1 a 4. `python3 ferramentas/cartao.py /caminho/do/cartao --fazer`, com o cartão no PC, escreve em cada
   pasta um `_NAV/*.IDX` com os nomes compridos. Repetir quando se juntam jogos.
5. **Ligar** por um carregador de 2 A. O botão do pino 87 (ou **Home**) é o NMI (navegador); **Ctrl+Alt+Shift** = RESET+NMI (volta ao TC2048), para quando um jogo estraga o NMI; Ctrl+Alt+AltGr = reset normal; o do pino 88 escolhe, nos LEDs,
   o que o NMI faz (RESET, `.go128`, `.go2068`, turbo…). Liga sempre em TC2048; o navegador propõe a última
   máquina.

Se o navegador aparecer a preto e branco, falta o `NMI.SYS` do Bob Fossil ou a pasta `cartao/`.

## Usar

- **Velocidade:** **F10** sobe (3,5 → 7 → 14 → 27 MHz), **F9** desce. Ao ligar é sempre 3,5 MHz. A 27 MHz, com a
  DivMMC mapeada (esxDOS, navegador, cargas), desce para 14; perto de cada acesso ao cartão anda a 3,5, para o
  cartão ficar a salvo.
- **TZX:** a partir do BASIC, ENTER num `.TZX` no navegador toca a fita à velocidade da máquina e escreve sozinho
  o `LOAD ""` (no 128K faz reset e escolhe o Tape Loader); o F10 acelera a carga. **F3** pausa no fim do bloco
  que está a tocar, **F4** pára já; outra vez continua. No canto de cima à esquerda um quadrado (verde a tocar,
  amarelo em pausa, vermelho parada) e um rectângulo por bloco aparecem 3 s a cada bloco e ficam enquanto
  estiver em pausa. Quem toca a fita é o Z80 do General Sound: enquanto toca não há música do GS, e no fim o
  GS volta a como estava. Os blocos 15, 18 e 19 não dão.
- **ZX 128K** arranca no menu da Sinclair; um TAP escolhido no navegador faz reset e o Tape Loader carrega-o.
  Para demos e jogos de Pentagon 128 usa o **Pentagon 128**, não o 1024 (os bits 5-7 do 7FFD escolhem bancos
  no 1024 e uma demo de 128 que os escreva salta para outra zona da memória).

## De quem é

- **SCLD:** modelo do Load ZX Museum (Álvaro Lopes, Paulo Cortesão, CC BY-SA 4.0), reparado e completado por
  mim para o [CPLD de substituição](https://github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex).
- **Z80:** T80 (Daniel Wallner, Sorgelig), [corrigido por mim em 2026](https://github.com/zambujal/T80-Q-fix).
- **Meu** (GPL v3): o core, o vídeo, o HDMI, o som, a ponte do cartão, o arranque, o navegador e os programas do
  cartão, o `cartao.py`. Foi usada IA (Claude).
- **De outros** (`LICENCAS.md`): YM2149 (MikeJ), General Sound, SID, sysctrl, mcu_spi (MiSTer / MiSTeryNano),
  DivTIESUS e ULAplus (ZX-UNO), leitor PT3 (S. V. Bulba), HDMI (hdl-util / NanoMig).
- **Não está aqui:** o esxDOS, os plugins do Bob Fossil, o firmware do BL616 e as outras ROMs (128K, General
  Sound, FDD3000). As do TC2048 e do 2068 estão, em `cartao/` (em baixo).

## As ROMs do Timex no cartão

A pasta `cartao/` traz a `SYS/ROMS/TC2048.ROM` (a do Timex TC2048, 16384 bytes, md5
`9dd7ecf784a6c04265c073c236f5fadb`) e a `BIN/2068.rom` (a do TS2068, HOME + EXROM, 24576 bytes, md5
`9194283503a105f3f3dfba13e61e993f`), para o Kairos arrancar e passar a TC2068 sem ninguém ter de ir à procura de
ROMs. São os mesmos ficheiros que o emulador [ZEsarUX](https://github.com/chernandezba/zesarux) traz no seu
repositório (`src/tc2048.rom` e `src/ts2068.rom`); a do TC2048 vem também no pacote `spectrum-roms` do Debian e a
do TS2068 no [Spectrum Computing](https://spectrumcomputing.co.uk/entry/1000506/Hardware/TimexSinclair_TS2068).

São a ROM do Spectrum da Sinclair, hoje da Amstrad, com as mudanças da Timex:

- a Amstrad deixa os emuladores incluírem as suas ROMs ("Amstrad are happy for emulator writers to include
  images of our copyrighted code", Cliff Lawson, Amstrad; ver o
  [copyright do pacote spectrum-roms do Debian](https://tracker.debian.org/media/packages/s/spectrum-roms/copyright-20081224-5),
  que traz a do TC2048);
- a nota das ROMs do emulador zxsp diz da do TC2048 que é da Amstrad, que deixa distribuí-la, e das do TC2068
  que são feitas do código da Amstrad e que as mudanças da Timex estão no domínio público
  ([README.copyright](https://k1.spdns.de/Develop/Projects/zxsp/Media/Roms/README.copyright)); a do TS2068 tem a
  mesma origem.

A `2068.rom` é a de 24K, sem o esxDOS: o modo TC2068 arranca, mas sem esxDOS. O esxDOS do 2068 (o ESX2068, a
`2068.rom` de 32K) é feito do esxDOS e não se pode pôr aqui. O esxDOS também não: é de
[esxdos.org](https://www.esxdos.org), e cada um mete o seu `SYS/ROMS/ESXMMC.BIN`.

Ligações: [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) ·
[Gowin EDA](https://www.gowinsemi.com/en/support/download_eda/) ·
[openFPGALoader](https://github.com/trabucayre/openFPGALoader) · [esxDOS](https://www.esxdos.org) ·
[Bob Fossil](http://www.thefossilrecord.co.uk) · [FPGA Companion](https://github.com/MiSTle-Dev/FPGA-Companion) ·
[gs-firmware](https://github.com/psbhlw/gs-firmware) · [DivTIESUS](https://github.com/mcleod-ideafix/divtiesus) ·
[sjasmplus](https://github.com/z00m128/sjasmplus) · ROMs: [worldofspectrum.org](https://worldofspectrum.org),
[timexsinclair.com](https://www.timexsinclair.com)
