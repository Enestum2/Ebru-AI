@echo off
title Ebru - Sunucuyu guncelle

REM ============================================================
REM  Bu bilgisayardaki kodu Oracle'daki sunucuya gonderir ve
REM  siteyi yeniden baslatir. Birkac saniye surer.
REM
REM  Gonderilenler : server/ ve web/ (sablonlar, statik dosyalar)
REM  Gonderilmeyen : 58 MB APK, veritabani, gizli anahtarlar
REM                  (sunucudakiler oldugu gibi korunuyor)
REM
REM  Yeniden baslatmadan once veritabaninin sunucuda yedegi
REM  aliniyor: sema gocleri acilista kendiliginden calisiyor.
REM
REM  Tuzaklar tunel_baslat.bat icinde ayrintili yazili; ozeti:
REM  klasor adindaki Turkce harf CMD kod sayfasinda dustugu icin
REM  mutlak yol yazilmiyor, once cd sonra ciplak dosya adi.
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

"%BASH%" sunucu.sh guncelle

echo.
pause
