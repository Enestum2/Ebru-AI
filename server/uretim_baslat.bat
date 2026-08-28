@echo off
title Ebru - Uretim (ACIK)

REM ============================================================
REM  URETIM AC/KAPAT
REM
REM  Site (ebruai.com) her zaman acik sunucuda calisiyor ve bu
REM  betikten bagimsiz ayakta. Bu pencere yalnizca GORUNTU
REM  URETIMINI aciyor:
REM
REM     acikken  -> site "uretime hazir" der, istekler bu
REM                 bilgisayardaki GPU'ya gider
REM     kapaliyken -> site ayakta kalir, "uretim su anda kapali" der
REM
REM  Kapatmak icin bu pencereyi kapatman yeterli.
REM
REM  NOT: sunucu_baslat.bat ile karistirma. O betik Flask'i ve
REM  kalici tuneli bu bilgisayarda ayaga kaldiriyordu; site
REM  sunucuya tasindiktan sonra artik gerekmiyor.
REM
REM  Tuzaklar (tunel_baslat.bat icinde ayrintili):
REM   - NoDefaultCurrentDirectoryInExePath set oldugunda cmd bu
REM     klasordeki dosyalari adiyla calistiramiyor.
REM   - Klasor adindaki Turkce harf CMD kod sayfasinda dusuyor;
REM     bu yuzden once cd, sonra ciplak dosya adi kullaniliyor.
REM   - TUNNEL_ onekli ortam degiskenleri cloudflared'i bozuyor;
REM     temizligi uretim_isci.py kendi yapiyor.
REM ============================================================

set "NoDefaultCurrentDirectoryInExePath="
cd /d "%~dp0"

for %%I in ("%~dp0..\stable-diffusion-webui") do set "A1111_DIR=%%~fI"

REM ---------- A1111 ----------
REM Zaten aciksa ikinci kopya acilmiyor: ikinci surec 7860'i alamaz
REM ama ~3 GB bellek tutar ve 6 GB'lik kartta uretimi dusurur.
call :PORT_DOLU_MU 7860
if "%PORT_DURUM%"=="dolu" (
    echo A1111 zaten calisiyor.
) else (
    if not exist "%A1111_DIR%\webui-user.bat" (
        echo HATA: A1111 bulunamadi.
        echo Aranan yol: %A1111_DIR%
        pause
        exit /b 1
    )
    echo A1111 baslatiliyor... ilk acilis birkac dakika surebilir.
    start "Ebru - Stable Diffusion" /d "%A1111_DIR%" cmd /k "%A1111_DIR%\webui-user.bat"
)

REM ---------- Ayarlar ----------
REM Kayit anahtari sunucudakiyle ayni olmali. Anahtar depoya
REM girmemeli; bu yuzden ayri bir dosyada tutuluyor ve o dosya
REM .gitignore icine ADIYLA eklendi (uretim_ayarlar.bat).
if exist "uretim_ayarlar.bat" (
    call "uretim_ayarlar.bat"
) else (
    echo.
    echo UYARI: uretim_ayarlar.bat yok.
    echo Icine su satiri yazip kaydet:
    echo    set "EBRU_REGISTER_TOKEN=sunucudaki-anahtar"
    echo.
)

REM ---------- Isimli tunel ----------
REM Gecici (trycloudflare) tunel her acilista yeni adres aliyordu ve
REM koptugunda uretim dusuk kaliyordu. Isimli tunelde adres sabit:
REM kopan baglanti ayni gpu.ebruai.com adresine geri geliyor.
REM
REM Ucu birden tanimli olmali; biri eksikse isci eski gecici tunel
REM yoluna duser (yedek olarak bilerek birakildi).
if not defined EBRU_TUNEL_ADI    set "EBRU_TUNEL_ADI=ebru-gpu"
if not defined EBRU_TUNEL_CONFIG set "EBRU_TUNEL_CONFIG=%USERPROFILE%\.cloudflared\ebru-gpu.yml"
if not defined EBRU_GPU_URL      set "EBRU_GPU_URL=https://gpu.ebruai.com"

if not exist "%EBRU_TUNEL_CONFIG%" (
    echo.
    echo UYARI: Tunel yapilandirmasi yok: %EBRU_TUNEL_CONFIG%
    echo Gecici tunele dusulecek.
    echo.
    set "EBRU_TUNEL_ADI="
)

REM ---------- Isci ----------
if not exist "venv\Scripts\python.exe" (
    echo HATA: venv bulunamadi: %CD%\venv
    pause
    exit /b 1
)

venv\Scripts\python.exe uretim_isci.py

echo.
echo Uretim kapandi. Site calismaya devam ediyor.
pause
exit /b 0

:PORT_DOLU_MU
set "PORT_DURUM=bos"
netstat -ano | findstr /c:"LISTENING" | findstr /r /c:":%~1 " >nul 2>&1
if not errorlevel 1 set "PORT_DURUM=dolu"
exit /b 0
