#!/bin/sh
# indexSD.sh - indices do navegador do Kairos (_NAV) no cartao onde este ficheiro esta' (Linux / macOS).
# Por na raiz do cartao, ao lado do cartao.py (e do config.ini):  sh indexSD.sh
cd "$(dirname "$0")" || exit 1
echo
echo " Cartao: $(pwd)"
echo
echo " 1 - refazer os indices de todas as pastas"
echo " 2 - pasta a pasta (pergunta s/n para cada uma)"
echo " 3 - apagar os indices todos e refazer tudo (cartao copiado de outro)"
echo " 4 - so' ver o que faria (nao escreve nada)"
printf " Escolha [1-4]: "; read r
case "$r" in
  2) python3 cartao.py . --perguntar --fazer ;;
  3) python3 cartao.py . --limpar --fazer && python3 cartao.py . --fazer ;;
  4) python3 cartao.py . ;;
  *) python3 cartao.py . --fazer ;;
esac
