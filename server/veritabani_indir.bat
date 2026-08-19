@echo off
title Ebru - Veritabanini indir

REM ============================================================
REM  Sunucudaki kullanici veritabaninin TUTARLI bir kopyasini
REM  bu bilgisayara indirir.
REM
REM  Dosya suraya duser:  veritabani_yedek\ebru-<tarih>.db
REM  Acmak icin: DB Browser for SQLite (ucretsiz)
REM
REM  Neden dogrudan kopyalanmiyor: calisan bir SQLite dosyasini
REM  kopyalamak yazma anina denk gelirse yarim kayit veriyor.
REM  Betik sunucuda sqlite3'un backup API'siyle anlik goruntu
REM  aliyor, sonra onu indiriyor.
REM
REM  Bu ayni zamanda YEDEKTIR: sunucu kaybolursa hesaplar bu
REM  dosyada durur.
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
    echo Kurulum: winget install --id Git.Git
    echo.
    pause
    exit /b 1
)

"%BASH%" sunucu.sh veritabani

echo.
pause
