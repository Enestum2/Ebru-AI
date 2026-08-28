@echo off
title Ebru - Sunucu ayari yaz

REM ============================================================
REM  Sunucudaki gizli ayarlari yazar (/etc/ebru/ebru.env).
REM
REM  Degeri BU BETIK SORMUYOR: anahtar adini sunucu.sh'e verip
REM  degeri onun gizli okumasina birakiyor. Boylece deger ne CMD
REM  gecmisine ne de surec listesine dusuyor.
REM
REM  Ayar yazildiktan sonra servis kendiliginden yeniden basliyor.
REM
REM  Tuzak: klasor adindaki Turkce harf CMD kod sayfasinda dustugu
REM  icin mutlak yol yazilmiyor; once cd, sonra ciplak dosya adi.
REM ============================================================

set "NoDefaultCurrentDirectoryInExePath="
cd /d "%~dp0"

REM ---------- Git Bash ----------
REM Arama sirasi guncelle.bat ile ayni tutuldu ki iki betik farkli
REM kopyalari calistirmasin.
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

:MENU
cls
echo ==========================================================
echo    SUNUCU AYARI YAZ
echo ==========================================================
echo.
echo   Sik kullanilanlar:
echo.
echo     1  EBRU_ACCESS_ID          Cloudflare Access istemci kimligi
echo     2  EBRU_ACCESS_SECRET      Cloudflare Access gizli anahtari
echo     3  EBRU_REGISTER_TOKEN     Uretim iscisinin kayit anahtari
echo     4  EBRU_RESEND_API_KEY     E-posta gonderim anahtari
echo     5  EBRU_GOOGLE_CLIENT_ID   Google ile giris istemci kimligi
echo     6  EBRU_DAILY_LIMIT        Gunluk uretim hakki (sayi)
echo.
echo     7  Baska bir anahtar yaz
echo     0  Cikis
echo.
set "ANAHTAR="
set /p SECIM=  Secim: 

if "%SECIM%"=="0" exit /b 0
if "%SECIM%"=="1" set "ANAHTAR=EBRU_ACCESS_ID"
if "%SECIM%"=="2" set "ANAHTAR=EBRU_ACCESS_SECRET"
if "%SECIM%"=="3" set "ANAHTAR=EBRU_REGISTER_TOKEN"
if "%SECIM%"=="4" set "ANAHTAR=EBRU_RESEND_API_KEY"
if "%SECIM%"=="5" set "ANAHTAR=EBRU_GOOGLE_CLIENT_ID"
if "%SECIM%"=="6" set "ANAHTAR=EBRU_DAILY_LIMIT"
if "%SECIM%"=="7" goto OZEL_ANAHTAR
goto ANAHTAR_KONTROL

:OZEL_ANAHTAR
echo.
set /p ANAHTAR=  Anahtar adi: 

:ANAHTAR_KONTROL
if defined ANAHTAR goto ANAHTAR_TAMAM
echo.
echo Gecersiz secim.
echo.
pause
goto MENU

:ANAHTAR_TAMAM

echo.
echo ----------------------------------------------------------
echo   Anahtar: %ANAHTAR%
echo   Deger sorulacak. Yazarken ekranda GORUNMEZ, bu normal.
echo ----------------------------------------------------------
echo.

"%BASH%" sunucu.sh ayar %ANAHTAR%

if errorlevel 1 goto YAZILAMADI
echo.
echo Ayar yazildi ve servis yeniden baslatildi.
goto SONUC_BITTI

:YAZILAMADI
echo.
echo Ayar YAZILAMADI. Yukaridaki mesaja bak.

:SONUC_BITTI

echo.
echo Baska bir ayar yazmak icin bir tusa bas, kapatmak icin pencereyi kapat.
pause >nul
goto MENU
