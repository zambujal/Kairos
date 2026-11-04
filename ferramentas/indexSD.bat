@echo off
rem indexSD.bat - indices do navegador do Kairos (_NAV) no cartao onde este ficheiro esta'.
rem Por na raiz do cartao, ao lado do cartao.py (e do config.ini), e dar dois cliques.
setlocal
cd /d "%~dp0"
set PY=py -3
%PY% --version >nul 2>&1 || set PY=python
%PY% --version >nul 2>&1 || (echo Falta o Python 3: https://www.python.org ^(marcar "Add to PATH"^) & pause & exit /b 1)
echo.
echo  Cartao: %~dp0
echo.
echo  1 - so' as pastas que mudaram (ficheiros novos, apagados ou com outro nome)
echo  2 - refazer os indices de todas as pastas
echo  3 - pasta a pasta (pergunta s/n para cada uma)
echo  4 - apagar os indices todos e refazer tudo (cartao copiado de outro)
echo  5 - so' ver o que faria (nao escreve nada)
echo.
choice /c 12345 /n /m " Escolha [1-5]: "
if errorlevel 5 goto ver
if errorlevel 4 goto limpar
if errorlevel 3 goto perguntar
if errorlevel 2 goto todas
%PY% cartao.py "%~dp0." --novas --fazer
goto fim
:todas
%PY% cartao.py "%~dp0." --fazer
goto fim
:perguntar
%PY% cartao.py "%~dp0." --perguntar --fazer
goto fim
:limpar
%PY% cartao.py "%~dp0." --limpar --fazer && %PY% cartao.py "%~dp0." --fazer
goto fim
:ver
%PY% cartao.py "%~dp0."
:fim
echo.
pause
