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
- **Sem ROMs dentro:** ao ligar lê do cartão a ROM do TC2048 e o esxDOS.

A placa com ESP32-S3 (capas, rede, NAS, MP3) é outro projecto; nada aqui depende dela. Até 1 de Novembro
de 2026 chamou-se Timorphius; antes, Timextenso e Timmy.

## Pôr a funcionar

Os pormenores estão em [docs/instalacao.md](docs/instalacao.md); as teclas em [docs/teclas.md](docs/teclas.md).

1. **Core.** O `kairos.fs` dos *Releases* grava-se na flash com o Gowin Programmer (External Flash Mode,
   `0x000000`) ou com `openFPGALoader -b tangnano20k -f kairos.fs`. Para compilar: Gowin EDA 1.9.11+,
   `gw_sh kairos.tcl` em `core/` (`faz_576p.sh` dá a versão 576p).
2. **Teclado.** O BL616 do Tang leva o **FPGA Companion + Partner** de Till Harbaum (placa 3921 ou 3923:
   firmware diferente). Com ele a placa é teclado quando está sem PC e programador quando está numa porta
   directa do PC.
3. **Cartão** (FAT32): `BIN`, `SYS` e `TMP` do esxDOS; o zip do Bob Fossil por cima (traz o `NMI.SYS` e os
   plugins, que o esxDOS não traz); a pasta `cartao/` deste repositório por cima; `SYS/ROMS/TC2048.ROM` e
   `SYS/ROMS/ESXMMC.BIN`. Opcionais, para as outras máquinas: `BIN/128.rom`, `BIN/2068.rom`, `BIN/GS105B.ROM`
   e o `BIN/PLUG2068/TAP` feito com `fontes/plug2068/faz_plug2068.py`. Em Linux, `ferramentas/faz_cartao.sh`
   faz tudo menos as ROMs.
4. **Índices.** Sem eles o navegador mostra nomes 8.3 (`JETSETW~1.TAP`) e o menu das máquinas só abre com as
   teclas 1 a 4. `python3 ferramentas/cartao.py /caminho/do/cartao --fazer`, com o cartão no PC, escreve em cada
   pasta um `_NAV/*.IDX` com os nomes compridos. Repetir quando se juntam jogos.
5. **Ligar** por um carregador de 2 A. O botão do pino 87 é o NMI (navegador); o do pino 88 escolhe, nos LEDs,
   o que o NMI faz (RESET, `.go128`, `.go2068`, turbo…). Liga sempre em TC2048; o navegador propõe a última
   máquina.

Se o navegador aparecer a preto e branco, falta o `NMI.SYS` do Bob Fossil ou a pasta `cartao/`.

## De quem é

- **SCLD:** modelo do Load ZX Museum (Álvaro Lopes, Paulo Cortesão, CC BY-SA 4.0), reparado e completado por
  mim para o [CPLD de substituição](https://github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex).
- **Z80:** T80 (Daniel Wallner, Sorgelig), [corrigido por mim em 2026](https://github.com/zambujal/T80-Q-fix).
- **Meu** (GPL v3): o core, o vídeo, o HDMI, o som, a ponte do cartão, o arranque, o navegador e os programas do
  cartão, o `cartao.py`. Escrito com ajuda de IA.
- **De outros** (`LICENCAS.md`): YM2149 (MikeJ), General Sound, SID, sysctrl, mcu_spi (MiSTer / MiSTeryNano),
  DivTIESUS e ULAplus (ZX-UNO), leitor PT3 (S. V. Bulba), HDMI (hdl-util / NanoMig).
- **Não está aqui:** ROMs (Timex, Sinclair, Amstrad), esxDOS, plugins do Bob Fossil, firmware do BL616.

Ligações: [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) ·
[Gowin EDA](https://www.gowinsemi.com/en/support/download_eda/) ·
[openFPGALoader](https://github.com/trabucayre/openFPGALoader) · [esxDOS](https://www.esxdos.org) ·
[Bob Fossil](http://www.thefossilrecord.co.uk) · [FPGA Companion](https://github.com/MiSTle-Dev/FPGA-Companion) ·
[gs-firmware](https://github.com/psbhlw/gs-firmware) · [DivTIESUS](https://github.com/mcleod-ideafix/divtiesus) ·
[sjasmplus](https://github.com/z00m128/sjasmplus) · ROMs: [worldofspectrum.org](https://worldofspectrum.org),
[timexsinclair.com](https://www.timexsinclair.com)
