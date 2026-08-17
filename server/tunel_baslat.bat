@echo off
title Ebru - Tunel

REM ============================================================
REM  Ebru AI tuneli. sunucu_baslat.bat bunu ayri pencerede cagirir.
REM
REM  KALICI TUNEL kullaniliyor: adres her zaman ebruai.com.
REM  Baglanti kopsa da cloudflared yeniden baglandiginda ayni
REM  adrese donuyor, sunucu.json'u guncellemek gerekmiyor.
REM  Yapilandirma: %USERPROFILE%\.cloudflared\config.yml
REM
REM  Bu dosya sade tutuldu. Denemelerde su tuzaklar cikti, hepsi
REM  burada asiliyor:
REM
REM  1) cloudflared, TUNNEL_ onekli ORTAM DEGISKENLERINI komut
REM     satiri bayragi gibi okuyor. sunucu_baslat.bat eskiden
REM     "TUNNEL_NAME=ebru" ayarliyordu; o yuzden hizli tunel bile
REM     adlandirilmis tunel sanilip cert.pem isteniyor ve
REM     "Error locating origin cert" hatasi aliniyordu. Asil sebep
REM     buydu; degisken adi CF_TUNEL_ADI'ya cevrildi, burada da
REM     temizlik yapiliyor.
REM  2) Komut "start ... cmd /k "..."" icine gomuldugunde ic ice
REM     tirnaklar bozuluyor ve bayraklar kayboluyor. O yuzden
REM     komut ayri dosyada.
REM  3) Klasor adindaki Turkce harf CMD kod sayfasinda dusuyor
REM     ("proje kodlari" -> "proje kodlar"), o yuzden yonlendirmede
REM     mutlak yol kullanilmiyor: once cd, sonra ciplak dosya adi.
REM  4) NoDefaultCurrentDirectoryInExePath set oldugunda cmd bu
REM     klasordeki dosyalari adiyla calistiramiyor.
REM  5) Origin adresi 127.0.0.1, "localhost" DEGIL: Windows'ta
REM     localhost IPv6'ya (::1) cozulebiliyor, Flask yalnizca IPv4
REM     dinledigi icin tunel 502 donuyor. (config.yml icinde.)
REM ============================================================

set "NoDefaultCurrentDirectoryInExePath="
cd /d "%~dp0"

set "TUNNEL_NAME="
set "TUNNEL_ORIGIN_CERT="
set "TUNNEL_OUTPUT="
set "TUNNEL_ID="
set "TUNNEL_CONFIG="
set "TUNNEL_CRED_FILE="

REM Tunel Windows servisi olarak kuruluysa ve calisiyorsa burada
REM ikinci bir kopya acmanin anlami yok: ayni tunele iki baglayici
REM baglanir. Servis zaten acilista kendiliginden kalkiyor.
sc query Cloudflared 2>nul | find /i "RUNNING" >nul
if not errorlevel 1 (
    echo Tunel Windows servisi olarak calisiyor, ayrica baslatilmiyor.
    echo Adres: https://ebruai.com
    echo.
    echo Durumu gormek icin: cloudflared tunnel info ebru
    echo.
    timeout /t 5 /nobreak >nul
    exit /b 0
)

REM Kalici tunel icin gerekli iki dosya var mi?
if not exist "%USERPROFILE%\.cloudflared\config.yml" goto hizli
if not exist "%USERPROFILE%\.cloudflared\cert.pem"   goto hizli

echo Kalici tunel baslatiliyor: https://ebruai.com
echo Gunluk: bu klasordeki tunel.log
echo.
cloudflared tunnel run ebru > tunel.log 2>&1
goto kapandi

REM ------------------------------------------------------------
REM Kalici tunel yapilandirmasi yoksa gecici adresle devam et.
REM O durumda adres her acilista degisir ve depodaki sunucu.json
REM elle guncellenmelidir.
REM ------------------------------------------------------------
:hizli
echo UYARI: kalici tunel yapilandirmasi bulunamadi.
echo Gecici (trycloudflare) adres kullanilacak; adres her acilista
echo degisir ve sunucu.json elle guncellenmelidir.
echo.
cloudflared tunnel --url http://127.0.0.1:5000 > tunel.log 2>&1

:kapandi
echo.
echo Tunel kapandi. Sebebi icin tunel.log dosyasina bak.
pause
