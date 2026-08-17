@echo off
title Ebru - Tunel

REM ============================================================
REM  Cloudflare hizli tuneli. sunucu_baslat.bat bunu ayri bir
REM  pencerede cagiriyor. Adres tunel.log dosyasina yazilir.
REM
REM  Bu dosya bilerek cok sade tutuldu. Denemelerde sunlar sorun
REM  cikardi ve hepsi burada asiliyor:
REM
REM  1) Komut dogrudan "start ... cmd /k "..."" icine yazildiginda
REM     ic ice tirnaklar bozuluyor, "--url" bayragi kayboluyor ve
REM     cloudflared komutu adlandirilmis tunel sanip cert.pem
REM     istiyor ("Error locating origin cert").
REM  2) Klasor adindaki Turkce harf CMD kod sayfasinda dusuyor
REM     ("proje kodlari" -> "proje kodlar"), o yuzden yonlendirmede
REM     mutlak yol KULLANILMIYOR; once cd yapip ciplak dosya adi
REM     yaziliyor.
REM  3) NoDefaultCurrentDirectoryInExePath set oldugunda cmd bu
REM     klasordeki dosyalari adiyla calistiramiyor.
REM  4) "localhost" Windows'ta IPv6'ya (::1) cozulebiliyor, Flask
REM     ise yalnizca IPv4 dinliyor; tunel 502 donuyor. Bu yuzden
REM     127.0.0.1 yaziliyor.
REM ============================================================

set "NoDefaultCurrentDirectoryInExePath="
cd /d "%~dp0"

REM ============================================================
REM  ASIL TUZAK BURASI: cloudflared, TUNNEL_ onekli ortam
REM  degiskenlerini komut satiri bayragi gibi okuyor.
REM  sunucu_baslat.bat "TUNNEL_NAME=ebru" ayarliyor (kalici
REM  Cloudflare tuneli secenegi icin). O degisken ortamda oldugunda
REM  cloudflared "--name ebru" verilmis sayiyor, adlandirilmis tunel
REM  moduna geciyor ve cert.pem istiyor:
REM    "Error locating origin cert" / "failed to create tunnel"
REM  --url versek bile oluyor. Bu yuzden hizli tunel calistirmadan
REM  once TUNNEL_ degiskenlerini temizliyoruz.
REM ============================================================
set "TUNNEL_NAME="
set "TUNNEL_ORIGIN_CERT="
set "TUNNEL_OUTPUT="
set "TUNNEL_ID="
set "TUNNEL_CONFIG="
set "TUNNEL_CRED_FILE="

echo Cloudflare tuneli baslatiliyor...
echo Adres bu klasordeki tunel.log dosyasina yazilacak.
echo.

cloudflared tunnel --url http://127.0.0.1:5000 > tunel.log 2>&1

REM cloudflared PATH'te yoksa yukaridaki satir hata verir; tam yolla
REM tekrar deniyoruz.
if errorlevel 9009 (
    echo cloudflared PATH'te yok, tam yol deneniyor...
    "%ProgramFiles(x86)%\cloudflared\cloudflared.exe" tunnel --url http://127.0.0.1:5000 > tunel.log 2>&1
)

echo.
echo Tunel kapandi. Sebebi icin tunel.log dosyasina bak.
pause
