#!/bin/sh
# indexSD.sh - indices do navegador do Kairos (_NAV) no cartao onde este ficheiro esta' (Linux / macOS).
# Por na raiz do cartao, ao lado do cartao.py (e do config.ini):  sh indexSD.sh
cd "$(dirname "$0")" || exit 1
echo
echo " Cartao: $(pwd)"
echo
echo " 1 - so' as pastas que mudaram (ficheiros novos, apagados ou com outro nome)"
echo " 2 - refazer os indices de todas as pastas"
echo " 3 - pasta a pasta (pergunta s/n para cada uma)"
echo " 4 - apagar os indices todos e refazer tudo (cartao copiado de outro)"
echo " 5 - so' ver o que faria (nao escreve nada)"
printf " Escolha [1-5]: "; read r
case "$r" in
  2) python3 cartao.py . --fazer ;;
  3) python3 cartao.py . --perguntar --fazer ;;
  4) python3 cartao.py . --limpar --fazer && python3 cartao.py . --fazer ;;
  5) python3 cartao.py . ;;
  *) python3 cartao.py . --novas --fazer ;;
esac
