@echo off
title Ebru - Sunucu durumu

REM ============================================================
REM  Sunucunun ve sitenin durumunu gosterir: servisler ayakta mi,
REM  bellek/disk ne durumda, ebruai.com disaridan cevap veriyor mu.
REM  Hicbir sey degistirmez, yalnizca okur.
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

"%BASH%" sunucu.sh durum

echo.
pause
