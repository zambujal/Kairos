#!/bin/bash
# faz_imagem.sh: uma imagem de cartao SD (MBR, uma particao FAT32 a partir de 1 MiB) com o conteudo de uma pasta,
# para a simulacao (SDIMG). A pasta e' um cartao do Kairos (o esxDOS, o navegador, as ROMs, os jogos...).
#   ./faz_imagem.sh pasta_do_cartao cartao.img [MB]        (128 MB por omissao)
# Precisa de: sfdisk, mkfs.fat (dosfstools), mtools.
set -e
PASTA="$1"; IMG="$2"; MB="${3:-128}"
[ -d "$PASTA" ] && [ -n "$IMG" ] || { echo "uso: $0 pasta imagem [MB]"; exit 1; }
rm -f "$IMG"
truncate -s "${MB}M" "$IMG"
echo "2048,,c" | sfdisk -q "$IMG"
mkfs.fat -F 32 -s 2 -n KAIROS --offset 2048 "$IMG" $(( (MB * 1024) - 1024 )) > /dev/null
export MTOOLS_SKIP_CHECK=1
( cd "$PASTA" && for f in *; do mcopy -s -Q -i "$IMG@@1M" "$f" ::/; done )
mdir -i "$IMG@@1M" ::/
