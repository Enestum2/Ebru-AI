# -*- coding: utf-8 -*-
"""
Ebru AI uretim iscisi.

MIMARI (Durum B)
----------------
Site (Flask + sayfalar) her zaman acik bir sunucuda calisir; goruntuyu
ureten A1111 ve GPU bu bilgisayarda kalir. Bu betik ikisini birbirine
baglayan tek parcadir:

    A1111 (127.0.0.1:7860)
        |
        +-- gecici Cloudflare tuneli --> https://xxxx.trycloudflare.com
                                              |
                                              v
                              site: POST /register-backend

Betik calistigi surece uretim ACIK, kapattiginda KAPALI olur. Site her
iki durumda da ayakta kalir; sadece "uretim su anda kapali" der.
Aradigimiz ac/kapat dugmesi bu betigin kendisidir.

NEDEN GECICI (trycloudflare) TUNEL
----------------------------------
Gecici tunel daha once "adres her kopmada degisiyor" diye elenmisti. O
gerekce sitenin adresi icin geciliydi: kullanicinin yazdigi adres sabit
olmali. Burada adres kullaniciya hic gorunmuyor, degistiginde bu betik
yenisini siteye bildiriyor. Yani ayni ozellik artik sorun degil.

Kalici bir alt alan adi (ornegin gpu.ebruai.com) da kullanilabilirdi
ama o zaman A1111'in API'si sabit ve tahmin edilebilir bir adreste
internete acik kalirdi. Donen adres en azindan bunu zorlastiriyor.

AYARLAR (ortam degiskenleri)
----------------------------
    EBRU_SITE_URL        Sitenin adresi.  Varsayilan: https://ebruai.com
    EBRU_REGISTER_TOKEN  Kayit anahtari.  ZORUNLU, sunucudakiyle ayni.
    EBRU_SD_URL          A1111 adresi.    Varsayilan: http://127.0.0.1:7860
"""

import os
import re
import sys
import time
import signal
import threading
import subprocess

import requests


SITE_URL = (os.environ.get("EBRU_SITE_URL") or "https://ebruai.com").rstrip("/")
TOKEN = os.environ.get("EBRU_REGISTER_TOKEN") or ""
SD_URL = (os.environ.get("EBRU_SD_URL") or "http://127.0.0.1:7860").rstrip("/")

# A1111'in acilmasi 6 GB'lik kartta dakikalar surebiliyor; betik hemen
# pes etmesin diye bekleme sinirlari genis tutuldu.
A1111_BEKLEME = 600      # saniye: A1111 ayaga kalkana kadar beklenecek sure
TUNEL_BEKLEME = 60       # saniye: tunel adresi gorunene kadar
NABIZ_ARALIGI = 60       # saniye: siteye "hala buradayim" bildirimi
YOKLAMA_ZAMAN_ASIMI = 10

# Yeni tunel adresi basildiktan sonra ilk sorguya kadar beklenecek sure.
# Gerekcesi dongu() icinde ayrintili yazili: erken sorgu, cozumleyiciye
# "boyle bir ad yok" cevabini onbellekletip tuneli dakikalarca
# erisilemez kiliyor.
ILK_SORGU_BEKLEMESI = 25

# trycloudflare adresi cloudflared'in stderr ciktisinda gecer.
ADRES_KALIBI = re.compile(r"https://[-a-z0-9]+\.trycloudflare\.com")

# Isimli tunelde adres bastan belli, ciktidan okunmuyor. Bunun yerine
# cloudflared'in "baglandim" satiri bekleniyor.
KAYIT_KALIBI = re.compile(r"Registered tunnel connection")

# ISIMLI TUNEL
# ------------
# Gecici tunel her acilista yeni adres aliyordu. Adres kullaniciya
# gorunmedigi icin bu sorun degil sanilmisti, ama tunel KOPTUGUNDA
# suren uretim oluyor ve site kaynagi "kapali" isaretliyor; yeni adres
# kaydedilene kadar uretim dusuk kaliyor. Isimli tunelde adres sabit,
# kopan baglanti ayni adrese geri geliyor.
#
# Ucu de tanimliysa isimli tunel kullaniliyor; degilse eski gecici
# tunel yolu isliyor (yedek olarak bilerek birakildi).
TUNEL_ADI = (os.environ.get("EBRU_TUNEL_ADI") or "").strip()
TUNEL_CONFIG = (os.environ.get("EBRU_TUNEL_CONFIG") or "").strip()
SABIT_ADRES = (os.environ.get("EBRU_GPU_URL") or "").strip().rstrip("/")
ISIMLI_TUNEL = bool(TUNEL_ADI and TUNEL_CONFIG and SABIT_ADRES)

# cloudflared, hicbir sey soylenmezse %USERPROFILE%\.cloudflared\config.yml
# dosyasini KENDILIGINDEN okuyor. O dosya kalici ebruai.com tunelini
# tarif ediyor ve icinde "son care: http_status:404" kurali var. Sonuc:
# "tunnel --url" ile acilan gecici tunel bile kalici tunelin kimligiyle
# baglaniyor, gecici adres ingress kurallarina uymadigi icin Cloudflare
# 404 donuyor ve tunel calismiyor saniliyor. Olcumle bulundu; cozum
# cloudflared'i bos bir yapilandirmayla calistirmak.
BOS_CONFIG = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "uretim_tunel_config.yml",
)

_durdur = threading.Event()


BOS_CONFIG_ICERIK = """# Bu dosya uretim_isci.py tarafindan olusturuldu.
# Bilerek bos birakildi: gecici tunel, kalici ebruai.com tunelinin
# ayarlarini almasin diye. Ayrintili gerekce betigin basindaki
# BOS_CONFIG aciklamasinda.
"""


def bos_config_hazirla():
    """Gecici tunel icin bos bir cloudflared yapilandirmasi olusturur."""
    if not os.path.exists(BOS_CONFIG):
        with open(BOS_CONFIG, "w", encoding="utf-8") as dosya:
            dosya.write(BOS_CONFIG_ICERIK)
    return BOS_CONFIG


# ---------------------------------------------------------------
# Yardimcilar
# ---------------------------------------------------------------
def yaz(mesaj):
    """Zaman damgali, ASCII konsol ciktisi.

    Emoji kullanilmiyor: Windows konsolunun kod sayfasi (cp857/cp1254)
    bunlari basamayip UnicodeEncodeError ile betigi dusurebiliyor.
    """
    print("[%s] %s" % (time.strftime("%H:%M:%S"), mesaj), flush=True)


def cloudflared_bul():
    """cloudflared'i once PATH'te, sonra kurulum klasorlerinde arar.

    Arama sirasi sunucu_baslat.bat ile ayni tutuldu ki iki betik farkli
    kopyalari calistirmasin.
    """
    from shutil import which

    yol = which("cloudflared")
    if yol:
        return yol

    adaylar = (
        os.path.join(
            os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
            "cloudflared", "cloudflared.exe",
        ),
        os.path.join(
            os.environ.get("ProgramFiles", r"C:\Program Files"),
            "cloudflared", "cloudflared.exe",
        ),
    )
    for aday in adaylar:
        if os.path.exists(aday):
            return aday
    return None


def temiz_ortam():
    """TUNNEL_ onekli degiskenleri temizlenmis bir ortam kopyasi dondurur.

    cloudflared bu degiskenleri komut satiri bayragi gibi okuyor. Ortamda
    TUNNEL_NAME varsa "cloudflared tunnel --url ..." bile adlandirilmis
    tunel sanilip cert.pem istiyor ve "Error locating origin cert" ile
    patliyor. Bu tuzak daha once saatler yakti; burada da asiliyor.
    """
    ortam = os.environ.copy()
    for ad in list(ortam):
        if ad.upper().startswith("TUNNEL_"):
            del ortam[ad]
    return ortam


def a1111_ayakta_mi(url=None):
    """A1111'in API'si cevap veriyor mu?"""
    try:
        cevap = requests.get(
            "%s/sdapi/v1/progress" % (url or SD_URL),
            timeout=YOKLAMA_ZAMAN_ASIMI,
        )
        # Tunel dustugunde saglayici JSON degil HTML hata sayfasi dondurur.
        return (
            cevap.status_code == 200
            and "json" in cevap.headers.get("Content-Type", "")
        )
    except Exception:
        return False


# ---------------------------------------------------------------
# Tunel
# ---------------------------------------------------------------
class Tunel(object):
    """cloudflared surecini yonetir ve adresini yakalar."""

    def __init__(self, cf_yolu):
        self.cf_yolu = cf_yolu
        self.surec = None
        self.adres = None
        self._okuyucu = None

    def baslat(self):
        self.adres = None

        if ISIMLI_TUNEL:
            # --config MUTLAKA veriliyor: cloudflared hicbir sey
            # soylenmezse ~/.cloudflared/config.yml dosyasini okuyor ve
            # komut satirinda baska tunel adi verilse bile oradaki
            # tuneli kullaniyor. DNS kaydi ilk kurulumda tam bu yuzden
            # yanlis tunele baglanmisti.
            komut = [
                self.cf_yolu,
                "--config", TUNEL_CONFIG,
                "tunnel", "run", TUNEL_ADI,
            ]
        else:
            komut = [
                self.cf_yolu, "tunnel",
                # Kalici tunelin config.yml'i sizmasin diye (yukaridaki
                # BOS_CONFIG aciklamasina bak).
                "--config", bos_config_hazirla(),
                "--url", SD_URL,
            ]

        self.surec = subprocess.Popen(
            komut,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=temiz_ortam(),
            universal_newlines=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )

        # Cikti ayri bir is parcaciginda okunuyor: cloudflared surekli
        # log basiyor ve boru dolarsa surec kilitleniyor.
        self._okuyucu = threading.Thread(
            target=self._ciktiyi_oku,
            name="tunel-cikti",
            daemon=True,
        )
        self._okuyucu.start()

        baslangic = time.time()
        while time.time() - baslangic < TUNEL_BEKLEME:
            if self.adres:
                return self.adres
            if self.surec.poll() is not None:
                yaz("HATA: cloudflared beklenmedik sekilde kapandi.")
                return None
            time.sleep(0.5)

        yaz("HATA: %d saniyede tunel adresi alinamadi." % TUNEL_BEKLEME)
        return None

    def _ciktiyi_oku(self):
        try:
            for satir in self.surec.stdout:
                if self.adres is not None:
                    continue
                if ISIMLI_TUNEL:
                    # Adres zaten belli; beklenen sey baglantinin
                    # kurulmasi.
                    if KAYIT_KALIBI.search(satir):
                        self.adres = SABIT_ADRES
                else:
                    bulunan = ADRES_KALIBI.search(satir)
                    if bulunan:
                        self.adres = bulunan.group(0)
        except Exception:
            pass

    def yasiyor_mu(self):
        return self.surec is not None and self.surec.poll() is None

    def kapat(self):
        if self.surec and self.surec.poll() is None:
            try:
                self.surec.terminate()
                self.surec.wait(timeout=10)
            except Exception:
                try:
                    self.surec.kill()
                except Exception:
                    pass


def tunel_dogrula(adres, sure=45):
    """Tunel uzerinden A1111'e ulasilabiliyor mu (en fazla `sure` saniye)."""
    baslangic = time.time()
    while time.time() - baslangic < sure:
        if _durdur.is_set():
            return False
        if a1111_ayakta_mi(adres):
            return True
        if _durdur.wait(3):
            return False
    return False


# ---------------------------------------------------------------
# Site ile haberlesme
# ---------------------------------------------------------------
def siteye_kaydol(adres):
    try:
        cevap = requests.post(
            "%s/register-backend" % SITE_URL,
            json={"token": TOKEN, "url": adres},
            timeout=30,
        )
    except Exception as hata:
        yaz("Siteye ulasilamadi: %s" % hata)
        return False

    if cevap.status_code == 403:
        yaz("HATA: kayit anahtari reddedildi. Sunucudaki")
        yaz("      EBRU_REGISTER_TOKEN ile buradaki ayni mi?")
        return False

    if cevap.status_code != 200:
        yaz("Site kaydi reddetti (%d): %s" % (cevap.status_code, cevap.text[:200]))
        return False

    try:
        erisilebilir = cevap.json().get("reachable")
    except Exception:
        erisilebilir = None

    if erisilebilir is False:
        # Kayit gecti ama site tunelden A1111'e ulasamiyor. Genelde tunel
        # daha yeni acildigi icin birkac saniye sonra duzeliyor.
        yaz("Kayit alindi ama site A1111'e henuz ulasamiyor.")
        return False

    return True


def kaydi_sil():
    try:
        requests.post(
            "%s/unregister-backend" % SITE_URL,
            json={"token": TOKEN},
            timeout=15,
        )
        yaz("Site bilgilendirildi: uretim kapandi.")
    except Exception:
        # Onemli degil: site 30 saniye icinde tunelin dustugunu zaten
        # kendisi fark ediyor. Bu yalnizca aninda guncelleme icin.
        yaz("Site bilgilendirilemedi; kendisi en gec 30 sn icinde anlar.")


# ---------------------------------------------------------------
# Ana akis
# ---------------------------------------------------------------
def a1111_bekle():
    yaz("A1111 bekleniyor: %s" % SD_URL)
    baslangic = time.time()
    uyarildi = False

    while time.time() - baslangic < A1111_BEKLEME:
        if _durdur.is_set():
            return False
        if a1111_ayakta_mi():
            yaz("A1111 hazir.")
            return True
        if not uyarildi and time.time() - baslangic > 15:
            yaz("A1111 henuz cevap vermiyor. Acik degilse")
            yaz("stable-diffusion-webui\\webui-user.bat ile baslat.")
            uyarildi = True
        time.sleep(3)

    yaz("HATA: A1111 %d saniyede acilmadi." % A1111_BEKLEME)
    return False


def dongu(cf_yolu):
    tunel = None
    kayitli = False
    basarisiz = 0

    try:
        while not _durdur.is_set():
            # --- tunel yoksa ya da olduyse yeniden kur ---
            if tunel is None or not tunel.yasiyor_mu():
                if tunel is not None:
                    yaz("Tunel dustu, yeniden kuruluyor.")
                    tunel.kapat()
                    kayitli = False

                tunel = Tunel(cf_yolu)
                adres = tunel.baslat()
                if not adres:
                    tunel.kapat()
                    tunel = None
                    if _durdur.wait(10):
                        break
                    continue

                yaz("Tunel acildi: %s" % adres)

                # ADRESI HEMEN SORGULAMA.
                #
                # Olcumle bulundu: cloudflared adresi bastigi anda DNS
                # kaydi heryerde gorunur olmuyor. O anda yapilan ilk
                # sorgu "boyle bir ad yok" cevabi aliyor ve cozumleyici
                # bu OLUMSUZ cevabi onbellege koyuyor. Sonrasinda tunel
                # calissa bile ad dakikalarca cozulemiyor; yani erken
                # sorgu sorunu olusturan seyin ta kendisi.
                #
                # 25 saniye beklenip yapilan ilk sorgu ayni makinede
                # sorunsuz cozuldu ve tunel HTTP 200 dondu. Bekleme
                # yalnizca tunel ilk kuruldugunda, bir kez odeniyor;
                # A1111'in acilisi zaten dakikalar suruyor.
                # Isimli tunelde bu bekleme gereksiz: gpu.ebruai.com
                # kaydi kalici, cozumleyicide zaten var. Bekleme yalnizca
                # HER ACILISTA YENI ad ureten gecici tunel icin gerekli.
                if not ISIMLI_TUNEL:
                    if _durdur.wait(ILK_SORGU_BEKLEMESI):
                        break

                # Tunel calisiyor mu diye bir de kendimiz bakalim.
                #
                # Basarisizlik tuneli YIKMIYOR: onemli olan SITENIN
                # adrese ulasabilmesi, bu makinenin ulasip ulasamamasi
                # degil. Son sozu site veriyor; /register-backend
                # cevabinda "reachable" donuyor.
                if tunel_dogrula(adres):
                    yaz("Tunel dogrulandi.")
                else:
                    yaz("UYARI: tunel bu makineden dogrulanamadi.")
                    yaz("       Kayit yine de denenecek; karar sitenin.")

            # --- siteye bildir (ilk kayit ve nabiz) ---
            if siteye_kaydol(tunel.adres):
                if not kayitli:
                    yaz("URETIM ACIK. Site: %s" % SITE_URL)
                    yaz("Kapatmak icin bu pencereyi kapat ya da Ctrl+C.")
                kayitli = True
                basarisiz = 0
            else:
                kayitli = False
                basarisiz += 1
                # Tunel ayakta gorunuyor ama site ona ulasamiyorsa
                # beklemenin faydasi yok; birkac denemeden sonra
                # tuneli bastan kur.
                if basarisiz >= 3:
                    yaz("Site tunele 3 denemedir ulasamiyor, tunel yenileniyor.")
                    tunel.kapat()
                    tunel = None
                    basarisiz = 0
                    continue

            # Nabiz: site yeniden baslatilirsa kayit bellekten silinir,
            # bu tekrar bildirim onu kendiliginden geri getirir.
            if _durdur.wait(NABIZ_ARALIGI):
                break
    finally:
        yaz("Kapatiliyor...")
        if kayitli:
            kaydi_sil()
        if tunel is not None:
            tunel.kapat()


def main():
    print("")
    print("=" * 58)
    print("   EBRU AI - URETIM ISCISI")
    print("=" * 58)
    print("   Bu pencere acik oldugu surece uretim ACIK.")
    print("   Kapattiginda site ayakta kalir, uretim kapanir.")
    print("=" * 58)
    print("")

    if not TOKEN:
        yaz("HATA: EBRU_REGISTER_TOKEN ayarlanmamis.")
        yaz("      Sunucudaki anahtarin aynisi burada da olmali.")
        return 1

    cf_yolu = cloudflared_bul()
    if not cf_yolu:
        yaz("HATA: cloudflared bulunamadi.")
        yaz("      Kurulum: winget install --id Cloudflare.cloudflared")
        return 1

    yaz("cloudflared: %s" % cf_yolu)
    yaz("Site       : %s" % SITE_URL)

    if not a1111_bekle():
        return 1

    dongu(cf_yolu)
    return 0


def _sinyal(imza, cerceve):
    _durdur.set()


if __name__ == "__main__":
    signal.signal(signal.SIGINT, _sinyal)
    try:
        signal.signal(signal.SIGTERM, _sinyal)
    except Exception:
        pass

    try:
        sys.exit(main())
    except KeyboardInterrupt:
        _durdur.set()
        sys.exit(0)
