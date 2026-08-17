@echo off
title Ebru AI - Sunucu Baslatici

REM ============================================================
REM  Uygulamayi indiren herkesin bu PC'yi kullanabilmesi icin
REM  gereken UC servisi birlikte baslatir:
REM    1) Stable Diffusion (A1111)  -> goruntuyu ureten GPU tarafi
REM    2) Flask                     -> prompt hazirlar, yonlendirir
REM    3) Tunel                     -> internetten erisilebilir adres
REM
REM  Ucu de acikken telefonlar nerede olursa olsun uretim yapabilir.
REM  Bu pencereleri kapatirsan uretim durur.
REM
REM  NOT: Bu dosya sadece ASCII karakter icerir ve klasor yollarini
REM  kendi konumundan turetir. Klasor adindaki Turkce harfler CMD'nin
REM  kod sayfasinda bozuldugu icin yol yazmak sorun cikariyordu.
REM ============================================================

REM Bazi gelistirme ortamlari bu degiskeni set ediyor; set oldugunda
REM cmd, bulundugu klasordeki .bat dosyalarini calistiramiyor ve
REM "'webui.bat' is not recognized" hatasi aliniyor. Temizliyoruz.
set "NoDefaultCurrentDirectoryInExePath="

REM ---------- AYARLAR ----------

REM Tunel secimi:
REM   tailscale  -> kalici ucretsiz adres; adresi "tailscale funnel
REM                 status" ile gorebilirsin. NOT: bu adres mobil
REM                 sebekelerde DNS'te cozulemiyor, o yuzden yanina
REM                 Cloudflare tuneli de aciliyor.
REM   sabit      -> alan adina bagli kalici Cloudflare tuneli
REM   cloudflare -> her acilista degisen gecici adres (test icin)
REM   ngrok      -> ngrok tuneli
REM   yok        -> tunel yok, yalnizca ayni Wi-Fi
set "TUNEL=tailscale"

REM TUNEL=sabit icin: "cloudflared tunnel create" ile olusturdugun ad
REM
REM DIKKAT: bu degiskenin adi TUNNEL_ ile BASLAMAMALI. cloudflared,
REM TUNNEL_ onekli ortam degiskenlerini komut satiri bayragi gibi
REM okuyor; "TUNNEL_NAME=ebru" ayarliyken hizli tunel (--url) bile
REM adlandirilmis tunel sanilip cert.pem isteniyor ve
REM "Error locating origin cert" hatasi aliniyor. Eskiden adi
REM TUNNEL_NAME'di ve tam bu soruna yol aciyordu.
set "CF_TUNEL_ADI=ebru"

REM TUNEL=ngrok icin sabit adres (ornek: ebru.ngrok-free.app)
set "NGROK_DOMAIN="

REM Yollar bu dosyanin bulundugu klasorden turetiliyor.
REM %%~fI ile ".." icermeyen tam yola cevriliyor; aksi halde
REM "start /d" dogru klasore gecemiyor ve webui.bat bulunamiyor.
for %%I in ("%~dp0.") do set "BACKEND_DIR=%%~fI"
for %%I in ("%~dp0..\stable-diffusion-webui") do set "A1111_DIR=%%~fI"

REM Site dosyalari bu depoda degil, Desktop altinda ayri bir klasorde.
REM app.py artik sabit yol tutmuyor, konumu buradan aliyor.
for %%I in ("%~dp0..\..\..\Ebru_Web") do set "EBRU_WEB_DIR=%%~fI"
if not exist "%EBRU_WEB_DIR%\templates" (
    echo UYARI: Web klasoru bulunamadi: %EBRU_WEB_DIR%
    echo Site sayfalari acilmayacak, uretim yine de calisir.
)

REM ---------- 1) STABLE DIFFUSION ----------
echo [1/3] Stable Diffusion baslatiliyor...
if not exist "%A1111_DIR%\webui-user.bat" (
    echo HATA: A1111 bulunamadi.
    echo Aranan yol: %A1111_DIR%
    pause
    exit /b 1
)
start "Ebru - Stable Diffusion" /d "%A1111_DIR%" cmd /k "%A1111_DIR%\webui-user.bat"

REM ---------- 2) FLASK ----------
echo [2/3] Flask sunucusu baslatiliyor...
if not exist "%BACKEND_DIR%\app.py" (
    echo HATA: app.py bulunamadi.
    echo Aranan yol: %BACKEND_DIR%
    pause
    exit /b 1
)
start "Ebru - Flask" /d "%BACKEND_DIR%" cmd /k venv\Scripts\python.exe app.py

REM ---------- 3) TUNEL ----------
if /i "%TUNEL%"=="yok" (
    echo [3/3] Tunel atlandi. Uygulama yalnizca ayni Wi-Fi uzerinden baglanabilir.
    goto son
)

if /i "%TUNEL%"=="tailscale" (
    echo [3/3] Tailscale Funnel kontrol ediliyor...
    set "TS=C:\Program Files\Tailscale\tailscale.exe"
    if not exist "C:\Program Files\Tailscale\tailscale.exe" (
        echo HATA: Tailscale kurulu degil.
        echo Kurulum: winget install --id Tailscale.Tailscale
        pause
        exit /b 1
    )
    REM Tailscale arayuz sureci kapaliysa funnel komutu "unexpected
    REM state: NoState" verip sessizce basarisiz oluyor. Bilgisayar
    REM yeniden basladiginda bu surec her zaman kendiliginden
    REM kalkmiyor, o yuzden once onu ayaga kaldiriyoruz.
    tasklist /fi "imagename eq tailscale-ipn.exe" 2>nul | find /i "tailscale-ipn.exe" >nul
    if errorlevel 1 (
        echo    Tailscale arayuz sureci baslatiliyor...
        start "" "C:\Program Files\Tailscale\tailscale-ipn.exe"
        timeout /t 6 /nobreak >nul
    )
    REM Funnel arka planda calisir; bilgisayar acildiginda kendiliginden
    REM devreye girer. Yine de her ihtimale karsi yeniden baglaniyoruz.
    "C:\Program Files\Tailscale\tailscale.exe" funnel --bg 5000
    goto ekcf
)

if /i "%TUNEL%"=="ngrok" (
    echo [3/3] ngrok tuneli baslatiliyor...
    where ngrok >nul 2>&1
    if errorlevel 1 (
        echo HATA: ngrok kurulu degil.
        echo Kurulum: winget install --id ngrok.ngrok
        pause
        exit /b 1
    )
    if "%NGROK_DOMAIN%"=="" (
        echo UYARI: NGROK_DOMAIN bos. Adres her acilista degisecek.
        start "Ebru - Tunel" cmd /k ngrok http 5000
    ) else (
        start "Ebru - Tunel" cmd /k ngrok http --domain=%NGROK_DOMAIN% 5000
    )
    goto son
)

REM cloudflared'i once PATH'te, bulunamazsa kurulum klasorunde ara.
REM Kurulumdan hemen sonra acilan pencereler PATH'i henuz gormeyebiliyor.
set "CF="
where cloudflared >nul 2>&1 && set "CF=cloudflared"
if not defined CF if exist "%ProgramFiles(x86)%\cloudflared\cloudflared.exe" set "CF=%ProgramFiles(x86)%\cloudflared\cloudflared.exe"
if not defined CF if exist "%ProgramFiles%\cloudflared\cloudflared.exe" set "CF=%ProgramFiles%\cloudflared\cloudflared.exe"

if not defined CF (
    echo HATA: cloudflared bulunamadi.
    echo Kurulum: winget install --id Cloudflare.cloudflared
    echo Kurduysan bu pencereyi kapatip tekrar dene.
    pause
    exit /b 1
)

if exist "%BACKEND_DIR%\tunel.log" del "%BACKEND_DIR%\tunel.log"

REM NOT: cloudflared'i PowerShell uzerinden calistirmak "--url"
REM bayraginin kaybolmasina ve "origin cert" hatasina yol aciyordu.
REM Bu yuzden dogrudan calistirilip cikti dosyaya yonlendiriliyor.

if /i "%TUNEL%"=="sabit" (
    echo [3/3] Kalici Cloudflare tuneli baslatiliyor: %CF_TUNEL_ADI%
    start "Ebru - Tunel" cmd /k ""%CF%" tunnel run --url http://127.0.0.1:5000 %CF_TUNEL_ADI% ^> "%BACKEND_DIR%\tunel.log" 2^>^&1"
    goto adres
)

echo [3/3] Gecici Cloudflare tuneli baslatiliyor...
echo UYARI: Bu adres her acilista degisir, dagitim icin uygun degil.
start "Ebru - Tunel" cmd /k ""%CF%" tunnel --url http://localhost:5000 ^> "%BACKEND_DIR%\tunel.log" 2^>^&1"
goto adres

REM ------------------------------------------------------------
REM  TUNEL=tailscale iken buraya gelinir.
REM
REM  Tailscale adresi tailnet icinden sorunsuz calisiyor ama mobil
REM  sebekede DNS onu cozemiyor: telefonun tarayicisi bile "server IP
REM  address could not be found" veriyor. Bu yuzden Tailscale'in yanina
REM  bir Cloudflare tuneli de aciliyor; ikisi de ayni porta (5000)
REM  bakiyor, cakismiyorlar.
REM ------------------------------------------------------------
:ekcf
echo.
echo  Tailscale adresini gormek icin: tailscale funnel status
echo  (tailnet icinden calisir, mobil sebekede DNS cozemiyor)
echo.
echo  Telefonlar icin ek Cloudflare tuneli baslatiliyor...

REM Tunel komutu ayri bir dosyada (tunel_baslat.bat). Buraya dogrudan
REM yazildiginda ic ice tirnak ve ">" kacislari bozulup "--url"
REM bayragi kayboluyor; o zaman cloudflared komutu adlandirilmis
REM tunel sanip cert.pem istiyor ve "Error locating origin cert"
REM hatasi veriyor. Ayri dosyada kacis gerekmiyor.
if not exist "%BACKEND_DIR%\tunel_baslat.bat" (
    echo UYARI: tunel_baslat.bat bulunamadi. Telefonlar baglanamaz.
    goto son
)

REM Tam yolla cagiriliyor: adiyla cagirmak
REM NoDefaultCurrentDirectoryInExePath set oldugunda calismiyor.
if exist "%BACKEND_DIR%\tunel.log" del "%BACKEND_DIR%\tunel.log"
start "Ebru - Tunel" "%BACKEND_DIR%\tunel_baslat.bat"

:adres
echo.
echo Tunel adresi bekleniyor...
set "TUNEL_ADRES="
for /l %%N in (1,1,20) do (
    if not defined TUNEL_ADRES (
        timeout /t 2 /nobreak >nul
        for /f "delims=" %%A in ('powershell -NoProfile -Command "(Select-String -Path '%BACKEND_DIR%\tunel.log' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches -ErrorAction SilentlyContinue).Matches.Value ^| Select-Object -Last 1"') do set "TUNEL_ADRES=%%A"
    )
)

if defined TUNEL_ADRES (
    echo.
    echo ****************************************************
    echo  TUNEL ADRESI: %TUNEL_ADRES%
    echo.
    echo  Bu adresi depodaki sunucu.json dosyasina yaz ve GitHub'a
    echo  it. Uygulamalar acilista oradan okuyor, APK derlemek
    echo  gerekmiyor. Acele varsa Ayarlar ekranina elle de girilebilir.
    echo ****************************************************
) else (
    echo Adres okunamadi. "%BACKEND_DIR%\tunel.log" dosyasina bak.
)

:son
echo.
echo ============================================================
echo  Uc pencere acildi. Sirasiyla sunlari bekle:
echo.
echo   - Stable Diffusion: "Running on local URL" yazisi (1-2 dk)
echo   - Flask           : "EBRU AI SUNUCUSU BASLADI" yazisi
echo   - Tunel           : https://... ile baslayan adres
echo.
echo  Tunel adresi ayrica su dosyaya yazilir:
echo    %BACKEND_DIR%\tunel.log
echo.
echo  Kontrol: http://127.0.0.1:5000/health
echo ============================================================
echo.
pause
