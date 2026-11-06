# Simulação do core do Kairos

O core inteiro (o Z80 do Timex, a DivTIESUS com o esxDOS, a SDRAM, o General Sound / a FDD3000, os AY, o vídeo)
a correr no Verilator, com um cartão SD simulado. Serve para ver o que acontece lá dentro quando uma coisa falha
no Tang: o esxDOS e o navegador a sério, a ler o cartão, e os saltos do Z80 ciclo a ciclo.

É lenta: cerca de 200 vezes mais devagar que o Tang (1 s de Timex demora uns 3 minutos). Por isso guarda-se o
estado (`SAVE`) e continua-se dali (`LOAD=`).

## O que é preciso

- `ghdl` com `--synth` (testado com o 4.1), `verilator` 5 (testado com o 5.020), `g++`, `python3` com o PIL;
- para a imagem do cartão: `sfdisk`, `mkfs.fat` (dosfstools) e o mtools.

Em Ubuntu/Debian: `apt-get install ghdl verilator g++ python3-pil fdisk dosfstools mtools`.

## Construir

```
./faz.sh          # o core em Verilog (GHDL), os nomes para o banco (nomes.h) e o programa (obra/obj/sim_kairos)
./faz.sh tb       # só o banco de ensaio, depois de mudar o tb_kairos.cpp
```

- O `faz.sh` põe o sinal `carga` do core a 0 desde o início: no Tang o programa de arranque lê a ROM do Timex e o
  esxDOS do cartão; aqui elas já estão nas memórias (`home.hex` e `esx.hex`, na pasta onde se corre).
- `limpa_syn.py` arranja o Verilog do GHDL para o Verilator: um nome escapado mal feito (o porto `REG` do T80) e
  sinais com o mesmo nome que a saída de uma instância.
- `nomes.py` faz o `nomes.h`: o registo de cada sinal do core (`R_fdd_on`, `R_regff`...), da FDD (`F_`, `G_`) e o
  endereço e o M1 dos dois Z80 (`P_cpu_a`, `P_gs_a`...), para o banco os ler e mudar.

## Correr

Numa pasta de trabalho (fora do repositório):

```
# as ROMs (as tuas: nao vem com o Kairos)
python3 -c "import sys; d=open('TC2048.ROM','rb').read(); open('home.hex','w').write('\n'.join('%02x'%b for b in d))"
python3 -c "import sys; d=open('ESXMMC.BIN','rb').read(); open('esx.hex','w').write('\n'.join('%02x'%b for b in d))"
# o cartão: uma pasta com o que vai no cartão do Kairos (BIN, SYS, as ROMs em SYS/ROMS, os jogos...)
.../sim/faz_imagem.sh pasta_do_cartao cartao.img
# os eventos e a simulação (5000 ms)
printf "500 SCRS 500\n3990 SAVE arranque.st\n" > ev.txt
SDIMG=cartao.img EVENTOS=ev.txt .../sim/obra/obj/sim_kairos 5000 > log.txt
python3 .../sim/v16png.py ecra_t*.v16
```

Os eventos (`ms COMANDO argumento`) e as variáveis de ambiente estão no princípio do `tb_kairos.cpp`: teclas
(`KEYS .GO2068~`), NMI, reset, ecrãs, a memória, guardar o estado, a FDD3000.

### A FDD3000

`dsk_fdd.py` faz a memória da FDD (2 MB) a partir da ROM de arranque e de um .DSK, como o plugin DSK a deixa.
O evento `FDD fich` liga a FDD com esse disco e faz o reset do Timex (como o plugin); antes, `TIROM` põe a ROM
do Timex Interface que se quer (a da Stavi para o TC2048, a da TMX para o TC2068).

```
python3 .../sim/dsk_fdd.py FDD3BOOT.ROM MONEMU.DSK fdd_monemu.bin
printf "4000 TIROM fdd3stavi.rom\n4000 FDD fdd_monemu.bin\n4000 SCRS 250\n" > ev.txt
SDIMG=cartao.img EVENTOS=ev.txt LOAD=arranque.st TRACO=4000,9000 .../sim/obra/obj/sim_kairos 9000
```

`TRACO=ini,fim` escreve em `traco.txt` os saltos do Z80 do Timex (com o TI, a porta FF e a HSR do 2068);
`TRACOFDD` o mesmo para o Z80 da FDD.

### Mudar ficheiros no cartão a meio

Um estado guardado traz o esxDOS a meio, com pedaços da FAT na memória: copiar um ficheiro novo para a imagem com
o mtools (que lhe dá outros clusters) estraga-o. `poe_fich.py cartao.img /BIN/NAVHR.BIN NAVHR.BIN` escreve o
ficheiro novo nos clusters do antigo e muda só o tamanho (tem de caber neles).
