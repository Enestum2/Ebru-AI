@echo off
title Ebru - Oracle kurulum sihirbazi

REM ============================================================
REM  oracle_kurulum.sh sihirbazini Git Bash icinde baslatir.
REM  Bu dosyaya CIFT TIKLAMAK yeterli.
REM
REM  Neden ayri bir baslatici var:
REM
REM  1) Sihirbaz bir bash betigi; cmd.exe "bash" komutunu
REM     tanimiyor ("is not recognized"). Git Bash'in tam yolu
REM     gerekiyor, o da kurulumdan kuruluma degisiyor.
REM
REM  2) Bu klasorun adinda Turkce harf var ("proje kodlari").
REM     CMD kod sayfasinda o harf dusuyor ve elle yazilan mutlak
REM     yollar gecersiz oluyor; hata da sebebi gostermiyor.
REM     Cozum: yol yazmamak. "cd /d %~dp0" ile klasore gecip
REM     betigi CIPLAK ADIYLA calistiriyoruz.
REM
REM  3) NoDefaultCurrentDirectoryInExePath bu makinede set;
REM     temizlenmezse cmd bulundugu klasordeki dosyalari adiyla
REM     calistiramiyor.
REM ============================================================

set "NoDefaultCurrentDirectoryInExePath="
cd /d "%~dp0"

set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not defined BASH (
    echo.
    echo HATA: Git Bash bulunamadi.
    echo.
    echo Git kurulu degilse:  winget install --id Git.Git
    echo Kuruluysa bash.exe genelde surada olur:
    echo    C:\Program Files\Git\bin\bash.exe
    echo.
    pause
    exit /b 1
)

if not exist "oracle_kurulum.sh" (
    echo.
    echo HATA: oracle_kurulum.sh bu klasorde yok.
    echo Aranan klasor: %CD%
    echo.
    pause
    exit /b 1
)

echo Git Bash: %BASH%
echo Sihirbaz baslatiliyor...
echo.

REM Betik adi ciplak: yukaridaki 2. maddeye bak.
"%BASH%" oracle_kurulum.sh

echo.
echo Sihirbaz kapandi.
pause
