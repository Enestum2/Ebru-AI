import os
import re
import sys
import time
import random
import secrets
import subprocess
import threading
from collections import deque
from contextlib import contextmanager

from deep_translator import GoogleTranslator

# Windows konsolu varsayılan olarak cp1254 kullanıyor ve log'lardaki
# emojilerde UnicodeEncodeError fırlatıp isteği çökertebiliyor.
for _akis in (sys.stdout, sys.stderr):
    try:
        _akis.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# =====================================
# GEREKLİ PAKETLER
# =====================================

def ensure_package(package_name, import_name=None):
    """
    Paket kurulu değilse otomatik kurar.
    """
    import_name = import_name or package_name

    try:
        __import__(import_name)

    except ImportError:
        print(f"📦 {package_name} kuruluyor...")
        subprocess.check_call(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                package_name
            ]
        )


ensure_package("flask")
ensure_package("flask-cors", "flask_cors")
ensure_package("requests")
ensure_package("deep-translator", "deep_translator")

# =====================================
# IMPORTLAR
# =====================================

from flask import (
    Flask,
    jsonify,
    render_template,
    request,
    send_from_directory,
    url_for,
)
from flask_cors import CORS
import requests

import kullanicilar
import eposta as eposta_servisi
import google_giris
import renk_secici
# =====================================
# FLASK AYARLARI
# =====================================

# Web dosyaları (html/css/js) sunucu kodundan ayrı bir klasörde
# duruyor ki backend ile karışmasınlar.
#
# Koda makineye özel bir yol yazılmıyor: önce EBRU_WEB_DIR, sonra bilinen
# yerleşimler kendi konumumuza göre denenir. Böylece hem depo düzeninde
# (../web) hem geliştirme makinesindeki ayrı klasörde çalışıyor ve sunucu
# bir konteynere taşındığında da bozulmuyor.
def _web_klasoru_bul():
    elle = os.environ.get("EBRU_WEB_DIR")
    if elle:
        return elle

    burasi = os.path.dirname(os.path.abspath(__file__))
    adaylar = (
        os.path.join(burasi, "..", "web"),              # depo düzeni
        os.path.join(burasi, "..", "..", "..", "Ebru_Web"),  # ayrı klasör
    )

    for aday in adaylar:
        if os.path.isdir(os.path.join(aday, "templates")):
            return os.path.normpath(aday)

    # Hiçbiri yoksa ilk adayı döndür; başlangıçta uyarı basılıyor.
    return os.path.normpath(adaylar[0])


WEB_KLASORU = _web_klasoru_bul()

if not os.path.isdir(os.path.join(WEB_KLASORU, "templates")):
    print(f"⚠️  Web klasörü bulunamadı: {WEB_KLASORU}")
    print("   Site sayfaları açılmayacak. EBRU_WEB_DIR ile konumu ver.")

app = Flask(
    __name__,
    template_folder=os.path.join(WEB_KLASORU, "templates"),
    static_folder=os.path.join(WEB_KLASORU, "static"),
)

CORS(app)


# =====================================
# STATİK DOSYA SÜRÜMLEME
# =====================================
# Tarayıcı ve Cloudflare statik dosyaları 4 saat önbelleğe alıyor
# (max-age=14400). Şablonlarda bunun için elle tutulan bir "?v=5"
# vardı; sürüm artırmak unutulunca kullanıcılar eski JS ile kalıyor ve
# ortaya "kod doğru ama site eski davranıyor" gibi teşhisi zor bir
# durum çıkıyor. Bir kez yaşandı ve yarım saat yedi.
#
# Sürüm artık dosyanın değişiklik zamanından üretiliyor: dosya
# değişince adres de değişiyor, kimsenin bir şey hatırlaması
# gerekmiyor.
@app.context_processor
def _statik_yardimcisi():
    def statik(dosya):
        yol = os.path.join(app.static_folder or "", dosya)
        try:
            damga = int(os.path.getmtime(yol))
        except OSError:
            # Dosya yoksa sürümsüz döndür; şablon yine de çalışsın.
            damga = 0
        return "%s?v=%d" % (url_for("static", filename=dosya), damga)

    return {"statik": statik}
# =====================================
# STABLE DIFFUSION BAĞLANTI AYARLARI
# =====================================
# Eski tasarımda Colab tünel adresi her istekte Google Drive'daki bir
# dosyadan okunuyordu. Bu hem istek başına ~15 sn gecikme ekliyor hem de
# Drive'ın indirme onay sayfası yüzünden sessizce bozulabiliyordu.
#
# Yeni tasarım: Colab notebook'u açılışta kendi tünel adresini
# POST /register-backend ile buraya bildirir. Adres bellekte tutulur,
# arka planda çalışan bir sağlık kontrolü ayakta olup olmadığını izler.

# Site GPU'dan ayri bir makinede calistiginda (bkz. UZAK URETIM notu)
# bu makinede A1111 yok; 30 saniyede bir 127.0.0.1:7860'i yoklamanin
# anlami kalmiyor. Deger "0" verilirse yerel yedek tamamen devre disi
# kalir ve /health yalnizca kayitli uzak sunucuya bakar.
_yerel_sd_ayari = (
    os.environ.get("EBRU_LOCAL_SD_URL")
    or os.environ.get("SD_LOCAL_URL")
    or "http://127.0.0.1:7860"
).strip()

LOCAL_FALLBACK_URL = (
    None
    if _yerel_sd_ayari.lower() in ("0", "yok", "kapali", "kapalı")
    else _yerel_sd_ayari
)

# Colab'ın kendini kaydederken göndereceği gizli anahtar.
# Ortam değişkeni yoksa her açılışta rastgele üretilir ve konsola yazılır.
REGISTER_TOKEN = os.environ.get("EBRU_REGISTER_TOKEN")
_TOKEN_AUTO_GENERATED = REGISTER_TOKEN is None
if _TOKEN_AUTO_GENERATED:
    REGISTER_TOKEN = secrets.token_urlsafe(16)

# Yönetici master anahtarı. REGISTER_TOKEN'dan AYRI tutuluyor: tünel
# kaydı ile yönetici yetkisi farklı güven alanları; tek anahtarın
# sızması ikisini birden açmamalı. Tanımlı değilse geriye dönük uyum
# için REGISTER_TOKEN'a düşülüyor ve açılışta uyarı basılıyor.
_ADMIN_TOKEN_ENV = (os.environ.get("EBRU_ADMIN_TOKEN") or "").strip()
ADMIN_TOKEN = _ADMIN_TOKEN_ENV or REGISTER_TOKEN

# Yalnızca bilinen tünel sağlayıcıları kabul edilir.
#
# Listeye projenin kendi alt alan adı da eklendi: GPU artık isimli
# Cloudflare tüneliyle `gpu.ebruai.com` üzerinden bağlanıyor. Geçici
# adres her açılışta değiştiği için tünel koptuğunda üretim, yeni adres
# kaydedilene kadar kapalı kalıyordu.
#
# Eski sağlayıcılar listede duruyor: isimli tünel kurulamazsa üretim
# işçisi geçici tünele düşüyor ve o yol çalışmaya devam etmeli.
ALLOWED_TUNNEL_HOSTS = (
    "gpu.ebruai.com",
    "gradio.live",
    "trycloudflare.com",
    "ngrok-free.app",
    "ngrok.io",
    "loca.lt",
)

HEALTH_INTERVAL = 30      # saniye: arka plan sağlık kontrolü sıklığı
HEALTH_TIMEOUT = 6        # saniye: tek bir ping için üst sınır
GENERATE_TIMEOUT = int(
    os.environ.get("EBRU_GENERATE_TIMEOUT", "300")
)                         # saniye: görsel üretimi için üst sınır

# Geçici Cloudflare tüneli uzun isteklerde ara sıra araya girip JSON
# yerine kendi HTML hata sayfasını döndürüyor. Tünel ölmüş değil:
# ölçümde, hatadan 5 saniye sonra aynı adres yine cevap veriyordu.
# 27 Ağustos'ta günün 16 üretiminden 5'i tam bu yüzden düşmüştü.
# Bu yüzden aynı adres birkaç kez deneniyor.
URETIM_DENEME = int(os.environ.get("EBRU_URETIM_DENEME", "3"))
URETIM_DENEME_BEKLEME = 2.0   # saniye; her denemede biraz artıyor

# Bağlantıların yeniden kullanılması için oturumlar.
# Üretim ve yoklama ayrı oturumlarda: uzun süren üretim isteği
# havuzu meşgul ettiğinde ilerleme sorguları boş dönüyordu.
http = requests.Session()
probe_http = requests.Session()

# CLOUDFLARE ACCESS
# -----------------
# GPU artık isimli tünelle sabit bir adreste (gpu.ebruai.com). Sabit ve
# tahmin edilebilir olduğu için A1111'in API'si korumasız bırakılamaz:
# adresi bilen herkes başkasının kartında üretim yaptırabilir.
#
# Access açıldığında adres kimlik doğrulamasız açılmıyor. Sunucu bir
# "servis anahtarı" ile geçiyor; anahtar iki başlıkta gönderiliyor.
#
# İkisi de tanımlı değilse hiçbir şey eklenmiyor ve her şey eskisi gibi
# çalışıyor. Böylece Access panelden açılana kadar üretim durmuyor.
ACCESS_ID = (os.environ.get("EBRU_ACCESS_ID") or "").strip()
ACCESS_SECRET = (os.environ.get("EBRU_ACCESS_SECRET") or "").strip()

if ACCESS_ID and ACCESS_SECRET:
    for _oturum in (http, probe_http):
        _oturum.headers.update({
            "CF-Access-Client-Id": ACCESS_ID,
            "CF-Access-Client-Secret": ACCESS_SECRET,
        })
    print("🔐 Cloudflare Access servis anahtarı etkin")

# İlerleme bilgisi kısa süre önbelleklenir. Her sorgu A1111'e
# gitmiyor; VRAM'i zorlanan sunucuda bu fark yaratıyor.
PROGRESS_CACHE_TTL = 2.0
_progress_cache = {"veri": None, "zaman": 0.0}
_progress_lock = threading.Lock()


def get_progress_cached(active_url):
    """A1111'in ilerleme bilgisini en fazla saniyede bir kez sorar."""
    simdi = time.time()
    with _progress_lock:
        if (
            _progress_cache["veri"] is not None
            and simdi - _progress_cache["zaman"] < PROGRESS_CACHE_TTL
        ):
            return _progress_cache["veri"]

    try:
        veri = probe_http.get(
            f"{active_url}/sdapi/v1/progress",
            timeout=HEALTH_TIMEOUT,
        ).json()
    except Exception:
        veri = {}

    with _progress_lock:
        _progress_cache["veri"] = veri
        _progress_cache["zaman"] = simdi
    return veri

# Aktif backend durumu (arka plan thread'i ve istekler ortak kullanır).
_state_lock = threading.Lock()
_state = {
    "remote_url": None,     # Colab'ın kaydettiği tünel adresi
    "remote_ok": False,
    "local_ok": False,
    "registered_at": None,
    "last_check": None,
}


def probe(url):
    """Bir A1111 sunucusunun ayakta olup olmadığını hızlıca kontrol eder."""
    try:
        response = probe_http.get(
            f"{url}/sdapi/v1/progress",
            timeout=HEALTH_TIMEOUT,
        )
        # Tünel düşmüşse sağlayıcı HTML hata sayfası döndürür.
        content_type = response.headers.get("Content-Type", "")
        return response.status_code == 200 and "json" in content_type
    except Exception:
        return False


def refresh_health():
    """Kayıtlı uzak sunucuyu ve yerel GPU'yu kontrol edip durumu günceller."""
    with _state_lock:
        remote_url = _state["remote_url"]

    remote_ok = probe(remote_url) if remote_url else False
    local_ok = probe(LOCAL_FALLBACK_URL) if LOCAL_FALLBACK_URL else False

    with _state_lock:
        _state["remote_ok"] = remote_ok
        _state["local_ok"] = local_ok
        _state["last_check"] = time.time()


def health_loop():
    """Arka planda sürekli çalışan sağlık kontrolü."""
    while True:
        try:
            refresh_health()
        except Exception as e:
            print("⚠️ Sağlık kontrolü hatası:", e)
        time.sleep(HEALTH_INTERVAL)


def get_active_url():
    """
    Kullanılacak sunucuyu döner: önce Colab, o yoksa yerel GPU.
    Deneme-yanılma yapılmaz; durum arka planda zaten biliniyor.
    """
    with _state_lock:
        if _state["remote_ok"] and _state["remote_url"]:
            return _state["remote_url"], "colab"
        if _state["local_ok"]:
            return LOCAL_FALLBACK_URL, "local"
    return None, None


# =====================================
# KUYRUK VE KULLANIM SINIRLARI
# =====================================
# Uygulamayı indiren herkes aynı tek GPU'yu kullanacak. Eşzamanlı
# istekler GPU'yu belleksiz bırakıp tüm üretimleri düşürebildiği için
# aynı anda yalnızca bir üretim çalışır, kalanlar sıraya girer.

# A1111'in API'si ürettiği görseli varsayılan olarak diske yazmıyor,
# yalnızca yanıtta döndürüyor. Telefondaki kopya ise uygulamaya özel
# klasörde duruyor ve uygulama kaldırılınca siliniyor — bir güncelleme
# yüzünden bütün eserler böyle kaybolmuştu ve geri dönüş yeri yoktu.
# Açıkken her üretimin bir kopyası sunucuda kalıyor
# (stable-diffusion-webui/outputs/txt2img-images).
#
# A1111 üretim parametrelerini PNG üstverisine de gömüyor, yani seed
# dâhil her şey sonradan okunabiliyor.
#
# 704x1024 bir görsel ~300-500 KB; günlük 30 üretimde aylık ~450 MB.
# Yer sıkıntısı olursa EBRU_SAVE_IMAGES=0 ile kapatılabilir.
SAVE_IMAGES = os.environ.get("EBRU_SAVE_IMAGES", "1") == "1"

MAX_QUEUE = int(os.environ.get("EBRU_MAX_QUEUE", "8"))
QUEUE_TIMEOUT = int(os.environ.get("EBRU_QUEUE_TIMEOUT", "240"))
DAILY_LIMIT = int(os.environ.get("EBRU_DAILY_LIMIT", "3"))
MIN_INTERVAL = float(os.environ.get("EBRU_MIN_INTERVAL", "3"))

_gpu_semaphore = threading.BoundedSemaphore(1)
_queue_lock = threading.Lock()
_queue_length = 0

_usage_lock = threading.Lock()
_usage = {}


class KuyrukDolu(Exception):
    """Bekleyen istek sayısı üst sınıra ulaştı."""


class KuyrukZamanAsimi(Exception):
    """Sıra beklerken süre doldu."""


@contextmanager
def gpu_slot():
    """Aynı anda tek üretim çalışmasını sağlayan sıra yönetimi."""
    global _queue_length

    with _queue_lock:
        if _queue_length >= MAX_QUEUE:
            raise KuyrukDolu()
        _queue_length += 1
        sira = _queue_length

    if sira > 1:
        print(f"⏳ Sırada bekleyen istek sayısı: {sira}")

    try:
        if not _gpu_semaphore.acquire(timeout=QUEUE_TIMEOUT):
            raise KuyrukZamanAsimi()
        try:
            yield
        finally:
            _gpu_semaphore.release()
    finally:
        with _queue_lock:
            _queue_length -= 1


def client_ip():
    """
    Gerçek istemci IP'si.

    Tünel arkasında çalışırken her istek Flask'a 127.0.0.1 olarak
    geliyor; tünel gerçek adresi X-Forwarded-For başlığında iletiyor.
    Bu olmadan bütün kullanıcılar tek istemci sayılıyordu.
    """
    iletilen = request.headers.get("X-Forwarded-For", "")
    if iletilen:
        # İlk adres asıl istemci, sonrakiler ara sunucular.
        ilk = iletilen.split(",")[0].strip()
        if ilk:
            return ilk
    return request.remote_addr or "bilinmiyor"


# =====================================
# KİMLİK UÇLARINDA HIZ SINIRI
# =====================================
# Giriş ve kayıt şifreyi scrypt ile doğruluyor: kasıtlı olarak pahalı.
# Sunucu tek gunicorn işçisiyle küçük bir kutuda çalıştığı için sınırsız
# istek hem şifre deneme-yanılmasına hem de işçiyi kilitleyen bir DoS'a
# kapı açıyordu. IP başına pencere içinde sınırlı deneme.
KIMLIK_PENCERE = 300          # saniye
KIMLIK_MAX_DENEME = 10        # pencere içinde bu IP'ye izin verilen istek
_kimlik_denemeleri = {}       # ip -> [zaman, ...]
_kimlik_lock = threading.Lock()


def _guvenli_ip():
    """Hız sınırı için güvenilir istemci IP'si.

    client_ip() X-Forwarded-For'un ilk değerini alıyor; onu istemci de
    yazabilir, yani sınırı sahte IP'lerle atlatmak mümkün olurdu.
    CF-Connecting-IP'yi Cloudflare kendisi koyuyor ve istemcininkini
    eziyor, bu yüzden sınır anahtarı olarak güvenli.
    """
    cf = request.headers.get("CF-Connecting-IP", "").strip()
    return cf or client_ip()


def kimlik_hizi_asildi_mi():
    """Bu IP kimlik uçlarında pencere içinde çok mu istek attı.

    True dönerse istek reddedilmeli. Reddedilen istek de sayılıyor:
    ısrarla deneyen bot, denemeyi kesene kadar kilitli kalıyor.
    """
    simdi = time.time()
    ip = _guvenli_ip()
    with _kimlik_lock:
        gecmis = [
            t for t in _kimlik_denemeleri.get(ip, [])
            if simdi - t < KIMLIK_PENCERE
        ]
        gecmis.append(simdi)
        _kimlik_denemeleri[ip] = gecmis

        # Sözlük şişmesin: ara sıra tamamen eskimiş IP'leri at.
        if len(_kimlik_denemeleri) > 2000:
            for anahtar in list(_kimlik_denemeleri):
                if all(simdi - t >= KIMLIK_PENCERE
                       for t in _kimlik_denemeleri[anahtar]):
                    del _kimlik_denemeleri[anahtar]

        return len(gecmis) > KIMLIK_MAX_DENEME


def _hiz_asildi_yaniti():
    return jsonify({
        "status": "error",
        "message": "Çok fazla deneme yapıldı. Birkaç dakika sonra "
                   "tekrar deneyin.",
    }), 429


def client_id():
    """
    İstemciyi ayırt etmek için cihaz kimliği, yoksa IP adresi.
    Uygulama X-Device-Id başlığını gönderiyor.
    """
    return request.headers.get("X-Device-Id") or client_ip()


def check_rate_limit(kimlik, kullanici=None):
    """
    Kullanım sınırını denetler.
    Döner: (izin_var, mesaj, kac_saniye_sonra)

    Oturum açmış kullanıcıda günlük hak veritabanından okunuyor;
    böylece uygulamayı silip yeniden kurmak hakkı sıfırlamıyor ve
    sunucu yeniden başlasa da sayaç korunuyor.
    """
    simdi = time.time()
    bugun = time.strftime("%Y-%m-%d", time.localtime(simdi))

    # Art arda basmayı engelleyen kısa aralık her durumda bellekte.
    with _usage_lock:
        son = _usage.get(f"son:{kimlik}", 0)
        gecen = simdi - son
        if gecen < MIN_INTERVAL:
            return (
                False,
                "Çok sık istek gönderiyorsunuz, lütfen biraz bekleyin.",
                int(MIN_INTERVAL - gecen) + 1,
            )
        _usage[f"son:{kimlik}"] = simdi

    if kullanici:
        # Yonetici gunluk haktan muaf: ornek uretmek ve prompt motorunu
        # olcmek icin sinirsiz uretebilmesi gerekiyor. Art arda basmayi
        # engelleyen MIN_INTERVAL ona da uygulaniyor (yukarida).
        # ADMIN_KULLANICI asagida tanimli; calisma aninda cozuluyor.
        if _yonetici_mi(kullanici.get("kullanici_adi")):
            return True, None, None

        # Kişiye özel hak varsa o geçerli; yoksa genel değer.
        hak = _gunluk_hak(kullanici)
        kullanilan = kullanicilar.gunluk_sayi(kullanici["id"])
        if kullanilan >= hak:
            if hak == 0:
                return (
                    False,
                    "Bu hesap için üretim kapalı.",
                    None,
                )
            return (
                False,
                f"Günlük {hak} üretim hakkınız doldu. "
                "Yarın tekrar deneyebilirsiniz.",
                None,
            )
        kullanicilar.kullanim_artir(kullanici["id"])
        return True, None, None

    with _usage_lock:
        # Dünden kalan kayıtları ara sıra temizle.
        if len(_usage) > 1000:
            for anahtar in [
                k for k, v in _usage.items() if v["gun"] != bugun
            ]:
                del _usage[anahtar]

        kayit = _usage.get(kimlik)
        if kayit is None or kayit["gun"] != bugun:
            kayit = {"gun": bugun, "sayi": 0, "son": 0.0}
            _usage[kimlik] = kayit

        gecen = simdi - kayit["son"]
        if gecen < MIN_INTERVAL:
            return (
                False,
                "Çok sık istek gönderiyorsunuz, lütfen biraz bekleyin.",
                int(MIN_INTERVAL - gecen) + 1,
            )

        if kayit["sayi"] >= DAILY_LIMIT:
            return (
                False,
                f"Günlük {DAILY_LIMIT} üretim hakkınız doldu. "
                "Yarın tekrar deneyebilirsiniz.",
                None,
            )

        kayit["son"] = simdi
        kayit["sayi"] += 1
        return True, None, None


def refund_quota(kimlik, kullanici=None):
    """Üretim başarısız olduysa kullanılan hakkı geri verir."""
    if kullanici:
        kullanicilar.kullanim_azalt(kullanici["id"])
        return

    with _usage_lock:
        kayit = _usage.get(kimlik)
        if isinstance(kayit, dict) and kayit["sayi"] > 0:
            kayit["sayi"] -= 1


# =====================================
# İSTEK KAYIT DEFTERİ
# =====================================
# Kimin ne ürettiğini görebilmek için son isteklerin özeti bellekte
# tutulur. Görsel saklanmaz, yalnızca üstveri.

ISTEK_GECMISI_BOYUTU = int(os.environ.get("EBRU_LOG_SIZE", "200"))

_gecmis = deque(maxlen=ISTEK_GECMISI_BOYUTU)
_gecmis_lock = threading.Lock()

_sayaclar = {"toplam": 0, "basarili": 0, "hatali": 0}


def istek_kaydet(kimlik, ip, prompt, durum, sure, kaynak, mesaj=None):
    """Tamamlanan bir isteği geçmişe yazar."""
    with _gecmis_lock:
        _gecmis.append({
            "zaman": time.time(),
            "kimlik": kimlik,
            "ip": ip,
            "prompt": (prompt or "")[:120],
            "durum": durum,
            "sure": round(sure, 1),
            "kaynak": kaynak,
            "mesaj": (mesaj or "")[:160] if mesaj else None,
        })
        _sayaclar["toplam"] += 1
        if durum == "success":
            _sayaclar["basarili"] += 1
        else:
            _sayaclar["hatali"] += 1
# =====================================
# GELİŞMİŞ PROMPT ENGINE
# =====================================
# Ortak ebru sanat stili
# =====================================
# RENK TEMASINA GÖRE LORA AĞIRLIĞI
# =====================================
# Farklı renk temaları LoRA ile farklı etkileşime giriyor.
# Örneğin pastel tonlar daha yumuşak, çok renkli temalar
# daha yoğun bir LoRA baskısı gerektirebilir.
# LoRA ağırlığı aslında "ebru dokusu ne kadar baskın olsun" ayarı.
# Düşük değerde model nesneyi serbestçe çizebiliyor (araba, kuş,
# portre tanınır çıkıyor); yüksek değerde ebru dokusu her şeyin üstüne
# biniyor ve sonuç soyut/çiçeksi oluyor.
#
# Uygulamadaki paletler bu eksene bilinçli dağıtıldı; her paletin ne
# işe yaradığı seçim ekranında kullanıcıya yazılıyor. Yeni paletler
# eklenirken buraya da eklenmeli, yoksa hepsi varsayılana düşüp
# aralarındaki fark kaybolur.
COLOR_LORA_WEIGHTS = {
    # --- Nesne belirgin ---
    "pastel": 0.33,        # araba, hayvan, portre en net çıkar
    "lale": 0.45,          # nesne belli olur, doku hafif

    # --- Dengeli ---
    "okyanus": 0.55,       # soyut ama tanınır formlar
    "gece": 0.62,          # atmosferik, formlar erimeye başlar

    # --- Ebru baskın ---
    "osmanli": 0.75,       # klasik ebru, çiçek motifleri
    "osmanlı": 0.75,
    "zumrut": 0.88,        # en yoğun ebru dokusu
    "zümrüt": 0.88,

    # --- Web sitesindeki eski temalar ---
    "cok-renkli": 0.80,
    "mavi-beyaz": 0.45,
}

DEFAULT_LORA_WEIGHT = 0.55


def get_lora_weight(user_text):
    """Kullanıcı promptunda geçen renk temasına göre uygun LoRA ağırlığını seçer."""
    text = user_text.lower()
    for renk_key, agirlik in COLOR_LORA_WEIGHTS.items():
        if renk_key in text:
            print(f"🎨 Renk temasına göre LoRA ağırlığı: {renk_key} → {agirlik}")
            return agirlik
    return DEFAULT_LORA_WEIGHT


# Uygulamadaki "desen yoğunluğu" kaydırıcısının karşılığı.
# Ölçümle belirlendi: 0.30'da doku neredeyse yok, 0.90'da ebru her
# şeyin üstüne biniyor.
INTENSITY_MIN_LORA = 0.30
INTENSITY_MAX_LORA = 0.90

# --- Nesne istendiğinde uygulanan düzeltmeler ---
#
# Ölçüm (18 Ağustos, aynı seed'le karşılaştırmalı): nesne istendiğinde
# taç yapraklarda geniş beyaz alanlar çıkıyordu. Kaynağı paletin kendi
# metnindeki beyaz vurgusuydu ("... and ivory white"); negatif prompt
# tek başına onu yenemiyordu. Palet metninden beyaz vurgusu çıkarılınca
# beyaz kayboldu, saf ebru üretimi ise etkilenmedi.
NESNE_NEGATIF = (
    "white petals, striped petals, two-tone flower, variegated tulip"
)

# Referanstaki hatip ebrusu motifi küçük ve ortada duruyor; nesne
# istendiğinde kadrajı doldurmasın diye.
NESNE_KOMPOZISYON = (
    "(the motif small and centered, occupying only a third of the "
    "frame, surrounded by a wide calm marbled field:1.2)"
)

# Beyazın vurgu olduğu paletlerde (osmanli, okyanus, pastel) çıkarılıyor;
# beyazın paletin kendisi olduğu yerlerde (siyah-beyaz, mavi-beyaz…)
# dokunulmuyor, yoksa palet anlamını kaybeder.
_BEYAZ_VURGUSU = re.compile(
    r"(,\s*|\s+and\s+)(ivory white|soft white|clean white|pure white|creams|cream)",
    re.IGNORECASE,
)


def paletten_beyazi_cikar(anahtar, metin):
    """Nesne istendiğinde paletteki beyaz vurgusunu düşürür."""
    if "beyaz" in anahtar or "white" in anahtar:
        return metin
    return _BEYAZ_VURGUSU.sub("", metin)


# Nesne istendiğinde üst sınır. 0.60'a kadar nesne net kalıyor,
# üstüne çıkınca doku nesneyi yutmaya başlıyor.
NESNE_LORA_TAVANI = float(os.environ.get("EBRU_NESNE_LORA", "0.60"))


def intensity_to_lora(intensity):
    """Kaydırıcı değerini (0-100) LoRA ağırlığına çevirir."""
    oran = max(0, min(100, int(intensity))) / 100
    agirlik = INTENSITY_MIN_LORA + oran * (
        INTENSITY_MAX_LORA - INTENSITY_MIN_LORA
    )
    return round(agirlik, 2)
# LoRA'nın eğitim etiketleri. Veri setindeki tüm görseller bu üç
# kelimeyle etiketlendiği için model bunları gördüğünde SDXL'in genel
# bilgisi yerine öğrendiği ebru tarzına geçiyor.
#
# Ölçüm: aynı seed ile karşılaştırıldığında saf ebruda doku belirgin
# şekilde inceliyor, nesne istendiğinde ise fark çok daha büyük —
# tetikleyicisiz kedi dekoratif bir illüstrasyon çıkarken, tetikleyicili
# olanın tüyleri boya akışına dönüşüyor.
LORA_TETIKLEYICI = "ebru_style, marble texture, liquid art"

BASE_STYLE = f"""
{LORA_TETIKLEYICI},
traditional Turkish ebru marbling art,
authentic Ottoman paper marbling technique,
organic flowing paint patterns,
natural pigment movements on water,
handcrafted marbled paper texture,
soft color transitions,
elegant artistic composition,
balanced visual harmony,
museum quality artwork
""".replace("\n", " ").strip()

# Kullanıcı somut bir nesne istediğinde yukarıdaki uzun tanım nesneyi
# bastırıyor. O durumda ebru kimliğini koruyan kısa sürüm kullanılıyor.
BASE_STYLE_SHORT = (
    f"{LORA_TETIKLEYICI}, "
    "traditional Turkish ebru marbling art, "
    "marbled paper texture, flowing paint patterns"
)

OBJECT_PROMPTS = {

    "türk bayrağı":
    "the Turkish national flag, a white crescent moon and a white five-pointed star centered on a solid deep red rectangular flag",

    "bayrak":
    "a national flag with a crescent moon and star symbol on a solid colored background",

    "aslan":
    "a majestic lion with powerful body, detailed mane, expressive eyes, strong facial features, noble posture",

    "araba":
    "a modern luxury car with sleek metallic body, aerodynamic design, detailed headlights, wheels and windows",

    "otomobil":
    "a modern luxury car with sleek metallic body, aerodynamic design, detailed headlights, wheels and windows",


    "ağaç":
    "a majestic tree with thick textured trunk, detailed bark, green leafy branches and natural roots",


    "kanarya":
    "a small elegant yellow canary bird with soft detailed feathers, bright eyes, tiny orange beak and perched pose",


    "kuş":
    "a beautiful bird with detailed feathers, elegant wings, sharp beak and graceful posture",


    # Sözlükte olmayan bir hayvan yazıldığında motor onu nesne saymıyor:
    # desen tarifi prompt'ta 1.2 ağırlıkla kalıyor, LoRA'ya nesne tavanı
    # uygulanmıyor ve doku konuyu tamamen örtüyor. Çeviri doğru çalışsa
    # bile görselde çıkmıyor. Sık istenen hayvanlar bu yüzden burada.
    "kartal":
    "a powerful eagle with broad outstretched wings, detailed feathers, "
    "sharp curved beak and piercing focused eyes",

    "şahin":
    "a sleek falcon with pointed wings, detailed plumage, hooked beak "
    "and alert intense gaze",

    "kuğu":
    "an elegant white swan with long curved neck, smooth detailed "
    "feathers and calm graceful posture",

    "güvercin":
    "a gentle dove with soft rounded body, detailed wing feathers and "
    "calm posture",

    "leylek":
    "a tall stork with long slender legs, long straight beak, white and "
    "black detailed plumage",

    "kurt":
    "a wolf with thick detailed fur, alert pointed ears, intense eyes "
    "and strong upright stance",

    "geyik":
    "a noble deer with branching antlers, slender legs, soft detailed "
    "fur and calm watchful expression",

    "tilki":
    "a fox with pointed ears, bushy tail, detailed reddish fur and "
    "clever alert expression",

    "ayı":
    "a large bear with dense detailed fur, broad shoulders and "
    "powerful heavy stance",

    "tavşan":
    "a rabbit with long upright ears, soft detailed fur, round bright "
    "eyes and compact crouched pose",

    "yunus":
    "a dolphin with smooth streamlined body, curved dorsal fin and "
    "playful arching motion",

    "boğa":
    "a powerful bull with muscular body, curved horns, broad chest and "
    "strong grounded stance",


    "gemi":
    "a majestic wooden sailing ship with tall mast, detailed sails, ropes and realistic wooden hull",


    "tekne":
    "a small handcrafted wooden boat with curved hull, realistic wood texture and oars",


    "kelebek":
    "a beautiful butterfly with symmetrical patterned wings, delicate antennae and elegant body",


    "balık":
    "a realistic fish with detailed scales, flowing fins and elegant tail",


    "ay":
    "a glowing crescent moon with soft luminous light and celestial atmosphere",


    "güneş":
    "a radiant golden sun with detailed light rays and warm glowing appearance",


    "yıldız":
    "a five pointed star with soft glowing edges and elegant geometric shape",


    "kalp":
    "a smooth symmetrical heart shape with elegant curves and balanced proportions",


    "ev":
    "a traditional house with roof, windows, door, chimney and detailed walls",


    "köpek":
    "a loyal dog with detailed fur texture, expressive eyes, ears and natural posture",


    "kedi":
    "an elegant cat with detailed fur texture, whiskers, ears and graceful posture",


    "at":
    "a majestic horse with flowing silky mane, long tail, muscular athletic body, powerful legs, expressive eyes and noble appearance",

# --- HAYVANLAR ---
    "kaplan":
    "a majestic tiger with detailed striped fur, powerful body, sharp eyes and fierce expression",

    "ejderha":
    "a mythical dragon with detailed scales, large wings, sharp claws and fierce expression",

    "fil":
    "a majestic elephant with detailed wrinkled skin, large ears, long trunk and tusks",

    "baykuş":
    "a wise owl with detailed feathers, large round eyes and sharp talons",

    "tavus kuşu":
    "a peacock with an elaborate colorful fan-shaped tail with detailed eye patterns",

    # --- TAŞITLAR ---
    "uçak":
    "a modern airplane with detailed metallic fuselage, wings and engines",

    "helikopter":
    "a detailed helicopter with rotor blades, cockpit and metallic body",

    "motosiklet":
    "a detailed motorcycle with sleek metallic body, wheels and handlebars",

    "bisiklet":
    "a detailed bicycle with frame, wheels, handlebars and pedals",

    "tren":
    "a detailed train with metallic carriages, wheels and windows",

    # --- SEMBOLLER / BAYRAKLAR ---
    # NOT: "türk bayrağı" ve "bayrak" yukarıda zaten tanımlı,
    # burada tekrar tanımlanınca sessizce üzerine yazılıyordu.
    "ay yıldız":
    "a white crescent moon and a white five-pointed star together, a classic Turkish symbol",

    "nazar boncuğu":
    "a traditional Turkish evil eye amulet, a circular blue glass bead with concentric blue and white rings",

    # Ölçümle bulundu (18 Ağustos): "a classic tulip flower with
    # elegant curved petals" natüralist, iri ve kırmızı-beyaz alacalı
    # bir lale çıkarıyordu. Geleneksel hatip ebrusu lalesi tek renk,
    # küçük ve sivri uçludur; tarif ona göre yazıldı.
    "lale":
    "a single small stylized Ottoman hatip ebru tulip motif, "
    "solid deep red petals in one flat tone with a slender pointed "
    "curled tip, no white markings, no stripes, no two-tone petals, "
    "a thin curved dark green stem with long narrow pointed leaves",

    # --- ÇİÇEKLER ---
    # Sözlükte yalnızca genel "çiçek" ve "lale" vardı; kullanıcı "gül"
    # ya da "lavanta" yazdığında nesne algılanmıyor, ebru dokusu
    # kelimeyi tamamen eziyordu.
    "gül":
    "a rose flower with layered curved petals, detailed bloom and "
    "green leaves",

    "lavanta":
    "lavender flowers, tall slender stems topped with small purple "
    "blossoms",

    "papatya":
    "a daisy flower with white petals radiating around a yellow center",

    "karanfil":
    "a carnation flower with densely ruffled fringed petals",

    "orkide":
    "an orchid flower with broad symmetrical petals and delicate lip",

    "sümbül":
    "a hyacinth flower, dense cluster of small star shaped blossoms "
    "on an upright stem",

    "nergis":
    "a narcissus flower with white petals and a trumpet shaped center",

    "menekşe":
    "a violet flower with small rounded purple petals",

    "ayçiçeği":
    "a sunflower with broad golden petals around a dark seeded center",

    "zambak":
    "a lily flower with long curved petals and prominent stamens",

    # --- DOĞA / MEKAN ---
    "dağ":
    "a majestic mountain with detailed rocky peaks and snow-capped summit",

    "deniz":
    "a vast sea with detailed rippling waves and horizon",

    "orman":
    "a dense forest with detailed trees, foliage and natural textures",

    "çiçek":
    "an elegant flower with detailed petals and natural texture",

    "yaprak":
    "a detailed leaf with visible veins and natural organic shape",

    "şimşek":
    "a bright lightning bolt with jagged glowing energy",

    "bulut":
    "a soft fluffy cloud with detailed volumetric texture",

    # --- MEKAN / MANZARA ---
    # "çölde giden deve" gibi sahneler kurulabilsin diye mekan
    # kelimeleri de sozlukte. Motor bunlari nesneyle birlikte
    # esliyor; ikisi ayri parca olarak prompt'a giriyor.
    "çöl":
    "a vast desert with rolling sand dunes and rippled wind patterns",

    "vaha":
    "a desert oasis with a still water pool and slender palm trees",

    "göl":
    "a calm lake with a smooth mirror-like surface and distant shore",

    "nehir":
    "a winding river with flowing water and curved banks",

    "şelale":
    "a tall waterfall with cascading water and rising mist",

    "vadi":
    "a deep valley between sloping hillsides",

    "ova":
    "a wide open plain with gently rolling grassland",

    "bozkır":
    "a dry steppe with sparse grass and open horizon",

    "gökyüzü":
    "an expansive sky with layered drifting clouds",

    "gün batımı":
    "a sunset horizon with a low glowing sun and banded sky",

    # --- HAYVANLAR (ek) ---
    "deve":
    "a camel with a curved humped back, long neck and steady walking stance",

    "ceylan":
    "a gazelle with slender legs, curved horns and alert poised stance",

    "kaplumbağa":
    "a tortoise with a domed patterned shell and short sturdy legs",

    "yılan":
    "a serpent with a long coiled winding body and patterned scales",

    "arı":
    "a bee with rounded striped body and delicate transparent wings",

    "koç":
    "a ram with large spiral curved horns and thick woolly coat",

    "balina":
    "a whale with a massive smooth body and broad tail fluke",

    "horoz":
    "a rooster with an upright stance, tall comb and arched tail feathers",

    "turna":
    "a crane bird with long slender legs, extended neck and broad wings",

    # --- OSMANLI / TÜRK MOTİFLERİ ---
    "selvi":
    "a tall slender cypress tree with a narrow pointed silhouette",

    "çınar":
    "a broad plane tree with a thick trunk and wide spreading canopy",

    "rumi":
    "a rumi motif, interlaced curved split-leaf arabesque scrollwork",

    "hatayi":
    "a hatayi motif, a stylized symmetrical blossom seen in cross section",

    "çintemani":
    "a chintamani motif, three dots arranged above two wavy tiger stripes",

    "tuğra":
    "an Ottoman tughra, a calligraphic monogram with tall vertical strokes "
    "and sweeping curves",

    "hilal":
    "a crescent moon with clean tapering points",

    "kandil":
    "a hanging mosque lamp with a rounded glass body and suspension chains",

    "ibrik":
    "an ornate ewer with a curved spout, slender neck and rounded body",

    "minare":
    "a tall slender minaret with a balcony and a pointed conical cap",

    "kubbe":
    "a large rounded dome with smooth curved surface and a finial",

    "çeşme":
    "an ottoman street fountain with a carved arched niche and basin",

    # --- MÜZİK ---
    "ney":
    "a ney reed flute, a long slender tube with finger holes",

    "ud":
    "an oud, a short-necked lute with a deep rounded pear-shaped body",

    "saz":
    "a saz, a long-necked lute with a small teardrop body and long fretted neck",

    "kudüm":
    "a pair of small hemispherical kettle drums",

    # --- BİNALAR ---
    "cami":
    "a traditional mosque with detailed minarets, domes and Islamic architectural patterns",

    "kale":
    "a majestic castle with detailed stone walls, towers and battlements",

    "köprü":
    "a detailed bridge with arches, cables and structural supports",
    "taş ev":
    "a rustic stone house with detailed textured stone walls, a wooden door, small windows and a sloped roof",

    # --- SPOR / EŞYALAR ---
    "top":
    "a detailed round ball with textured surface and visible seams",

    "gitar":
    "a detailed acoustic guitar with wooden body, strings and neck",

    "kitap":
    "a detailed open book with visible pages and text",

    "saat":
    "a detailed clock with visible hands, numbers and circular face",

    "anahtar":
    "a detailed ornate key with intricate handle design",


    

}
# ==================================
# RENK SÖZLÜĞÜ
# =====================================
COLOR_PROMPTS = {


    "kırmızı":
    "deep red colors",


    "sarı":
    "golden yellow colors",


    "mavi":
    "deep blue colors",


    "lacivert":
    "dark navy blue colors",


    "yeşil":
    "natural green colors",


    "mor":
    "royal purple colors",


    "turuncu":
    "warm orange colors",


    "siyah":
    "black dark tones",


    "beyaz":
    "pure white tones",


    "altın":
    "luxury golden colors",

    # --- UYGULAMADAN GELEN RENK TEMALARI ---
    # Bu temaların daha önce renk karşılığı yoktu; yalnızca LoRA
    # ağırlığını etkiliyor, görselin rengine hiç yansımıyorlardı.
    "pastel":
    "soft pastel color palette, muted powdery tones, gentle low saturation "
    "pinks, mints and creams",

    "cok-renkli":
    "vivid multicolored palette, rich saturated rainbow of pigments "
    "blending into one another",

    "çok renkli":
    "vivid multicolored palette, rich saturated rainbow of pigments "
    "blending into one another",

    "mavi-beyaz":
    "classic blue and white palette, deep indigo tones swirling through "
    "clean white",

    # --- İKİLİ RENK KOMBİNASYONLARI ---
    # Takım renkleri gibi bilinen ikili kombinasyonlar. Renkler tescilli
    # değil; burada yalnızca renk tarif ediliyor, hiçbir arma ya da
    # logo tarifi yok.
    #
    # Aşağıdaki metinler de yukarıdaki kuralın kapsamında: SADECE renk.
    # Nesne veya doku ifadesi eklenirse kullanıcı bir nesne istediğinde
    # onunla yarışır.
    "sarı-kırmızı":
    "golden yellow and deep red color palette",

    "sari-kirmizi":
    "golden yellow and deep red color palette",

    "sarı-lacivert":
    "golden yellow and dark navy blue color palette",

    "sari-lacivert":
    "golden yellow and dark navy blue color palette",

    "siyah-beyaz":
    "black and white color palette, high contrast monochrome",

    "sarı-siyah":
    "golden yellow and black color palette",

    "sari-siyah":
    "golden yellow and black color palette",

    "bordo-mavi":
    "burgundy red and deep blue color palette",

    "yeşil-beyaz":
    "green and white color palette",

    "yesil-beyaz":
    "green and white color palette",

    "kırmızı-beyaz":
    "deep red and white color palette",

    "kirmizi-beyaz":
    "deep red and white color palette",

    # --- UYGULAMADAKİ RENK PALETLERİ ---
    # Uygulamanın seçim ekranındaki paletlerle birebir aynı anahtarlar.
    #
    # ÖNEMLİ: Bu metinler YALNIZCA renk tarif etmeli. Önceki sürümde
    # "tulip palette", "flower colors", "marbling veined", "swirling
    # foam" gibi ifadeler vardı; bunlar nesne ve doku emri oldukları
    # için kullanıcı "araba" istediğinde onunla yarışıp nesneyi
    # siliyordu. Ölçümde lale paletinde araba yerine lale çıkıyordu.
    "osmanli":
    "deep crimson red, burnished gold and ivory white color palette",

    "osmanlı":
    "deep crimson red, burnished gold and ivory white color palette",

    "zumrut":
    "deep emerald green and antique gold color palette",

    "zümrüt":
    "deep emerald green and antique gold color palette",

    "okyanus":
    "deep blue, aquamarine and soft white color palette",

    "gece":
    "deep indigo, near-black, silver and faint violet color palette",

    "lale":
    "rose pink, crimson and soft blush color palette",

}
ACTION_PROMPTS = {

# --- HAREKET ---
    "yüzen":
    "swimming gracefully through water",

    "zıplayan":
    "jumping energetically in mid-air",

    "dövüşen":
    "fighting in a dynamic dramatic pose",

    "dans eden":
    "dancing gracefully with flowing movement",

    "uyuyan":
    "sleeping peacefully in a relaxed pose",

    "savaşan":
    "battling fiercely in an intense dramatic pose",

    # --- DUYGU / İFADE ---
    "gülümseyen":
    "smiling warmly with a gentle happy expression",

    "kızgın":
    "with an angry fierce expression",

    "mutlu":
    "with a joyful happy expression",

    "üzgün":
    "with a sad melancholic expression",

    # --- KOMPOZİSYON / AÇI ---
    "yandan":
    "shown from a side profile view",

    "yukarıdan":
    "shown from a top-down aerial view",

    "yakından":
    "shown in a detailed close-up view",

    "gece":
    "set against a dark night sky with stars",

    "gündüz":
    "set in bright daylight with clear sky",
    "bana bakan":
    "looking directly at the viewer, front facing",


    "karşıya bakan":
    "facing forward with direct gaze",


    "uçan":
    "flying gracefully in motion",


    # Yürüme/ilerleme fiilleri: bunlar yokken "çölde giden deve"
    # ifadesindeki "giden" serbest metne düşüp "outgoing" diye
    # çevriliyor ve prompt'a anlamsız bir kelime giriyordu.
    "yürüyen":
    "walking with a steady forward stride",

    "giden":
    "moving forward across the scene",

    "ilerleyen":
    "advancing steadily forward",

    "süzülen":
    "gliding smoothly through the air",

    "tırmanan":
    "climbing upward",

    "dinlenen":
    "resting calmly at ease",

    "koşan":
    "running dynamically",


    "oturan":
    "sitting calmly",

    "ayakta":
    "standing proudly"

}
# =====================================
# EBRU DESEN STİLLERİ
# =====================================
# Uygulama "battal", "hatip", "taraklı" gibi geleneksel ebru desen
# adlarını gönderiyor. Bu adların İngilizce karşılığı olmadığı için
# çeviriye bırakıldıklarında anlamsız kelimelere dönüşüyor ve stil
# seçimi görsele hiç yansımıyordu. Her desenin görsel karşılığı burada
# tarif ediliyor.
STYLE_PROMPTS = {

    "battal":
    "battal marbling pattern, freely dropped paint forming large organic "
    "rounded blotches spread evenly across the surface, no combing, "
    "soft irregular edges",

    "hatip":
    "hatip marbling pattern, concentric rings of paint drawn into a "
    "symmetrical central rosette flower motif, radial petal shapes, "
    "balanced centered composition",

    "taraklı":
    "combed marbling pattern, regular parallel rows of evenly spaced "
    "wave crests drawn by a comb, rhythmic repeating undulations, "
    "precise structured lines",

    # NOT: "tarakli" ayrıca tanımlanmıyor; eşleştirme Türkçe karakter
    # toleranslı olduğu için "taraklı" anahtarı ikisini de yakalıyor.

    "bülbül yuvası":
    "nightingale nest marbling pattern, tight concentric spiral swirls "
    "coiled around multiple centers, nested circular vortices",

    "gelgit":
    "tide marbling pattern, paint drawn back and forth with a stylus "
    "into sweeping S-shaped curves, flowing directional movement",

    "şal":
    "shawl marbling pattern, interlocking curved plumes forming a dense "
    "ornamental paisley-like texture",

    "somaki":
    "porphyry marbling pattern, fine veined stone-like texture with "
    "delicate branching capillary lines",

    "neftli":
    "turpentine marbling pattern, scattered pale rounded droplet spots "
    "opening within the paint like lace",

}

# Prompt içinde anlam taşımayan, çeviriye gönderilmesi gereksiz kelimeler.
FILLER_WORDS = (
    "renklerinde",
    "renginde",
    "deseninde",
    "desenli",
    "tarzında",
    "şeklinde",
    "olsun",

    # Tek başına çevrilince saçmalayan bağlaç ve zaman kelimeleri.
    # Ölçüm: "gece vakti" → "vakti" artakalıp "woke up" olarak
    # çevriliyordu; "bir" → "One" olarak prompt'a giriyordu.
    "vakti",
    "zamanı",
    "bir",
    "ile",
    "gibi",
    "olan",
    "ve",
)

# Aynı serbest metin tekrar geldiğinde Google Translate'e gidilmez.
_translation_cache = {}
_translation_lock = threading.Lock()


_SUPHELI_CEVIRI = (
    "error 500",
    "server error",
    "that's an error",
    "<html",
    "that’s all we know",
)

# Google ucu ara ara 500 dönüyor ya da boş yanıt veriyor; aynı metin
# saniyeler sonra sorunsuz çevriliyor. Kaynak dili sırayla deniyoruz:
# "auto" İngilizce yazan kullanıcıyı da doğru işliyor, "tr" ise otomatik
# algılamanın tökezlediği kısa metinlerde daha güvenilir.
_CEVIRI_DENEMELERI = ("auto", "tr", "auto")


def _ceviri_dene(text_tr):
    """Çeviriyi birkaç kez dener. Hepsi başarısızsa None döner."""
    for sira, kaynak in enumerate(_CEVIRI_DENEMELERI, start=1):
        try:
            translated = GoogleTranslator(
                source=kaynak,
                target="en",
            ).translate(text_tr)
        except Exception as e:
            print(f"⚠️ Çeviri denemesi {sira} ({kaynak}) hata verdi: {e}")
            time.sleep(0.5 * sira)
            continue

        if not translated or any(
            s in translated.lower() for s in _SUPHELI_CEVIRI
        ):
            print(
                f"⚠️ Çeviri denemesi {sira} ({kaynak}) şüpheli sonuç verdi:",
                str(translated)[:80],
            )
            time.sleep(0.5 * sira)
            continue

        return translated

    return None


def translate_cached(text_tr):
    """Serbest metni İngilizce'ye çevirir, sonucu bellekte saklar."""
    with _translation_lock:
        if text_tr in _translation_cache:
            return _translation_cache[text_tr]

    translated = _ceviri_dene(text_tr)

    if translated is None:
        # ÖNEMLİ: başarısız çeviri önbelleğe ALINMIYOR.
        #
        # Eskiden alınıyordu: metin bir kez çevrilemediğinde Türkçe hâli
        # önbelleğe yazılıyor, sonraki her istek o kaydı okuduğu için bir
        # daha hiç denenmiyordu. Kullanıcı aynı prompt'u tekrar tekrar
        # denese de konu modele hep Türkçe gidiyor, SDXL anlamadığı için
        # görselde hiç çıkmıyordu. Sunucu yeniden başlatılmadan da
        # düzelmiyordu.
        print(
            "⚠️ Çeviri yapılamadı, bu istek için orijinal metin "
            "kullanılıyor:",
            text_tr[:60],
        )
        return text_tr

    with _translation_lock:
        _translation_cache[text_tr] = translated
    return translated


# =====================================
# PROMPT OLUŞTURMA
# =====================================
# Türkçe karakterlerin ASCII karşılıkları. Kullanıcılar sıklıkla
# "kus", "agac", "ucan" gibi yazıyor; bunlar da eşleşmeli.
_HARF_GRUPLARI = {
    "i": "iıîİ",
    "s": "sş",
    "g": "gğ",
    "u": "uüû",
    "o": "oö",
    "c": "cç",
    "a": "aâ",
}

# Her Türkçe harfi kendi ASCII kökeniyle ilişkilendiren ters tablo.
_HARF_KOKU = {
    harf: kok
    for kok, harfler in _HARF_GRUPLARI.items()
    for harf in harfler
}

_desen_onbellegi = {}


# Türkçe eklemeli bir dil: kullanıcı "orman" değil "ormanda", "kuş"
# değil "kuşlar" yazıyor. Katı kelime sınırı bunları kaçırıyordu ve
# motif prompt'a hiç girmiyordu.
#
# Ekler SAYILI: serbest bir harf dizisi ("çöl" + herhangi bir şey)
# "kuş"u "kuşku"ya, "at"ı "ateş"e eşlerdi. Buradakiler yalnızca isim
# çekim ekleri; sıfat-fiil ekleri (-en, -an) bilerek dışarıda, çünkü
# "gül" ile "gülen" farklı şeyler.
_TURKCE_EKLER = (
    "(?:l[ae]r)?"                       # çoğul: -ler/-lar
    "(?:"
    "[dt][ae]n"                         # -den/-dan/-ten/-tan
    "|[dt][ae]"                         # -de/-da/-te/-ta
    "|n?[iıuü]n"                        # -in/-ın/-nin/-nın
    "|y?[iıuü]"                         # -i/-ı/-yi/-yı
    "|y?[ea]"                           # -e/-a/-ye/-ya
    "|y?l[ae]"                          # -le/-la/-yle/-yla
    ")?"
)

# Ünsüz yumuşaması: sonu p/ç/t/k ile biten kelimeler ünlüyle başlayan
# ek alınca yumuşuyor (kelebek -> kelebeğe, balık -> balığı).
#
# Yalnızca 4 harften uzun köklerde uygulanıyor: "at" için yumuşak
# biçim "ad" olurdu ve "adı güzel" yazan kullanıcıya at motifi
# eklenirdi. Kısa köklerde kazanç riske değmiyor.
_YUMUSAMA = {"p": "b", "ç": "c", "t": "d", "k": "ğ"}
_YUMUSAMA_EN_KISA = 4

# Yumuşamış biçimden sonra ek ZORUNLU ve ünlüyle başlamak durumunda:
# yumuşama zaten ancak o zaman oluyor. Çoğul (-ler/-lar) ünsüzle
# başladığı için buraya girmiyor, doğrusu da o ("kelebekler").
_EK_UNLUYLE = "(?:n?[iıuü]n|y?[iıuü]|y?[ea])"


def tolerant_pattern(key):
    """
    Bir anahtar kelime için Türkçe karakter toleranslı regex üretir.
    Örn. "kuş" → k[uüû][sş] ; hem "kuş" hem "kus" eşleşir.
    """
    if key in _desen_onbellegi:
        return _desen_onbellegi[key]

    parcalar = []
    for harf in key.lower():
        kok = _HARF_KOKU.get(harf, harf)
        grup = _HARF_GRUPLARI.get(kok)
        if grup:
            parcalar.append(f"[{grup}]")
        else:
            parcalar.append(re.escape(harf))

    govde = "".join(parcalar)
    desen = govde + _TURKCE_EKLER

    # Sonu sert ünsüzle biten uzun kökler için yumuşamış biçim de
    # kabul ediliyor.
    yumusak_harf = _YUMUSAMA.get(key.lower()[-1]) if key else None
    if yumusak_harf and len(key) >= _YUMUSAMA_EN_KISA:
        yumusak_govde = "".join(parcalar[:-1]) + yumusak_harf
        desen = "(?:%s|%s%s)" % (desen, yumusak_govde, _EK_UNLUYLE)

    desen = r"\b" + desen + r"\b"
    _desen_onbellegi[key] = desen
    return desen


def word_match(key, text):
    """Anahtar kelimenin metinde TAM KELİME olarak geçip geçmediğini kontrol eder."""
    return re.search(tolerant_pattern(key), text) is not None


def residual_text(text, matched_keys):
    """
    Sözlüklerde karşılığı bulunan kelimeleri metinden çıkarır.
    Geriye yalnızca kullanıcının kendi yazdığı, çevrilmesi gereken
    serbest ifade kalır. Böylece "battal" gibi terimler ikinci kez,
    bu sefer anlamsız biçimde çevrilmez.
    """
    kalan = text
    for key in matched_keys:
        kalan = re.sub(tolerant_pattern(key), " ", kalan)
    for filler in FILLER_WORDS:
        kalan = re.sub(tolerant_pattern(filler), " ", kalan)

    kalan = re.sub(r'[,\-.;:]+', " ", kalan)
    kalan = re.sub(r'\s+', " ", kalan).strip()

    # Tek harf / anlamsız kırıntılar çeviriye gönderilmez.
    return kalan if len(kalan) >= 3 else ""


def _en_ozgul_anahtarlar(anahtarlar, metin=None):
    """
    Başka bir eşleşmenin içinde geçen anahtarları eler.
    Örn. "ay yıldız" eşleştiyse "ay" ayrıca eklenmez,
    "mavi-beyaz" eşleştiyse "mavi" ve "beyaz" tekrar eklenmez.

    Metin verilirse anahtarların METİNDEKİ eşleşme aralıklarına
    bakılıyor; verilmezse anahtar adlarının birbirini içermesine.

    Aralık karşılaştırması şart oldu: ek toleransıyla birlikte
    "bayrak" anahtarı "türk bayrağı" ifadesindeki "bayrağı"
    kelimesini de eşliyor. Anahtar adları karşılaştırıldığında
    ("bayrak" ile "türk bayrağı") biri diğerini içermediği için
    ikisi de kalıyor ve prompt'a hem genel bayrak hem Türk bayrağı
    tarifi giriyordu.
    """
    if metin is None:
        return [
            anahtar for anahtar in anahtarlar
            if not any(
                anahtar != digeri and anahtar in digeri
                for digeri in anahtarlar
            )
        ]

    araliklar = {}
    for anahtar in anahtarlar:
        eslesme = re.search(tolerant_pattern(anahtar), metin)
        if eslesme:
            araliklar[anahtar] = eslesme.span()

    sonuc = []
    for anahtar in anahtarlar:
        if anahtar not in araliklar:
            continue
        bas, son = araliklar[anahtar]
        kapsanan = any(
            digeri != anahtar
            and digeri in araliklar
            and araliklar[digeri][0] <= bas
            and son <= araliklar[digeri][1]
            and (araliklar[digeri][1] - araliklar[digeri][0]) > (son - bas)
            for digeri in anahtarlar
        )
        if not kapsanan:
            sonuc.append(anahtar)
    return sonuc


def _tekrarsiz(anahtarlar, sozluk):
    """
    Aynı metni üreten anahtarları teke indirir.
    "osmanli" ve "osmanlı" aynı palet tanımına bakıyor; Türkçe karakter
    toleransı ikisini birden eşleştirdiği için palet tarifi prompt'a
    iki kez giriyordu.
    """
    gorulen = set()
    sonuc = []
    for anahtar in anahtarlar:
        metin = sozluk[anahtar]
        if metin in gorulen:
            continue
        gorulen.add(metin)
        sonuc.append(anahtar)
    return sonuc


# Uygulama palet seçimini "<palet> renklerinde" kalıbıyla gönderiyor.
# Bazı palet adları nesne sözlüğünde de var ("lale" hem renk paleti
# hem de "a classic tulip flower"). Palet olarak gelen kelime nesne
# sayılmamalı, yoksa kullanıcı Lale paletini seçtiğinde ne isterse
# istesin görselde lale çıkıyor.
_PALET_KALIBI = re.compile(r'([\wÀ-ɏ-]+)\s+renklerinde')


def palette_words(text):
    """"<kelime> renklerinde" kalıbındaki palet adlarını döner."""
    return set(_PALET_KALIBI.findall(text.lower()))


def object_keys(text):
    """
    Metinde geçen nesne anahtarları.

    Palet olarak yazılan kelime nesne sayılmaz — ama yalnızca
    "<kelime> renklerinde" kalıbının GEÇTİĞİ YERDE. Eskiden kelime
    metnin tamamından siliniyordu; bu yüzden Lale paletini seçip
    ayrıca "lale" yazan kullanıcı laleyi hiç göremiyordu
    ("lale renklerinde, battal deseninde, lale" → nesne yok).
    Şimdi önce palet kalıpları metinden çıkarılıyor, nesne araması
    kalan metinde yapılıyor.
    """
    text = text.lower()
    kalan = _PALET_KALIBI.sub(" ", text)
    return [k for k in OBJECT_PROMPTS if word_match(k, kalan)]


def has_object(user_text):
    """Kullanıcı somut bir nesne istemiş mi (araba, kuş, cami…)."""
    return bool(object_keys(user_text))


def enrich_prompt(user_text, ozel_renkler=None):
    """Türkçe isteği İngilizce prompt'a çevirir.

    ozel_renkler verilirse (kullanıcı kendi rengini seçtiyse) hazır
    palet sözlüğü devreye girmiyor; renkler doğrudan tarife çevriliyor.
    """
    text = user_text.lower()
    prompt_parts = []

    ozel_palet = renk_secici.palet_tarifi(ozel_renkler) if ozel_renkler else None

    # Önce hangi anahtarların eşleştiğini bul, sonra en özgül olanları seç.
    eslesen = {
        "nesne": object_keys(text),
        "stil": [k for k in STYLE_PROMPTS if word_match(k, text)],
        "renk": [k for k in COLOR_PROMPTS if word_match(k, text)],
        "hareket": [k for k in ACTION_PROMPTS if word_match(k, text)],
    }
    _sozlukler = {
        "nesne": OBJECT_PROMPTS,
        "stil": STYLE_PROMPTS,
        "renk": COLOR_PROMPTS,
        "hareket": ACTION_PROMPTS,
    }
    for kategori in eslesen:
        eslesen[kategori] = _tekrarsiz(
            _en_ozgul_anahtarlar(eslesen[kategori], text),
            _sozlukler[kategori],
        )

    # Bir kelime hem nesne hem palet olamaz. "lale" ikisinde de var:
    # kullanıcı Osmanlı paletini seçip "lale" yazdığında prompt'a hem
    # Osmanlı'nın hem lalenin renk tarifi giriyordu ve iki palet
    # birbiriyle çelişiyordu. Palet olarak yazılan kelime zaten
    # object_keys içinde nesne sayılmıyor; buradaki de tersi:
    # nesne olarak yazılan kelime palet sayılmasın.
    nesne_anahtarlari = set(eslesen["nesne"])
    if nesne_anahtarlari:
        # "<kelime> renklerinde" kalıbında geçen kelime her hâlükârda
        # palet; kullanıcı onu ayrıca nesne olarak da yazmış olabilir
        # (Lale paleti + "lale") ve o zaman ikisi de doğrudur.
        # Yalnızca palet kalıbında GEÇMEYEN bir kelime nesne olarak
        # yazıldıysa palet sayılmaz.
        palet_kelimeleri = palette_words(text)
        cakisan = [
            k for k in eslesen["renk"]
            if k in nesne_anahtarlari and k not in palet_kelimeleri
        ]
        if cakisan:
            print(f"🎯 Nesne olarak yazıldı, palet sayılmadı: {cakisan}")
        eslesen["renk"] = [
            k for k in eslesen["renk"] if k not in cakisan
        ]

    matched_keys = [k for liste in eslesen.values() for k in liste]

    # Kullanıcı somut bir nesne istediyse (araba, kuş, cami…) prompt
    # dengesi değişiyor.
    #
    # Ölçüm: nesne 1.3 ağırlıkla bir kez geçerken ebru fikri BASE_STYLE'ın
    # 12 ifadesi + desen tarifi + LoRA + kalite ekleriyle defalarca
    # tekrarlanıyordu. Model ağırlığın olduğu tarafa gidip nesneyi
    # tamamen yutuyordu. Kısa promptla aynı model arabayı sorunsuz
    # çiziyor, yani sorun modelde değil prompt dengesindeydi.
    nesne_var = bool(eslesen["nesne"])

    for key in eslesen["nesne"]:
        prompt_parts.append(f"({OBJECT_PROMPTS[key]}:1.55)")

    # Desen tarifleri tuvalin tamamını kaplayan kompozisyon emirleri
    # ("spread evenly across the surface", "regular parallel rows").
    # Nesne istendiğinde bunlar nesneyle doğrudan çelişiyor ve onu
    # siliyor; o yüzden tarif tamamen çıkarılıp yerine yalnızca desenin
    # adı kısa bir doku ipucu olarak bırakılıyor.
    for key in eslesen["stil"]:
        if nesne_var:
            prompt_parts.append(f"{key} style marbling texture")
        else:
            prompt_parts.append(f"({STYLE_PROMPTS[key]}:1.2)")

    for key in eslesen["renk"]:
        if ozel_palet:
            continue          # kullanıcının kendi rengi geçerli
        metin = COLOR_PROMPTS[key]
        if nesne_var:
            metin = paletten_beyazi_cikar(key, metin)
        prompt_parts.append(metin)

    if ozel_palet:
        print(f"🎨 Kullanıcı paleti: {ozel_palet}")
        prompt_parts.append(ozel_palet)

    for key in eslesen["hareket"]:
        prompt_parts.append(ACTION_PROMPTS[key])

    # Sözlükte karşılığı olmayan kısım varsa çevrilir.
    # Hepsi eşleştiyse çeviri servisine hiç gidilmez.
    kalan = residual_text(text, matched_keys)
    if kalan:
        prompt_parts.append(translate_cached(kalan))
    else:
        print("⏩ Serbest metin yok, çeviri atlandı")

    prompt_parts.append(BASE_STYLE_SHORT if nesne_var else BASE_STYLE)

    if nesne_var:
        prompt_parts.append(NESNE_KOMPOZISYON)

    final_prompt = ", ".join(prompt_parts)
    print("\n✨ OLUŞAN PROMPT:")
    print(final_prompt)
    return final_prompt
# =====================================
# BACKEND KAYIT VE SAĞLIK UÇLARI
# =====================================
# =====================================
# HESAP UÇLARI
# =====================================
kullanicilar.kur()


def oturum_kullanicisi():
    """
    İstekteki oturum anahtarından kullanıcıyı çözer.
    Anahtar `Authorization: Bearer <token>` başlığında gelir.
    """
    baslik = request.headers.get("Authorization", "")
    if baslik.startswith("Bearer "):
        return kullanicilar.oturumu_coz(baslik[7:].strip())
    return None


def _dogrulama_postasi_yolla(oturum_anahtari):
    """Oturum sahibine doğrulama bağlantısı gönderir.

    Döner: True (gönderildi) / False (gönderilemedi). Hata kullanıcıya
    değil günlüğe yazılıyor; Resend'in cevabı adres hakkında bilgi
    sızdırabilir.
    """
    kullanici = kullanicilar.oturumu_coz(oturum_anahtari)
    if not kullanici or not kullanici.get("eposta"):
        return False

    if not eposta_servisi.yapilandirildi_mi():
        print("⚠️  EBRU_RESEND_API_KEY yok; doğrulama postası gönderilemedi.")
        return False

    kod, bekle = kullanicilar.dogrulama_kodu_olustur(
        kullanici["id"], kullanici["eposta"]
    )
    if not kod:
        print(f"⏳ Doğrulama postası çok sık istendi ({bekle} sn kaldı)")
        return False

    basarili, hata = eposta_servisi.dogrulama_postasi_gonder(
        kullanici["eposta"], kullanici["kullanici_adi"], kod
    )
    if basarili:
        print(f"✉️  Doğrulama postası gönderildi: {kullanici['kullanici_adi']}")
    else:
        print(f"✉️  Doğrulama postası GÖNDERİLEMEDİ: {hata}")
    return basarili


@app.route("/auth/dogrulama-gonder", methods=["POST"])
def auth_dogrulama_gonder():
    """Doğrulama bağlantısını yeniden gönderir."""
    baslik = request.headers.get("Authorization", "")
    oturum_anahtari = baslik[7:].strip() if baslik.startswith("Bearer ") else ""

    kullanici = kullanicilar.oturumu_coz(oturum_anahtari)
    if not kullanici:
        return jsonify({
            "status": "error",
            "message": "Oturum açmanız gerekiyor",
        }), 401

    if kullanici.get("eposta_dogrulandi"):
        return jsonify({
            "status": "success",
            "message": "E-posta adresiniz zaten onaylı.",
            "email_verified": True,
        })

    if not kullanici.get("eposta"):
        return jsonify({
            "status": "error",
            "message": (
                "Hesabınızda kayıtlı e-posta adresi yok. "
                "Yeni bir hesap açmanız gerekiyor."
            ),
        }), 400

    if not eposta_servisi.yapilandirildi_mi():
        return jsonify({
            "status": "error",
            "message": (
                "Posta servisi şu anda yapılandırılmamış. "
                "Lütfen biraz sonra tekrar deneyin."
            ),
        }), 503

    kod, bekle = kullanicilar.dogrulama_kodu_olustur(
        kullanici["id"], kullanici["eposta"]
    )
    if not kod:
        return jsonify({
            "status": "error",
            "message": f"Çok sık istediniz. {bekle} saniye sonra tekrar deneyin.",
            "retry_after": bekle,
        }), 429

    basarili, hata = eposta_servisi.dogrulama_postasi_gonder(
        kullanici["eposta"], kullanici["kullanici_adi"], kod
    )
    if not basarili:
        print(f"✉️  Yeniden gönderim başarısız: {hata}")
        return jsonify({
            "status": "error",
            "message": "Posta gönderilemedi. Biraz sonra tekrar deneyin.",
        }), 502

    return jsonify({
        "status": "success",
        "message": "Doğrulama bağlantısı e-posta adresinize gönderildi.",
    })


def _google_kimligi_coz(data):
    """İstekteki Google belirtecini doğrular. (bilgi, hata_cevabi) döner."""
    try:
        bilgi = google_giris.dogrula(data.get("credential"))
    except google_giris.GoogleHatasi as e:
        return None, (jsonify({"status": "error", "message": str(e)}), 400)
    return bilgi, None


@app.route("/auth/google", methods=["POST"])
def auth_google():
    """Google ile giriş.

    Üç sonuç var:
      1. Google kimliği zaten bir hesaba bağlı  -> giriş
      2. Aynı e-postayla ONAYLI bir hesap var   -> hesaplar birleştirilir
      3. Hiçbiri                                 -> kullanıcı adı istenir
    """
    if not google_giris.yapilandirildi_mi():
        print(f"⚠️  Google girişi kapalı: {google_giris.eksik_ne()}")
        return jsonify({
            "status": "error",
            "message": "Google ile giriş şu anda kullanılamıyor.",
        }), 503

    data = request.get_json(silent=True) or {}
    bilgi, hata = _google_kimligi_coz(data)
    if hata:
        return hata

    # 1) Daha önce bağlanmış hesap
    mevcut = kullanicilar.google_ile_bul(bilgi["sub"])
    if mevcut:
        token = kullanicilar.oturum_ac_kullanici(mevcut["id"])
        print(f"🔑 Google girişi: {mevcut['kullanici_adi']}")
        return _google_cevabi(token, mevcut["kullanici_adi"])

    # 2) Aynı e-postayla açılmış şifreli hesap
    eslesen = kullanicilar.eposta_ile_bul(bilgi["eposta"])
    if eslesen:
        # Onaysız hesaba bağlanmıyoruz. Aksi halde biri başkasının
        # adresiyle hesap açıp bekleyebilir; adresin gerçek sahibi
        # Google'la girdiğinde o hesaba düşer ve şifresi saldırganda
        # olduğu için hesap devralınmış olurdu.
        if not eslesen["eposta_dogrulandi"]:
            return jsonify({
                "status": "error",
                "message": (
                    "Bu e-posta adresiyle onaylanmamış bir hesap var. "
                    "Önce o hesabın e-postasını onaylayın, sonra Google ile "
                    "giriş yapabilirsiniz."
                ),
            }), 409

        kullanicilar.google_bagla(eslesen["id"], bilgi["sub"])
        token = kullanicilar.oturum_ac_kullanici(eslesen["id"])
        print(f"🔗 Google hesabı bağlandı: {eslesen['kullanici_adi']}")
        return _google_cevabi(token, eslesen["kullanici_adi"])

    # 3) Yeni kullanıcı: kullanıcı adı seçmesi gerekiyor.
    #
    # Google bilgisi sunucuda saklanmıyor; istemci ikinci istekte aynı
    # belirteci tekrar gönderiyor ve biz yeniden doğruluyoruz. Böylece
    # "bekleyen kayıt" diye bir durum tutmak gerekmiyor. Belirtecin
    # ömrü (~1 saat) bu adım için fazlasıyla yeterli.
    return jsonify({
        "status": "username_required",
        "message": "Son bir adım: kullanıcı adı seçin.",
        "suggested": (bilgi["eposta"].split("@")[0] or "")[:24],
        "email": bilgi["eposta"],
    }), 200


@app.route("/auth/google/kullanici-adi", methods=["POST"])
def auth_google_kullanici_adi():
    """Google ile gelen yeni kullanıcının hesabını açar."""
    if not google_giris.yapilandirildi_mi():
        return jsonify({
            "status": "error",
            "message": "Google ile giriş şu anda kullanılamıyor.",
        }), 503

    data = request.get_json(silent=True) or {}
    bilgi, hata = _google_kimligi_coz(data)
    if hata:
        return hata

    # Bu arada başka bir sekmede bağlanmış olabilir.
    mevcut = kullanicilar.google_ile_bul(bilgi["sub"])
    if mevcut:
        token = kullanicilar.oturum_ac_kullanici(mevcut["id"])
        return _google_cevabi(token, mevcut["kullanici_adi"])

    try:
        token, ad = kullanicilar.google_kayit(
            (data.get("username") or "").strip(),
            bilgi["eposta"],
            bilgi["sub"],
            bilgi["ad"],
            bilgi["soyad"],
        )
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"👤 Yeni hesap (Google): {ad}")
    return _google_cevabi(token, ad), 201


def _google_cevabi(token, ad):
    """Google akışının başarı cevabı; giriş/kayıt ile aynı biçimde."""
    kullanici = kullanicilar.oturumu_coz(token)
    return jsonify({
        "status": "success",
        "token": token,
        "username": ad,
        "is_admin": _yonetici_mi(ad),
        # Google adresi kendisi doğruladığı için bu hesaplar
        # doğrulanmış geliyor; ön yüz onay ekranına götürmesin.
        "email_verified": True,
        "daily_limit": _gunluk_hak(kullanici),
    })


@app.route("/auth/google/durum", methods=["GET"])
def auth_google_durum():
    """Ön yüz Google düğmesini gösterip göstermeyeceğini buradan öğreniyor.

    İstemci kimliği gizli değil; sayfaya zaten gömülüyor.
    """
    return jsonify({
        "enabled": google_giris.yapilandirildi_mi(),
        "client_id": google_giris.ISTEMCI_KIMLIGI,
    })


@app.route("/auth/sifre-unuttum", methods=["POST"])
def auth_sifre_unuttum():
    """Şifre sıfırlama bağlantısı ister.

    Adres kayıtlı olsun ya da olmasın AYNI cevabı dönüyor. "Bu adres
    kayıtlı değil" demek, kimin üye olduğunu isteyen herkese söylerdi;
    bir adres listesini tek tek deneyerek üyeleri ayıklamak mümkün olurdu.
    """
    data = request.get_json(silent=True) or {}
    eposta = (data.get("email") or "").strip()

    # Google ile açılmış hesabın şifresi yoktur, dolayısıyla
    # sıfırlanacak bir şey de yok. Bunu kişiye özel söylemek
    # ("bu hesap Google ile açılmış") adresin kayıtlı olduğunu ele
    # verirdi; bir adres listesi denenerek üyeler ayıklanabilirdi.
    # Onun yerine açıklama HERKESE gösterilen ortak mesajın içinde:
    # kimseyi ayırt etmiyor ama Google kullanıcısı ne yapacağını
    # anlıyor. Aksi halde hiç gelmeyecek bir postayı bekliyordu.
    ayni_cevap = jsonify({
        "status": "success",
        "message": (
            "Bu adres kayıtlıysa şifre sıfırlama bağlantısı gönderilmiştir. "
            "Lütfen gelen kutunuzu ve gereksiz (spam) klasörünüzü "
            "kontrol ediniz. "
            "Hesabınızı Google ile açtıysanız şifreniz bulunmamaktadır; "
            "bu hesaba “Google ile devam et” seçeneğiyle "
            "giriş yapabilirsiniz."
        ),
    })

    if not eposta:
        return ayni_cevap

    kod, ad = kullanicilar.sifre_kodu_olustur(eposta)
    if not kod:
        # Hesap yok, Google hesabı ya da çok sık istendi. Üçünde de
        # dışarıya aynı cevap gidiyor; ayrım yalnızca günlükte.
        print(f"🔑 Şifre sıfırlama isteği karşılıksız: {eposta[:3]}***")
        return ayni_cevap

    if not eposta_servisi.yapilandirildi_mi():
        print("⚠️  EBRU_RESEND_API_KEY yok; sıfırlama postası gönderilemedi.")
        return ayni_cevap

    basarili, hata = eposta_servisi.sifirlama_postasi_gonder(eposta, ad, kod)
    if basarili:
        print(f"🔑 Şifre sıfırlama postası gönderildi: {ad}")
    else:
        print(f"🔑 Şifre sıfırlama postası GÖNDERİLEMEDİ: {hata}")

    return ayni_cevap


@app.route("/sifre-sifirla/<token>", methods=["GET"])
def sifre_sifirla_sayfasi(token):
    """E-postadaki bağlantı buraya geliyor: yeni şifre formu."""
    return render_template(
        "sifre_sifirla.html",
        token=token,
        gecerli=kullanicilar.sifre_kodu_gecerli_mi(token),
    )


@app.route("/auth/sifre-sifirla", methods=["POST"])
def auth_sifre_sifirla():
    """Yeni şifreyi kaydeder."""
    data = request.get_json(silent=True) or {}
    token = (data.get("token") or "").strip()
    yeni = data.get("password") or ""

    try:
        ad = kullanicilar.sifre_kodu_kullan(token, yeni)
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"🔑 Şifre değiştirildi: {ad}")
    return jsonify({
        "status": "success",
        "message": (
            "Şifreniz değiştirildi. Güvenlik için açık bütün oturumlar "
            "kapatıldı; yeni şifrenizle giriş yapabilirsiniz."
        ),
    })


@app.route("/gizlilik")
def gizlilik():
    """Gizlilik politikasi.

    Google Auth Platform uygulamayi yayinlamak icin bu adresi sart
    kosuyor; icerigi projenin fiilen yaptigi veri islemeyi anlatiyor.
    Veri isleyen bir yer eklenirse sablon da guncellenmeli.
    """
    return render_template("gizlilik.html")


@app.route("/kosullar")
def kosullar():
    """Kullanim kosullari."""
    return render_template("kosullar.html")


@app.route("/hesap-sil")
def hesap_sil():
    """Hesap silme sayfasi.

    Google Play, uygulamayi kurmadan da ulasilabilen bir hesap silme
    adresi istiyor; altbilgideki baglanti bu yuzden her sayfada var.

    Yetki denetimi yok: sayfa oturumu kendisi yokluyor. Tarayici adres
    cubugundan Authorization basligi gonderemiyor, yani sunucu tarafinda
    denetlemek zaten mumkun degil (/admin de ayni sebeple boyle).
    """
    return render_template("hesap_sil.html")


@app.route("/onay-bekleniyor")
def onay_bekleniyor():
    """Kayıttan sonra gelinen sayfa: e-postanı onayla.

    Yetki denetimi yok; sayfa kendisi oturumu kontrol edip gerekirse
    girişe yönlendiriyor. Tarayıcı adres çubuğundan Authorization
    başlığı gönderemediği için sunucu tarafında denetlemek zaten
    mümkün değil (aynı sebeple /admin de böyle çalışıyor).
    """
    return render_template("onay_bekleniyor.html")


@app.route("/dogrula/<token>", methods=["GET"])
def dogrula(token):
    """E-postadaki bağlantı buraya geliyor.

    Tarayıcıdan açıldığı için JSON değil sayfa döndürüyor.
    """
    try:
        ad = kullanicilar.dogrulama_kodu_kullan(token)
    except kullanicilar.KayitHatasi as e:
        return render_template(
            "dogrulama.html", basarili=False, mesaj=str(e)
        ), 400

    print(f"✅ E-posta doğrulandı: {ad}")
    return render_template("dogrulama.html", basarili=True, kullanici=ad)


@app.route("/auth/register", methods=["POST"])
def auth_register():
    if kimlik_hizi_asildi_mi():
        return _hiz_asildi_yaniti()
    data = request.get_json(silent=True) or {}
    try:
        token, ad = kullanicilar.kayit_ol(
            data.get("username"),
            data.get("password"),
            # 19 Ağustos 2026'da zorunlu oldu. Eski mobil sürüm bu üç
            # alanı göndermiyor; kayit_ol o durumu anlatan ve kullanıcıyı
            # siteye yönlendiren bir mesaj döndürüyor.
            ad=data.get("first_name"),
            soyad=data.get("last_name"),
            eposta=data.get("email"),
        )
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"👤 Yeni hesap: {ad}")

    # Doğrulama postası gönderiliyor.
    #
    # Gönderim başarısız olsa bile kayıt geri alınmıyor: hesap açıldı,
    # kullanıcı giriş yapabiliyor ve panelden yeniden gönderim
    # isteyebiliyor. Posta servisindeki geçici bir arıza yüzünden
    # kullanıcıyı hesapsız bırakmanın anlamı yok.
    gonderildi = _dogrulama_postasi_yolla(token)

    return jsonify({
        "status": "success",
        "token": token,
        "username": ad,
        "is_admin": _yonetici_mi(ad),
        # Hesap açıldı ama üretim için e-posta onayı gerekiyor.
        # Ön yüz bu bilgiyle "e-postanı onayla" ekranını gösteriyor.
        "email_verified": False,
        "verification_sent": gonderildi,
    }), 201


@app.route("/auth/login", methods=["POST"])
def auth_login():
    if kimlik_hizi_asildi_mi():
        return _hiz_asildi_yaniti()
    data = request.get_json(silent=True) or {}
    try:
        token, ad = kullanicilar.giris_yap(
            data.get("username"), data.get("password")
        )
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 401

    print(f"🔑 Giriş: {ad}")

    # Doğrulama durumu girişten sonra okunuyor. giris_yap yalnızca
    # (token, ad) döndürüyor ve imzasını değiştirmek mobil tarafta da
    # karşılığı olan bir iş; oturumu çözmek tek ek sorguyla aynı bilgiyi
    # veriyor.
    oturum = kullanicilar.oturumu_coz(token) or {}

    return jsonify({
        "status": "success",
        "token": token,
        "username": ad,
        "is_admin": _yonetici_mi(ad),
        "email_verified": bool(oturum.get("eposta_dogrulandi")),
    })


@app.route("/auth/me", methods=["GET"])
def auth_me():
    """Uygulama açılışta oturumun hâlâ geçerli olduğunu buradan anlar."""
    kullanici = oturum_kullanicisi()
    if not kullanici:
        return jsonify({
            "status": "error",
            "message": "Oturum geçersiz",
        }), 401

    return jsonify({
        "status": "success",
        "username": kullanici["kullanici_adi"],
        "daily_used": kullanicilar.gunluk_sayi(kullanici["id"]),
        "daily_limit": _gunluk_hak(kullanici),
        "is_admin": _yonetici_mi(kullanici["kullanici_adi"]),
        "email": kullanici.get("eposta"),
        "email_verified": bool(kullanici.get("eposta_dogrulandi")),
        # Hesap silme ekranı buna bakıyor: şifresi olan hesaptan şifre,
        # Google hesabından kullanıcı adı onayı isteniyor.
        "registration_path": kullanici.get("kayit_yolu", "sifre"),
        "has_password": kullanici.get("kayit_yolu", "sifre") != "google",
    })


@app.route("/auth/logout", methods=["POST"])
def auth_logout():
    baslik = request.headers.get("Authorization", "")
    if baslik.startswith("Bearer "):
        kullanicilar.cikis_yap(baslik[7:].strip())
    return jsonify({"status": "success"})


@app.route("/auth/hesabimi-sil", methods=["POST"])
def auth_hesabimi_sil():
    """Kullanıcının kendi hesabını silmesi.

    Google Play, uygulama içinden hesap silme yolu olmasını şart
    koşuyor; yöneticiden istemek yetmiyor.

    Son onay hesabın açılış yoluna göre değişiyor:
      * şifreyle açılan hesap  -> şifresini yazıyor,
      * Google ile açılan hesap -> kullanıcı adını yazıyor
        (o hesapların kullanılabilir bir şifresi yok).

    İşlem geri alınamıyor: eserler, sayaçlar ve oturumlar da gidiyor.
    """
    kullanici = oturum_kullanicisi()
    if not kullanici:
        return jsonify({
            "status": "error",
            "message": "Oturum geçersiz",
        }), 401

    # Kurucu yönetici silinemiyor. Silinirse panele girebilecek kimse
    # kalmaz ve tek çıkış yolu sunucuda veritabanını elle düzenlemek
    # olur; yönetici silme ucunda da aynı koruma var.
    if _kurucu_yonetici_mi(kullanici["kullanici_adi"]):
        return jsonify({
            "status": "error",
            "message": "Kurucu yönetici hesabı silinemez.",
        }), 400

    veri = request.get_json(silent=True) or {}
    google_hesabi = kullanici.get("kayit_yolu") == "google"

    if google_hesabi:
        onay = (veri.get("onay") or "").strip()
        if onay.lower() != kullanici["kullanici_adi"].lower():
            return jsonify({
                "status": "error",
                "message": "Onaylamak için kullanıcı adınızı yazın.",
            }), 400
    else:
        sifre = veri.get("sifre") or veri.get("password") or ""
        if not kullanicilar.sifre_dogru_mu(kullanici["id"], sifre):
            return jsonify({
                "status": "error",
                "message": "Şifre yanlış.",
            }), 400

    ad = kullanici["kullanici_adi"]
    try:
        kullanicilar.sil(kullanici["id"])
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"🗑️  Hesap sahibi tarafından silindi: {ad}")
    return jsonify({
        "status": "success",
        "message": "Hesabınız ve bütün verileriniz silindi.",
    })


@app.route("/register-backend", methods=["POST"])
def register_backend():
    """
    Colab notebook'u açılışta tünel adresini buraya bildirir.
    Drive üzerinden URL okuma yöntemi tamamen kaldırıldı.
    """
    data = request.get_json(silent=True) or {}
    token = data.get("token", "")
    url = (data.get("url") or "").strip().rstrip("/")

    if not secrets.compare_digest(str(token), REGISTER_TOKEN):
        print("⛔ Geçersiz token ile kayıt denemesi")
        return jsonify({
            "status": "error",
            "message": "Geçersiz token"
        }), 403

    if not url.startswith("https://") or not any(
        host in url for host in ALLOWED_TUNNEL_HOSTS
    ):
        return jsonify({
            "status": "error",
            "message": "Desteklenmeyen tünel adresi"
        }), 400

    with _state_lock:
        _state["remote_url"] = url
        _state["registered_at"] = time.time()

    # Kayıttan hemen sonra doğrula, bir sonraki döngüyü bekleme.
    refresh_health()

    with _state_lock:
        ok = _state["remote_ok"]

    print(f"📡 Backend kaydedildi: {url} (erişilebilir: {ok})")
    return jsonify({
        "status": "success",
        "reachable": ok
    })


@app.route("/unregister-backend", methods=["POST"])
def unregister_backend():
    """
    Uretim makinesi kapanirken kaydini siler.

    Bu uc olmadan da sistem dogru calisir: saglik kontrolu 30 saniye
    icinde tunelin dustugunu fark eder. Ama kullanicinin gordugu sey
    "uretimi kapattim, site hala acik diyor" oluyordu. Temiz kapanista
    durum aninda guncellensin diye eklendi.
    """
    data = request.get_json(silent=True) or {}
    token = data.get("token", "")

    if not secrets.compare_digest(str(token), REGISTER_TOKEN):
        return jsonify({
            "status": "error",
            "message": "Geçersiz token"
        }), 403

    with _state_lock:
        _state["remote_url"] = None
        _state["remote_ok"] = False
        _state["registered_at"] = None
        _state["last_check"] = time.time()

    print("📴 Uretim makinesi kaydini sildi")
    return jsonify({"status": "success"})


@app.route("/progress", methods=["GET"])
def progress():
    """
    Süren üretimin ilerlemesini döner. Uygulama bunu saniyede bir
    çağırıp gerçek bir ilerleme çubuğu gösterebilir.
    """
    active_url, kaynak = get_active_url()

    with _queue_lock:
        bekleyen = _queue_length

    if active_url is None:
        return jsonify({
            "status": "success",
            "progress": 0.0,
            "eta_seconds": None,
            "queue_length": bekleyen,
            "ready": False,
        })

    veri = get_progress_cached(active_url)

    return jsonify({
        "status": "success",
        "progress": veri.get("progress", 0.0),
        "eta_seconds": veri.get("eta_relative"),
        "queue_length": bekleyen,
        "source": kaynak,
        "ready": True,
    })


# İzleme ekranına erişebilecek hesap. Bu kullanıcı adıyla giriş
# yapan kişi yönetici sayılıyor; ayrıca bir anahtar girmesi gerekmiyor.
# Şifre kodda tutulmuyor, hesabın kendi şifresi geçerli.
ADMIN_KULLANICI = os.environ.get("EBRU_ADMIN_USER", "boss")


def _kurucu_yonetici_mi(kullanici_adi):
    """Ortam değişkeninde tanımlı, yetkisi alınamayan yönetici mi."""
    return (kullanici_adi or "").lower() == ADMIN_KULLANICI.lower()


def _yonetici_mi(kullanici_adi):
    """Bu kullanıcı adı yönetici mi.

    İki kaynak var:
      1. EBRU_ADMIN_USER ile eşleşen hesap — HER ZAMAN yönetici,
         yetkisi panelden alınamıyor.
      2. Veritabanındaki `yonetici` bayrağı — panelden verilip alınıyor.

    Birinci madde kilitlenmeye karşı sigorta: panelden herkesin yetkisi
    alınsa bile o hesapla girilebiliyor. Aksi halde düzeltmenin tek yolu
    sunucuya SSH ile bağlanıp veritabanını elle düzenlemek olurdu.
    """
    if _kurucu_yonetici_mi(kullanici_adi):
        return True
    return kullanicilar.yonetici_mi(kullanici_adi)


def _gunluk_hak(kullanici):
    """Bu kullanıcı için geçerli günlük üretim hakkı.

    Kişisel hak NULL ise genel değer geçerli. 0 geçerli bir değer
    (üretimi kapatır), bu yüzden "or" ile varsayılana düşülmüyor.
    """
    if not kullanici:
        return DAILY_LIMIT
    kisisel = kullanici.get("gunluk_limit")
    return DAILY_LIMIT if kisisel is None else kisisel


# E-postasını onaylamamış hesap üretim yapamaz (karar: 19 Ağustos 2026).
#
# Gerekçe kapasite: tek bir GPU var ve üretimler sırayla çalışıyor.
# Doğrulanmamış hesapların kuyruğa girmesi yalnızca onları değil,
# sıradaki herkesi bekletir.
#
# Yönetici bu denetime takılmıyor; göç sırasında doğrulanmış olarak
# işaretleniyor ve e-postası hiç olmayacak.
DOGRULAMA_MESAJI = (
    "Üretim yapabilmek için e-posta adresinizi onaylamanız gerekiyor."
)


def _dogrulanmamis_mi(kullanici):
    """Hesap üretimden men edilmeli mi. Döner: True/False."""
    if not kullanici:
        return False
    return not kullanici.get("eposta_dogrulandi")


def _yonetici_yetkili():
    """
    İzleme uçlarına erişim iki yoldan verilebiliyor:
      1. Yönetici hesabıyla açılmış bir oturum (uygulama bunu kullanır)
      2. Kayıt anahtarı (komut satırı ve tarayıcıdan hızlı erişim için)
    """
    kullanici = oturum_kullanicisi()
    if kullanici and _yonetici_mi(kullanici["kullanici_adi"]):
        return True

    # Anahtar YALNIZCA başlıkta kabul ediliyor. URL ?token= yolu
    # kaldırıldı: sorgu dizesi sunucu günlüğüne, tarayıcı geçmişine ve
    # dış kaynak yüklendiğinde Referer başlığına düşüyordu. Ayrıca artık
    # REGISTER_TOKEN değil, ondan ayrı olan ADMIN_TOKEN ile eşleşiyor.
    verilen = request.headers.get("X-Admin-Token", "")
    return bool(verilen) and secrets.compare_digest(str(verilen), ADMIN_TOKEN)


@app.route("/stats", methods=["GET"])
def stats():
    """Son istekler ve kullanım özeti (JSON)."""
    if not _yonetici_yetkili():
        return jsonify({
            "status": "error",
            "message": "Yetkisiz",
        }), 403

    with _gecmis_lock:
        gecmis = list(_gecmis)
        sayaclar = dict(_sayaclar)

    # Hesaplı kullanıcılar veritabanından, hesapsız istekler (web
    # sitesi) bellekten geliyor.
    cihazlar = kullanicilar.bugunku_kullanicilar()

    bugun = time.strftime("%Y-%m-%d")
    with _usage_lock:
        cihazlar += [
            {"kimlik": k, "bugun": v["sayi"]}
            for k, v in _usage.items()
            if isinstance(v, dict) and v.get("gun") == bugun
        ]
    cihazlar.sort(key=lambda c: c["bugun"], reverse=True)

    with _queue_lock:
        bekleyen = _queue_length

    with _jobs_lock:
        aktif_isler = sum(
            1 for j in _jobs.values()
            if j["status"] in ("queued", "running")
        )

    return jsonify({
        "status": "success",
        "sayaclar": sayaclar,
        "kuyruk": bekleyen,
        "aktif_isler": aktif_isler,
        "gunluk_limit": DAILY_LIMIT,
        "cihazlar": cihazlar,
        "istekler": list(reversed(gecmis)),
    })


@app.route("/admin/kullanicilar", methods=["GET"])
def admin_kullanicilar():
    """Kayıtlı kullanıcılar ve kullanım sayıları (yönetim paneli)."""
    if not _yonetici_yetkili():
        return jsonify({"status": "error", "message": "Yetkisiz"}), 403

    liste = kullanicilar.hepsi()
    for k in liste:
        # Veritabanı bayrağı ile ortam değişkenindeki hesap birleştiriliyor.
        kurucu = _kurucu_yonetici_mi(k["kullanici_adi"])
        k["yonetici"] = bool(k.get("yonetici")) or kurucu
        # Panel bu hesabın yetki düğmesini kapalı gösteriyor.
        k["kurucu_yonetici"] = kurucu
        # Kişisel hak yoksa hangi değerin geçerli olduğunu da bildir.
        k["gecerli_limit"] = (
            DAILY_LIMIT if k.get("gunluk_limit") is None else k["gunluk_limit"]
        )

    return jsonify({
        "status": "success",
        "kullanicilar": liste,
        "gunluk_limit": DAILY_LIMIT,
    })


def _yonetim_hedefi(kullanici_id):
    """Yönetim işlemi için hedef kullanıcıyı bulur.

    Döner: (kullanici, hata_cevabi). Hata varsa kullanici None.
    """
    hedef = kullanicilar.kullanici_getir(kullanici_id)
    if not hedef:
        return None, (jsonify({
            "status": "error",
            "message": "Kullanıcı bulunamadı.",
        }), 404)
    return hedef, None


@app.route("/admin/kullanicilar/<int:kullanici_id>/yonetici", methods=["POST"])
def admin_yonetici_ayarla(kullanici_id):
    """Yönetici yetkisini verir ya da alır."""
    if not _yonetici_yetkili():
        return jsonify({"status": "error", "message": "Yetkisiz"}), 403

    hedef, hata = _yonetim_hedefi(kullanici_id)
    if hata:
        return hata

    data = request.get_json(silent=True) or {}
    deger = bool(data.get("yonetici"))

    # Kurucu yöneticinin yetkisi alınamaz: panelden herkesin yetkisi
    # alınıp kimsenin giremediği bir duruma düşmeyi engelliyor.
    if _kurucu_yonetici_mi(hedef["kullanici_adi"]) and not deger:
        return jsonify({
            "status": "error",
            "message": (
                f"{hedef['kullanici_adi']} kurucu yönetici; yetkisi "
                "panelden alınamaz. Bu, paneli tamamen kaybetmeyi önlüyor."
            ),
        }), 400

    try:
        kullanicilar.yonetici_ayarla(kullanici_id, deger)
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"🛡️  Yetki {'verildi' if deger else 'alındı'}: "
          f"{hedef['kullanici_adi']}")
    return jsonify({"status": "success", "yonetici": deger})


@app.route("/admin/kullanicilar/<int:kullanici_id>/limit", methods=["POST"])
def admin_limit_ayarla(kullanici_id):
    """Kişiye özel günlük üretim hakkını ayarlar."""
    if not _yonetici_yetkili():
        return jsonify({"status": "error", "message": "Yetkisiz"}), 403

    hedef, hata = _yonetim_hedefi(kullanici_id)
    if hata:
        return hata

    data = request.get_json(silent=True) or {}
    deger = data.get("limit")
    # Boş gönderilirse kişisel hak kalkar, genel değer geçerli olur.
    if deger in ("", None):
        deger = None

    try:
        kullanicilar.limit_ayarla(kullanici_id, deger)
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"🎚️  Günlük hak: {hedef['kullanici_adi']} → "
          f"{'genel' if deger is None else deger}")
    return jsonify({
        "status": "success",
        "gunluk_limit": deger,
        "gecerli_limit": DAILY_LIMIT if deger is None else deger,
    })


@app.route("/admin/kullanicilar/<int:kullanici_id>", methods=["DELETE"])
def admin_kullanici_sil(kullanici_id):
    """Hesabı ve ona bağlı bütün kayıtları siler."""
    if not _yonetici_yetkili():
        return jsonify({"status": "error", "message": "Yetkisiz"}), 403

    hedef, hata = _yonetim_hedefi(kullanici_id)
    if hata:
        return hata

    if _kurucu_yonetici_mi(hedef["kullanici_adi"]):
        return jsonify({
            "status": "error",
            "message": f"{hedef['kullanici_adi']} kurucu yönetici; silinemez.",
        }), 400

    # Kendi hesabını silmek oturumu anında geçersiz kılar ve panelden
    # düşersin. Kaza eseri olmasın diye engelleniyor.
    kendisi = oturum_kullanicisi()
    if kendisi and kendisi["id"] == kullanici_id:
        return jsonify({
            "status": "error",
            "message": "Kendi hesabınızı panelden silemezsiniz.",
        }), 400

    try:
        kullanicilar.sil(kullanici_id)
    except kullanicilar.KayitHatasi as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    print(f"🗑️  Hesap silindi: {hedef['kullanici_adi']}")
    return jsonify({"status": "success"})


@app.route("/admin", methods=["GET"])
def admin():
    """
    Yönetim paneli.

    Sayfanın kendisi yetki istemiyor: tarayıcı adres çubuğundan
    gidilirken Authorization başlığı gönderilemiyor, oturum anahtarı
    ise tarayıcıda saklı. Sayfa boş bir kabuk; bütün veriler
    /stats, /admin/jobs ve /admin/kullanicilar uçlarından geliyor ve
    o uçlar yönetici yetkisi istiyor. Yetkisiz biri sayfayı açsa da
    hiçbir veri göremez.
    """
    return render_template("admin.html", token=request.args.get("token", ""))


@app.route("/health", methods=["GET"])
def health():
    """
    Uygulamanın açılışta çağırdığı durum ucu. Kullanıcıya
    'sunucuya bağlanılamadı' yerine anlamlı bir mesaj göstermeyi sağlar.
    """
    with _state_lock:
        durum = dict(_state)

    aktif = "colab" if durum["remote_ok"] else (
        "local" if durum["local_ok"] else None
    )

    with _queue_lock:
        bekleyen = _queue_length

    return jsonify({
        "status": "success",
        "ready": aktif is not None,
        "active_source": aktif,
        "colab_registered": durum["remote_url"] is not None,
        "colab_ok": durum["remote_ok"],
        "local_ok": durum["local_ok"],
        "last_check": durum["last_check"],
        "queue_length": bekleyen,
        "daily_limit": DAILY_LIMIT,
        "message": (
            "Üretim için hazır" if aktif
            else "Görsel üretim sunucusu şu anda kapalı"
        ),
    })
# =====================================
# WEB SAYFALARI
# =====================================
@app.route("/")
def home():
    return render_template(
        "index.html"
    )
@app.route("/nasil-calisir")
def nasil_calisir():

    return render_template(
        "nasil_calisir.html"
    )
@app.route("/ornekler")
def ornekler():

    return render_template(
        "ornekler.html"
    )
@app.route("/proje-ekibi")
def proje_ekibi():

    return render_template(
        "proje_ekibi.html"
    )


@app.route("/iletisim")
def iletisim():
    """İletişim sayfası: e-posta ve GitHub bağlantıları."""
    return render_template("iletisim.html")


@app.route("/giris")
def giris_sayfasi():
    """Site üzerinden hesap açma ve giriş."""
    return render_template("giris.html")


# Mobil uygulamanın indirileceği dosya. Derlenen APK buraya
# kopyalanıyor ki site sabit bir yoldan sunabilsin.
APK_KLASORU = os.path.join(WEB_KLASORU, "static", "indir")
APK_DOSYA = "ebru-ai.apk"


@app.route("/indir")
def indir_sayfasi():
    """Mobil uygulama tanıtım ve indirme sayfası."""
    yol = os.path.join(APK_KLASORU, APK_DOSYA)
    var_mi = os.path.exists(yol)
    boyut = round(os.path.getsize(yol) / (1024 * 1024), 1) if var_mi else 0

    return render_template(
        "indir.html",
        apk_var=var_mi,
        apk_boyut=boyut,
    )


@app.route("/apk")
def apk_indir():
    """APK dosyasını indirir."""
    yol = os.path.join(APK_KLASORU, APK_DOSYA)
    if not os.path.exists(yol):
        return "Uygulama dosyası henüz yüklenmedi.", 404

    return send_from_directory(
        APK_KLASORU,
        APK_DOSYA,
        as_attachment=True,
        download_name="EbruAI.apk",
    )
# =====================================
# GÖRSEL ÜRETME API
# =====================================
# SDXL'in eğitildiği en/boy oranlarına yakın, 6 GB VRAM'de taşma
# yapmadan üretilebilen ölçüler.
#
# NOT: Daha önce 832x1216 kullanılıyordu. LoRA 1024px'de eğitildiği
# için kalite açısından doğruydu ama 6 GB karta sığmayıp modeli sistem
# belleğine taşıtıyor, adım süresi ~16 saniyeye çıkıyordu (görsel başına
# ~6,5 dakika). Piksel sayısı düşürülerek kullanılabilir hale getirildi.
# Ölçüm sonucu: 6 GB kartta 0,88 MP (768x1152) bile VRAM'i doldurup
# sistem belleğine taşmaya yol açıyor ve adım süresi ~18 saniyeye
# çıkıyor. Orijinal 768x768 (0,59 MP) sığdığı için hızlıydı.
# Aşağıdaki ölçüler o piksel bandına yakın tutuldu.
SUPPORTED_SIZES = (
    (704, 1024),    # dikey — telefon duvar kağıdı için varsayılan (0,72 MP)
    (640, 1024),    # daha uzun dikey (0,66 MP)
    (768, 768),     # kare (0,59 MP)
    (1024, 704),    # yatay
)

DEFAULT_SIZE = (704, 1024)

# =====================================
# HIZLANDIRMA: SDXL-LIGHTNING
# =====================================
# 6 GB VRAM'de SDXL zaten kartı doldurduğu için adım başına ~13-18 sn
# harcanıyordu. Lightning LoRA, 16 yerine 4 adımda üretim yapmayı
# sağlayarak süreyi yaklaşık dörtte bire indiriyor.
#
# Lightning kendine özgü ayarlar ister:
#   - çok düşük CFG (1.0-2.0), yüksek CFG görüntüyü yakar
#   - Euler örnekleyici + sgm_uniform zamanlayıcı
#   - LoRA'nın prompt'a eklenmesi
LIGHTNING_LORA = "sdxl_lightning_4step_lora"

# LoRA klasörü A1111'in kurulumuna bağlı. Sunucu başka bir makinede
# çalıştığında yerleşim değiştiği için EBRU_LORA_DIR ile verilebilir.
LORA_KLASORU = os.environ.get("EBRU_LORA_DIR") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "stable-diffusion-webui", "models", "Lora",
)

_lightning_path = os.path.join(
    LORA_KLASORU,
    f"{LIGHTNING_LORA}.safetensors",
)

# Dosya varsa otomatik devreye girer.
#
# DIKKAT — uzak uretimde bu denetim tek basina yaniltici. Site GPU'dan
# ayri bir makinede calistiginda LoRA dosyasi burada degil, A1111'in
# yanindadir. Diske bakan eski denetim o durumda "yok" der, hizlandirma
# sessizce kapanir: adim 4 yerine 16, CFG 1.8 yerine 8.5 olur. Yavaslama
# bir yana, Lightning LoRA'si yuksek CFG ile goruntuyu yakar; yani hata
# kendini cokme olarak degil bozuk cikti olarak gosterir.
#
# Bu yuzden EBRU_LIGHTNING artik iki yonlu:
#   "1" -> dosyaya bakmadan ac (GPU'nun oldugu makinede var kabul edilir)
#   "0" -> kapat
#   verilmezse -> eski davranis: dosya varsa ac
_lightning_secimi = os.environ.get("EBRU_LIGHTNING")

if _lightning_secimi == "1":
    LIGHTNING_ENABLED = True
elif _lightning_secimi == "0":
    LIGHTNING_ENABLED = False
else:
    LIGHTNING_ENABLED = os.path.exists(_lightning_path)

if LIGHTNING_ENABLED:
    # Ölçüm: 4 adım ~94 sn, 6 adım ~116 sn. LoRA zaten 4 adım için
    # eğitildiği için kalite farkı gözle görülmüyor.
    STEPS = int(os.environ.get("EBRU_STEPS", "4"))
    CFG_SCALE = float(os.environ.get("EBRU_CFG", "1.8"))
    SAMPLER = os.environ.get("EBRU_SAMPLER", "Euler")
    SCHEDULER = os.environ.get("EBRU_SCHEDULER", "SGM Uniform")
else:
    STEPS = int(os.environ.get("EBRU_STEPS", "16"))
    CFG_SCALE = float(os.environ.get("EBRU_CFG", "8.5"))
    SAMPLER = os.environ.get("EBRU_SAMPLER", "DPM++ 2M")
    SCHEDULER = os.environ.get("EBRU_SCHEDULER", "Karras")


def pick_size(data):
    """
    İstenen en/boy oranına en yakın desteklenen çözünürlüğü seçer.
    Uygulama ekran oranını gönderirse duvar kağıdı kırpılmadan oturur.
    """
    try:
        oran = data.get("aspect_ratio")
        if oran is None:
            genislik = data.get("width")
            yukseklik = data.get("height")
            if not genislik or not yukseklik:
                return DEFAULT_SIZE
            oran = float(genislik) / float(yukseklik)
        oran = float(oran)
        if oran <= 0:
            return DEFAULT_SIZE
    except (TypeError, ValueError):
        return DEFAULT_SIZE

    return min(
        SUPPORTED_SIZES,
        key=lambda boyut: abs((boyut[0] / boyut[1]) - oran)
    )


def perform_generation(data, kimlik, ip="-", kullanici=None,
                       job_id=None, on_start=None):
    """
    Üretimi çalıştırır ve sonucu istek geçmişine yazar.
    Döner: (govde_sozlugu, http_kodu)
    """
    baslangic = time.time()
    govde, kod = _uretimi_calistir(
        data, kimlik, kullanici, job_id, on_start
    )

    istek_kaydet(
        kimlik=kimlik,
        ip=ip,
        prompt=data.get("prompt"),
        durum=govde.get("status", "error"),
        sure=time.time() - baslangic,
        kaynak=govde.get("source"),
        mesaj=(
            govde.get("message")
            if govde.get("status") != "success" else None
        ),
    )
    return govde, kod


def _uretimi_calistir(data, kimlik, kullanici=None,
                      job_id=None, on_start=None):
    """
    Asıl üretim işi. Hem senkron /generate ucundan hem de asenkron
    iş kuyruğundan çağrılır.

    Flask'a özgü bir şey döndürmez ki arka plan thread'inden de
    çağrılabilsin.
    """
    print("\n======================")
    print("🔔 YENİ İSTEK")
    print("======================")
    try:
        # ------------------------------
        # Kullanıcı verisini al
        # ------------------------------
        user_prompt = data.get(
            "prompt"
        )
        print(
            "📥 Kullanıcı:",
            user_prompt
        )
        if not user_prompt or not str(user_prompt).strip():
            return {
                "status": "error",
                "message": "Boş prompt gönderildi",
            }, 400
        # ------------------------------
        # KAYNAK KONTROLÜ
        # ------------------------------
        # Üretim sunucusu kapalıysa prompt/çeviri işine hiç girilmez.
        if get_active_url()[0] is None:
            # Durum bayatlamış olabilir, bir kez tazeleyip tekrar bak.
            refresh_health()
            if get_active_url()[0] is None:
                print("⛔ Hiçbir üretim sunucusu ayakta değil")
                return {
                    "status": "error",
                    "message": (
                        "Görsel üretim sunucusu şu anda kapalı. "
                        "Lütfen biraz sonra tekrar deneyin."
                    ),
                }, 503
        # ------------------------------
        # E-POSTA ONAYI
        # ------------------------------
        # /jobs bunu kuyruğa almadan önce zaten denetliyor. Burası
        # senkron /generate ucunu ve doğrudan çağrıları kapsıyor;
        # denetim tek yerde bırakılırsa öbür yol açık kalırdı.
        if _dogrulanmamis_mi(kullanici):
            print(f"✉️  Onaysız hesap üretim denedi: {kimlik}")
            return {
                "status": "error",
                "message": DOGRULAMA_MESAJI,
                "email_verified": False,
            }, 403

        # ------------------------------
        # KULLANIM SINIRI
        # ------------------------------
        izin_var, sinir_mesaji, bekleme = check_rate_limit(
            kimlik, kullanici
        )
        if not izin_var:
            print(f"🚦 Sınır aşıldı ({kimlik}): {sinir_mesaji}")
            return {
                "status": "error",
                "message": sinir_mesaji,
                "retry_after": bekleme,
            }, 429
        # ------------------------------
        # YENİ PROMPT ENGINE
        # ------------------------------
        # Kullanıcı kendi rengini seçtiyse hazır palet yerine o geçerli.
        # Liste kısa tutuluyor: ebruda iki üç renk yeterli, fazlası
        # prompt'u seyreltiyor.
        ozel_renkler = data.get("colors") or data.get("renkler") or []
        if isinstance(ozel_renkler, str):
            ozel_renkler = [ozel_renkler]
        ozel_renkler = [str(r) for r in ozel_renkler][:3]

        translated_prompt = enrich_prompt(
            user_prompt, ozel_renkler
        )
        # ------------------------------
        # LORA + MODEL PROMPT
        # ------------------------------
        nesne_var = has_object(user_prompt)

        # Kullanıcı desen yoğunluğunu ayarladıysa o belirler; aksi
        # halde paletin kendi ağırlığı geçerli (web sitesi bu yoldan
        # geliyor ve kaydırıcı göndermiyor).
        if data.get("intensity") is not None:
            lora_weight = intensity_to_lora(data["intensity"])
            print(
                f"🎚️ Desen yoğunluğu %{data['intensity']} → "
                f"LoRA {lora_weight}"
            )
        else:
            lora_weight = get_lora_weight(user_prompt)

        # Nesne istendiğinde ağırlığa tavan konuyor: ölçümde 0.60'a
        # kadar nesne net kalıyor, üstünde doku onu yutuyor. Kullanıcı
        # yoğunluğu sonuna çekse bile istediği nesneyi kaybetmesin.
        if nesne_var and lora_weight > NESNE_LORA_TAVANI:
            print(
                f"🐈 Nesne istendi, LoRA {lora_weight} → {NESNE_LORA_TAVANI}"
            )
            lora_weight = NESNE_LORA_TAVANI

        lora_tag = f"<lora:ebru_projesi-01:{lora_weight}>"

        # Hızlandırıcı LoRA varsa ebru LoRA'sının yanına eklenir.
        if LIGHTNING_ENABLED:
            lora_tag = f"{lora_tag} <lora:{LIGHTNING_LORA}:1>"

        final_prompt = (
            f"{translated_prompt}, "
            f"{improve_prompt_weight(lora_tag, nesne_var)}"
        )

        print(
            "\n🚀 Stable Diffusion Prompt:"
        )
        print(
            final_prompt
        )
        # ------------------------------
        # ÇÖZÜNÜRLÜK VE SEED
        # ------------------------------
        genislik, yukseklik = pick_size(data)

        # Seed gönderilirse aynı/benzer tasarım yeniden üretilebilir.
        try:
            seed = int(data.get("seed", -1))
        except (TypeError, ValueError):
            seed = -1
        if seed < 0:
            seed = random.randint(0, 2**31 - 1)

        # ------------------------------
        # STABLE DIFFUSION AYARLARI
        # ------------------------------
        payload = {
            "prompt":
            final_prompt,
            "negative_prompt":
            (
                f"{ADVANCED_NEGATIVE}, {NESNE_NEGATIF}"
                if nesne_var else ADVANCED_NEGATIVE
            ),
            "steps":
            STEPS,
            "cfg_scale":
            CFG_SCALE,
            "width":
            genislik,
            "height":
            yukseklik,
            "seed":
            seed,
            "sampler_name":
            SAMPLER,
            "scheduler":
            SCHEDULER,
            "save_images":
            SAVE_IMAGES,
            "override_settings":
            {
                "sd_model_checkpoint":
                "sd_xl_base_1.0"
            },
            "override_settings_restore_afterwards":
            False
        }
        # ------------------------------
        # AKTİF KAYNAK
        # ------------------------------
        # Kaynak arka planda zaten biliniyor; burada deneme-yanılma yok.
        active_url, kaynak = get_active_url()

        if active_url is None:
            # Prompt hazırlanırken sunucu düşmüş olabilir.
            return {
                "status": "error",
                "message": (
                    "Görsel üretim sunucusu şu anda kapalı. "
                    "Lütfen biraz sonra tekrar deneyin."
                ),
            }, 503

        print(f"✅ Kaynak: {kaynak} → {active_url}")

        # ------------------------------
        # SIRAYA GİR VE ÜRET
        # ------------------------------
        # Tek GPU olduğu için aynı anda yalnızca bir üretim çalışır.
        try:
            with gpu_slot():
                # Sıra beklerken iptal edilmiş olabilir. GPU'yu almış
                # olsak bile burada durursak boşa üretim yapılmıyor.
                if job_id and _iptal_edildi_mi(job_id):
                    print(f"🛑 Sırası gelen iş iptalli, üretim yapılmadı")
                    return {
                        "status": "error",
                        "message": "Üretim iptal edildi.",
                    }, 409

                if on_start:
                    on_start()

                # Aynı adres birkaç kez deneniyor: tünelin tek bir
                # tökezlemesi bütün üretimi düşürmemeli. GPU yuvası
                # denemeler boyunca elde tutuluyor, araya başka iş
                # girmesin.
                response = None
                son_hata = None

                for deneme in range(1, URETIM_DENEME + 1):
                    try:
                        response = http.post(
                            f"{active_url}/sdapi/v1/txt2img",
                            json=payload,
                            timeout=GENERATE_TIMEOUT
                        )
                        if "text/html" in response.headers.get(
                            "Content-Type", ""
                        ):
                            raise Exception(
                                "Sunucu arayüz sayfası döndürdü"
                            )
                        son_hata = None
                        break
                    except requests.exceptions.Timeout as e:
                        # Zaman aşımında TEKRAR DENENMİYOR. İstek zaten
                        # GENERATE_TIMEOUT kadar sürdü; üç kez denemek
                        # işi on beş dakika askıda bırakırdı. Bu, tünel
                        # tökezlemesi değil, GPU'nun yetişememesi.
                        son_hata = e
                        response = None
                        print(f"⚠️ {kaynak} zaman aşımı, tekrar denenmiyor")
                        break
                    except Exception as e:
                        son_hata = e
                        response = None
                        print(
                            f"⚠️ {kaynak} denemesi "
                            f"{deneme}/{URETIM_DENEME} başarısız: {e}"
                        )
                        if deneme < URETIM_DENEME:
                            # Sıradaki denemeden önce iptal edilmiş
                            # olabilir; boşa üretim yapılmasın.
                            if job_id and _iptal_edildi_mi(job_id):
                                print("🛑 Denemeler sırasında iptal edildi")
                                return {
                                    "status": "error",
                                    "message": "Üretim iptal edildi.",
                                }, 409
                            time.sleep(URETIM_DENEME_BEKLEME * deneme)

                if son_hata is not None:
                    # Denemeler tükendi: adres gerçekten cevap vermiyor.
                    if kaynak != "colab":
                        raise son_hata

                    with _state_lock:
                        _state["remote_ok"] = False

                    yedek_url, yedek_kaynak = get_active_url()
                    if yedek_url is None:
                        raise Exception(
                            "Üretim sunucusuna ulaşılamadı"
                        )

                    print(f"🔁 Yedeğe geçiliyor: {yedek_kaynak}")
                    response = http.post(
                        f"{yedek_url}/sdapi/v1/txt2img",
                        json=payload,
                        timeout=GENERATE_TIMEOUT
                    )
                    # Yedek de arayüz sayfası dönebiliyor. Denetim
                    # asıl yolda vardı, burada yoktu: HTML gövdesi
                    # geçerli sayılıp .json() aşamasında anlamsız bir
                    # çözümleme hatasına dönüşüyordu.
                    if "text/html" in response.headers.get(
                        "Content-Type", ""
                    ):
                        raise Exception(
                            "Yedek sunucu arayüz sayfası döndürdü"
                        )
                    kaynak = yedek_kaynak
        except KuyrukDolu:
            refund_quota(kimlik, kullanici)
            print("🚧 Kuyruk dolu, istek reddedildi")
            return {
                "status": "error",
                "message": (
                    "Şu anda çok yoğunluk var. "
                    "Lütfen birkaç dakika sonra tekrar deneyin."
                ),
            }, 429
        except KuyrukZamanAsimi:
            refund_quota(kimlik, kullanici)
            print("⌛ Sırada bekleme süresi doldu")
            return {
                "status": "error",
                "message": (
                    "Sıra beklerken süre doldu. "
                    "Lütfen tekrar deneyin."
                ),
            }, 503
        except Exception:
            refund_quota(kimlik, kullanici)
            raise
        # ------------------------------
        # SONUÇ
        # ------------------------------
        if response.status_code == 200:
            result = response.json()
            image_base64 = (
                result["images"][0]
            )
            image_url = (
                "data:image/png;base64,"
                +
                image_base64
            )
            return {
                "status": "success",
                "message": "Eser başarıyla oluşturuldu",
                "prompt": final_prompt,
                "image": image_url,
                "seed": seed,
                "width": genislik,
                "height": yukseklik,
                "source": kaynak,
            }, 200
        else:
            refund_quota(kimlik, kullanici)
            return {
                "status": "error",
                "message": response.text,
            }, 502
    except Exception as e:
        print(
            "❌ HATA:",
            e
        )
        return {
            "status": "error",
            "message": str(e),
        }, 500


# =====================================
# SENKRON ÜRETİM UCU (web sitesi kullanıyor)
# =====================================
@app.route("/generate", methods=["POST"])
def generate_image():
    """
    Sonucu bekleyerek döndürür. Web arayüzü bunu kullanıyor.
    Mobil uygulama, uzun süren isteklerde tünel zaman aşımına
    takılmamak için asenkron uçları kullanmalı.
    """
    data = request.get_json(silent=True) or {}
    govde, kod = perform_generation(data, client_id(), client_ip())
    return jsonify(govde), kod


# =====================================
# ASENKRON ÜRETİM (İŞ KUYRUĞU)
# =====================================
# Üretim 90 saniyeyi aşabiliyor; Cloudflare gibi tüneller ise ~100
# saniyede bağlantıyı kesiyor. Uzun HTTP bağlantısı kurmamak için
# istek hemen bir iş numarasıyla yanıtlanır, sonuç ayrı uçtan sorulur.

JOB_TTL = int(os.environ.get("EBRU_JOB_TTL", "900"))   # saniye

_jobs = {}
_jobs_lock = threading.Lock()


def _job_temizle():
    """Süresi dolmuş işleri bellekten siler."""
    simdi = time.time()
    with _jobs_lock:
        for anahtar in [
            k for k, v in _jobs.items()
            if simdi - v["updated"] > JOB_TTL
        ]:
            del _jobs[anahtar]


def _iptal_edildi_mi(job_id):
    with _jobs_lock:
        job = _jobs.get(job_id)
        return bool(job and job.get("cancelled"))


def _job_calistir(job_id, data, kimlik, ip, kullanici=None):
    """Arka planda üretimi yapıp sonucu iş kaydına yazar."""
    # Sıra beklerken iptal edilmiş olabilir.
    if _iptal_edildi_mi(job_id):
        _iptal_sonucu_yaz(job_id, kullanici)
        return

    def _basladi():
        """GPU sırası bu işe geldiğinde çağrılıyor."""
        with _jobs_lock:
            if job_id in _jobs:
                _jobs[job_id]["status"] = "running"
                _jobs[job_id]["updated"] = time.time()

    govde, kod = perform_generation(
        data, kimlik, ip, kullanici, job_id, _basladi
    )

    # Üretim sırasında iptal edildiyse sonucu kullanıcıya verme.
    if _iptal_edildi_mi(job_id):
        _iptal_sonucu_yaz(job_id, kullanici)
        return

    with _jobs_lock:
        if job_id not in _jobs:
            return  # iş bu arada süresi dolup silinmiş
        _jobs[job_id]["status"] = (
            "done" if kod == 200 else "error"
        )
        _jobs[job_id]["result"] = govde
        _jobs[job_id]["code"] = kod
        _jobs[job_id]["updated"] = time.time()


def _iptal_sonucu_yaz(job_id, kullanici=None):
    """İptal edilen işi sonuçlandırır ve kullanılan hakkı geri verir."""
    if kullanici:
        kullanicilar.kullanim_azalt(kullanici["id"])

    with _jobs_lock:
        if job_id not in _jobs:
            return
        _jobs[job_id]["status"] = "error"
        _jobs[job_id]["result"] = {
            "status": "error",
            "message": "Bu üretim yönetici tarafından iptal edildi.",
        }
        _jobs[job_id]["code"] = 409
        _jobs[job_id]["updated"] = time.time()

    print(f"🛑 İş iptal edildi: {job_id}")


@app.route("/admin/jobs", methods=["GET"])
def admin_jobs():
    """Bekleyen ve süren işleri listeler."""
    if not _yonetici_yetkili():
        return jsonify({"status": "error", "message": "Yetkisiz"}), 403

    simdi = time.time()
    with _jobs_lock:
        isler = [
            {
                "job_id": jid,
                "durum": j["status"],
                "kimlik": j.get("kimlik", "-"),
                "gecen": round(simdi - j["created"], 1),
                "iptal": bool(j.get("cancelled")),
            }
            for jid, j in _jobs.items()
            if j["status"] in ("queued", "running")
        ]

    isler.sort(key=lambda i: i["gecen"], reverse=True)
    return jsonify({"status": "success", "isler": isler})


@app.route("/admin/jobs/<job_id>/cancel", methods=["POST"])
def admin_cancel_job(job_id):
    """
    Bir üretimi iptal eder.

    Sıradaki iş hiç başlamadan düşer. Süren iş için A1111'e kesme
    komutu gönderilir; GPU boşalır ve sıradaki isteğe geçilir.
    """
    if not _yonetici_yetkili():
        return jsonify({"status": "error", "message": "Yetkisiz"}), 403

    with _jobs_lock:
        job = _jobs.get(job_id)
        if job is None:
            return jsonify({
                "status": "error",
                "message": "İş bulunamadı",
            }), 404

        if job["status"] not in ("queued", "running"):
            return jsonify({
                "status": "error",
                "message": "Bu iş zaten tamamlanmış",
            }), 409

        job["cancelled"] = True
        suruyor = job["status"] == "running"

    # Süren üretimi GPU tarafında kes.
    if suruyor:
        active_url, _ = get_active_url()
        if active_url:
            try:
                probe_http.post(
                    f"{active_url}/sdapi/v1/interrupt",
                    timeout=HEALTH_TIMEOUT,
                )
            except Exception as e:
                print("⚠️ Kesme komutu gönderilemedi:", e)

    return jsonify({"status": "success", "job_id": job_id})


@app.route("/jobs", methods=["POST"])
def create_job():
    """Üretim işini kuyruğa alır ve hemen iş numarası döner."""
    _job_temizle()

    # Mobil uygulama giriş yapmış olmalı: günlük hak hesaba bağlı ve
    # kimin ne ürettiği izlenebilir olsun.
    kullanici = oturum_kullanicisi()
    if not kullanici:
        return jsonify({
            "status": "error",
            "message": "Oturum açmanız gerekiyor",
        }), 401

    # Kuyruğa alınmadan önce bakılıyor: iş numarası verip sonra
    # reddetmek kullanıcıyı boşuna bekletirdi.
    if _dogrulanmamis_mi(kullanici):
        return jsonify({
            "status": "error",
            "message": DOGRULAMA_MESAJI,
            "email_verified": False,
        }), 403

    # Günlük hak da burada bir kez okunuyor. Asıl denetim ve sayaç
    # artışı üretim sırasında check_rate_limit'te; burası YALNIZCA
    # okuma yapıyor, yoksa hak iki kez düşerdi.
    #
    # Bunun eklenme sebebi: yönetici panelden bir hesabın hakkını 0
    # yapabiliyor ("üretim kapalı"). O hesap istek attığında iş numarası
    # alıp sıraya giriyor, reddi ancak üretim sırası gelince görüyordu.
    if not _yonetici_mi(kullanici["kullanici_adi"]):
        hak = _gunluk_hak(kullanici)
        if kullanicilar.gunluk_sayi(kullanici["id"]) >= hak:
            return jsonify({
                "status": "error",
                "message": (
                    "Bu hesap için üretim kapalı."
                    if hak == 0
                    else f"Günlük {hak} üretim hakkınız doldu. "
                         "Yarın tekrar deneyebilirsiniz."
                ),
            }), 429

    data = request.get_json(silent=True) or {}
    kimlik = kullanici["kullanici_adi"]
    # İstek bağlamı thread'e taşınamaz, şimdi okunmalı.
    ip = client_ip()

    if not data.get("prompt") or not str(data["prompt"]).strip():
        return jsonify({
            "status": "error",
            "message": "Boş prompt gönderildi",
        }), 400

    job_id = secrets.token_urlsafe(12)

    with _jobs_lock:
        _jobs[job_id] = {
            "status": "queued",
            "result": None,
            "code": None,
            "kimlik": kimlik,
            "cancelled": False,
            "created": time.time(),
            "updated": time.time(),
        }

    threading.Thread(
        target=_job_calistir,
        args=(job_id, data, kimlik, ip, kullanici),
        name=f"ebru-job-{job_id}",
        daemon=True,
    ).start()

    with _queue_lock:
        bekleyen = _queue_length

    print(f"🎫 İş oluşturuldu: {job_id} (kuyruk: {bekleyen})")
    return jsonify({
        "status": "success",
        "job_id": job_id,
        "job_status": "queued",
        "queue_length": bekleyen,
    }), 202


@app.route("/jobs/<job_id>", methods=["GET"])
def get_job(job_id):
    """
    İşin durumunu döner. Bitmişse görsel de bu yanıtta gelir.
    Uygulama bunu birkaç saniyede bir sorgular.
    """
    with _jobs_lock:
        job = _jobs.get(job_id)
        if job is None:
            return jsonify({
                "status": "error",
                "message": "İş bulunamadı veya süresi doldu",
            }), 404

        durum = job["status"]
        sonuc = job["result"]
        kod = job["code"]

    # Sonuç hazırsa üretim yanıtını olduğu gibi ilet.
    if durum in ("done", "error") and sonuc is not None:
        govde = dict(sonuc)
        govde["job_status"] = durum
        return jsonify(govde), (200 if durum == "done" else kod or 500)

    # Henüz sürüyor: ilerleme bilgisi ekle.
    ilerleme = 0.0
    kalan = None
    active_url, _ = get_active_url()
    if active_url and durum == "running":
        veri = get_progress_cached(active_url)
        ilerleme = veri.get("progress", 0.0) or 0.0
        kalan = veri.get("eta_relative")

    with _queue_lock:
        bekleyen = _queue_length

    return jsonify({
        "status": "success",
        "job_status": durum,
        "progress": ilerleme,
        "eta_seconds": kalan,
        "queue_length": bekleyen,
    }), 200

    # =====================================
# GELİŞMİŞ PROMPT KALİTE AYARLARI
# =====================================
def improve_prompt_weight(prompt, nesne_var=False):
    """
    Prompt'un sonuna kalite ekleri koyar.

    Nesne istendiğinde "traditional Turkish ebru art" vurgusu
    eklenmiyor: o ifade zaten prompt'ta birkaç kez geçiyor ve nesneyi
    bastıran asıl etkenlerden biri.
    """
    if nesne_var:
        return prompt + ", (masterpiece:1.05), (high quality:1.05)"

    return (
        prompt +
        ", (traditional Turkish ebru art:1.1), "
        "(masterpiece:1.1), (high quality:1.1)"
    )
# GELİŞMİŞ NEGATIVE PROMPT
# =====================================
ADVANCED_NEGATIVE = """
bad quality,
low resolution,
blurry,
pixelated,
photorealistic,
real photo,
3d render,
plastic texture,
cartoon,
anime,
comic style,
digital painting,
wrong anatomy,
deformed object,
extra limbs,
duplicate object,
multiple subjects,
bad composition,
text,
logo,
watermark,
signature,
noise

""".replace("\n"," ")
# =====================================
# SUNUCU BAŞLATMA
# =====================================
_health_thread = None


def start_health_monitor():
    """Arka plan sağlık kontrolünü başlatır (yalnızca bir kez)."""
    global _health_thread
    if _health_thread is not None and _health_thread.is_alive():
        return
    _health_thread = threading.Thread(
        target=health_loop,
        name="ebru-health",
        daemon=True
    )
    _health_thread.start()


# Modül içe aktarıldığında da başlasın (gunicorn vb. ile çalıştırıldığında
# __main__ bloğu çalışmaz).
start_health_monitor()


# Asagidaki iki uyari eskiden yalnizca __main__ blogunda basiliyordu.
# Sunucuda uygulama gunicorn ile calisiyor ve o blok hic islemiyor; en
# kritik iki yanlis yapilandirma da tam orada sessiz kaliyordu.
if _TOKEN_AUTO_GENERATED:
    print("[UYARI] EBRU_REGISTER_TOKEN verilmedi; bu acilisa ozel")
    print("        rastgele bir anahtar uretildi. Surec her yeniden")
    print("        baslatildiginda degisecegi icin uretim makinesi")
    print("        kaydolamaz. Sunucuda mutlaka sabitle.")
    print(f"        Gecerli anahtar: {REGISTER_TOKEN}")

if not _ADMIN_TOKEN_ENV:
    print("[UYARI] EBRU_ADMIN_TOKEN verilmedi; yonetici yetkisi tunel")
    print("        kayit anahtarina dusuyor. Ikisi ayri olmali:")
    print("        birinin sizmasi digerini acmasin. ayar_yaz.bat ile")
    print("        EBRU_ADMIN_TOKEN yaz.")

if LOCAL_FALLBACK_URL is None and not LIGHTNING_ENABLED:
    print("[UYARI] Yerel GPU kapali ve Lightning hizlandirma da kapali.")
    print("        Uzak uretimde EBRU_LIGHTNING=1 verilmezse adim/CFG")
    print("        degerleri yavas ve bozuk ciktiya yol acar.")


if __name__ == "__main__":
    print("""
    ===================================
       🎨 EBRU AI SUNUCUSU BAŞLADI
    ===================================
    Türkçe Prompt Engine Aktif ✅
    Ebru Desen Sözlüğü Aktif ✅
    Ebru LoRA Aktif ✅
    """)

    if _TOKEN_AUTO_GENERATED:
        print("🔑 Kayıt anahtarı (bu açılışa özel):")
        print(f"   {REGISTER_TOKEN}")
        print("   Kalıcı yapmak için EBRU_REGISTER_TOKEN ortam")
        print("   değişkenini ayarla.\n")

    if LIGHTNING_ENABLED:
        print(f"⚡ Hizlandirma      : {LIGHTNING_LORA} aktif")
    else:
        print("⚡ Hizlandirma      : kapali (Lightning LoRA bulunamadi)")
    print(f"🎚️  Uretim ayarlari  : {STEPS} adim, CFG {CFG_SCALE}, "
          f"{SAMPLER} / {SCHEDULER}")
    print(f"💻 Yerel GPU adresi : {LOCAL_FALLBACK_URL}")
    print("📡 Colab kaydı      : POST /register-backend")
    print("❤️  Durum kontrolü   : GET  /health\n")

    start_health_monitor()

    # debug=True, Werkzeug hata ayıklayıcısını ağa açar ve uzaktan
    # kod çalıştırmaya izin verebilir. Dağıtılan bir serviste kapalı olmalı.
    hata_ayikla = os.environ.get("EBRU_DEBUG") == "1"

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=hata_ayikla,
        threaded=True
    )