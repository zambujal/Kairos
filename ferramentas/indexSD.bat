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
echo  1 - refazer os indices de todas as pastas
echo  2 - pasta a pasta (pergunta s/n para cada uma)
echo  3 - apagar os indices todos e refazer tudo (cartao copiado de outro)
echo  4 - so' ver o que faria (nao escreve nada)
echo.
choice /c 1234 /n /m " Escolha [1-4]: "
if errorlevel 4 goto ver
if errorlevel 3 goto limpar
if errorlevel 2 goto perguntar
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
