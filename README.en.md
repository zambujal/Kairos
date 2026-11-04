# Kairos — Timex TC2068 and TC2048 on a Tang Nano 20K

*Em português: [README.md](README.md)*

A VHDL core for the **Sipeed Tang Nano 20K** (Gowin GW2AR-18). It is a Timex **TC2048** and **TC2068**, a ZX
Spectrum 48K and 128K, and a Pentagon 128/512/1024. HDMI 720p50, esxDOS on the microSD card, USB keyboard.
All it needs is the Tang, the card and the keyboard.

- **A real Timex:** EXROM, hi-colour, hi-res 512×192, contention and floating bus, from the SCLD model I
  repaired and tested on a real TC2068.
- **Sound:** TurboSound (2 AY), General Sound, beeper, over HDMI. ULAplus.
- **Z80:** a fixed T80 (Q register), 3.5 to 27 MHz with F9/F10.
- **Card:** own browser (machine menu, mouse; long names if `cartao.py` is run on the card), plugins for TAP, TZX, Z80, SNA, TRD, PT3, AY, MOD.
  TZX plays inside the FPGA, types `LOAD ""` by itself, F3 pauses and F4 stops.
- **No ROMs inside:** at power-up it reads the TC2048 ROM and esxDOS from the card.

The ESP32-S3 board (covers, network, NAS, MP3) is a separate project; nothing here depends on it. Until
1 November 2026 this was called Timorphius; before that, Timextenso and Timmy.

## Getting it running

Details in [docs/install.en.md](docs/install.en.md); keys in [docs/teclas.md](docs/teclas.md).

1. **Core.** Flash the `kairos.fs` from *Releases* with the Gowin Programmer (External Flash Mode, `0x000000`)
   or `openFPGALoader -b tangnano20k -f kairos.fs`. To build: Gowin EDA 1.9.11+, `gw_sh kairos.tcl` in `core/`
   (`faz_576p.sh` gives the 576p version).
2. **Keyboard.** The Tang's BL616 gets Till Harbaum's **FPGA Companion + Partner** (board 3921 or 3923: different
   firmware). With it the board is a keyboard when there is no PC and a programmer when on a direct PC port.
3. **Card** (FAT32): `BIN`, `SYS` and `TMP` from esxDOS; Bob Fossil's zip on top (it brings `NMI.SYS` and the
   plugins, which esxDOS does not); this repository's `cartao/` on top; `SYS/ROMS/TC2048.ROM` and
   `SYS/ROMS/ESXMMC.BIN`. Optional, for the other machines: `BIN/128.rom`, `BIN/2068.rom`, `BIN/GS105B.ROM`
   and `BIN/PLUG2068/TAP` made with `fontes/plug2068/faz_plug2068.py`. On Linux `ferramentas/faz_cartao.sh`
   does everything but the ROMs.
4. **Indexes.** Without them the browser shows 8.3 names (`JETSETW~1.TAP`) and the machine menu only opens with
   keys 1 to 4. `python3 ferramentas/cartao.py /path/to/card --fazer`, with the card in the PC, writes a
   `_NAV/*.IDX` with the long names in every folder. Run it again when you add games.
5. **Power** from a 2 A charger. The pin 87 button (or **Home**) is NMI (the browser); **Ctrl+Alt+Shift** = RESET+NMI (back to TC2048), for when a game breaks NMI; Ctrl+Alt+AltGr = normal reset; the pin 88 button picks, on the LEDs,
   what NMI does (RESET, `.go128`, `.go2068`, turbo…). It always boots as a TC2048; the browser offers the
   last machine used.

A black-and-white browser means Bob Fossil's `NMI.SYS` or the `cartao/` folder is missing.

## Using it

- **Speed:** **F10** up (3.5 → 7 → 14 → 27 MHz), **F9** down. Always 3.5 MHz at power-up. At 27 MHz, with the
  DivMMC mapped (esxDOS, browser, loading), it drops to 14; around every card access it runs at 3.5, to keep
  the card safe.
- **TZX:** from BASIC, ENTER on a `.TZX` in the browser plays the tape at the machine's speed and types
  `LOAD ""` by itself (on the 128K it resets and picks the Tape Loader); F10 speeds the load up. **F3** pauses
  at the end of the block being played, **F4** stops now; press again to resume. Top left, a square (green
  playing, yellow paused, red stopped) and one rectangle per block show for 3 s at each block and stay while
  paused. The General Sound's Z80 plays the tape: no GS music while it plays, and the GS is restored at the
  end. Blocks 15, 18 and 19 are not supported.
- **ZX 128K** boots into the Sinclair menu; a TAP chosen in the browser resets and the Tape Loader loads it.
  For Pentagon 128 demos and games use **Pentagon 128**, not 1024 (on the 1024 bits 5-7 of 7FFD select banks,
  and a 128 demo that writes them jumps to another part of memory).

## Credits

- **SCLD:** the Load ZX Museum model (Álvaro Lopes, Paulo Cortesão, CC BY-SA 4.0), repaired and completed by
  me for the [replacement CPLD](https://github.com/zambujal/CPLD-XC95288XL-replacement-for-scld-timex).
- **Z80:** T80 (Daniel Wallner, Sorgelig), [fixed by me in 2026](https://github.com/zambujal/T80-Q-fix).
- **Mine** (GPL v3): the core, video, HDMI, sound, card bridge, boot program, browser and card programs,
  `cartao.py`. Written with AI assistance.
- **Others** (`LICENCAS.md`): YM2149 (MikeJ), General Sound, SID, sysctrl, mcu_spi (MiSTer / MiSTeryNano),
  DivTIESUS and ULAplus (ZX-UNO), PT3 player (S. V. Bulba), HDMI (hdl-util / NanoMig).
- **Not included:** ROMs (Timex, Sinclair, Amstrad), esxDOS, Bob Fossil's plugins, BL616 firmware.

Links: [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) ·
[Gowin EDA](https://www.gowinsemi.com/en/support/download_eda/) ·
[openFPGALoader](https://github.com/trabucayre/openFPGALoader) · [esxDOS](https://www.esxdos.org) ·
[Bob Fossil](http://www.thefossilrecord.co.uk) · [FPGA Companion](https://github.com/MiSTle-Dev/FPGA-Companion) ·
[gs-firmware](https://github.com/psbhlw/gs-firmware) · [DivTIESUS](https://github.com/mcleod-ideafix/divtiesus) ·
[sjasmplus](https://github.com/z00m128/sjasmplus) · ROMs: [worldofspectrum.org](https://worldofspectrum.org),
[timexsinclair.com](https://www.timexsinclair.com)
