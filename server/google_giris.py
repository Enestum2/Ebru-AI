"""Google ile giriş — kimlik belirtecinin doğrulanması.

NASIL ÇALIŞIYOR
---------------
Tarayıcı (ve ileride mobil uygulama) Google'dan bir **kimlik belirteci**
alıyor ve bize gönderiyor. Biz onu Google'ın açık anahtarlarıyla
doğrulayıp içindeki bilgileri okuyoruz. Google ile doğrudan konuşan
taraf istemci; bizim tek işimiz gelen belirtecin gerçek olduğunu
kanıtlamak.

Bu yaklaşımın yan faydası: aynı sunucu ucu hem siteye hem mobil
uygulamaya hizmet ediyor, çünkü ikisi de aynı biçimde belirteç üretiyor.

NEDEN tokeninfo DEĞİL
---------------------
Google'ın `tokeninfo` ucu belirteci doğrulayabiliyor ama belgelerinde
"yalnızca geliştirme ve hata ayıklama için" deniyor. Üretimde önerilen
yol, kütüphaneyle yerel doğrulama: her girişte Google'a gidip gelmiyor
ve ağ kesintisinden etkilenmiyor.

DOĞRULANAN ŞEYLER (kütüphane hepsini kendisi yapıyor)
    - imza, Google'ın açık anahtarlarıyla
    - `iss`  : accounts.google.com olmalı
    - `exp`  : süresi dolmamış olmalı
    - `aud`  : BİZİM istemci kimliğimiz olmalı

Son madde kritik: bu denetim olmadan, başka bir Google uygulaması için
üretilmiş geçerli bir belirteçle bizim sitemize girilebilirdi.

AYAR
    EBRU_GOOGLE_CLIENT_ID   Google Cloud'daki OAuth istemci kimliği.
                            Gizli değil; sayfaya da gömülüyor.
"""
import os

ISTEMCI_KIMLIGI = os.environ.get("EBRU_GOOGLE_CLIENT_ID", "").strip()

# Kütüphane isteğe bağlı: kurulu değilse Google girişi kapalı kalıyor,
# sitenin geri kalanı çalışmaya devam ediyor. Sunucuya yeni bir paket
# kurulmadan dağıtım yapıldığında site tamamen düşmesin.
try:
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests
    _KUTUPHANE_VAR = True
except ImportError:  # pragma: no cover
    _KUTUPHANE_VAR = False


class GoogleHatasi(Exception):
    """Kullanıcıya gösterilebilecek Google girişi hatası."""


def yapilandirildi_mi():
    return bool(ISTEMCI_KIMLIGI) and _KUTUPHANE_VAR


def eksik_ne():
    """Kapalıysa sebebini söyler (günlüğe yazmak için)."""
    if not _KUTUPHANE_VAR:
        return "google-auth kutuphanesi kurulu degil"
    if not ISTEMCI_KIMLIGI:
        return "EBRU_GOOGLE_CLIENT_ID ayarlanmamis"
    return None


def dogrula(belirtec):
    """Kimlik belirtecini doğrular ve içindeki bilgileri döner.

    Döner: {"sub", "eposta", "ad", "soyad"}
    Geçersizse GoogleHatasi fırlatır.
    """
    if not yapilandirildi_mi():
        raise GoogleHatasi(
            "Google ile giriş şu anda kullanılamıyor."
        )

    if not belirtec:
        raise GoogleHatasi("Google'dan kimlik bilgisi gelmedi.")

    try:
        veri = google_id_token.verify_oauth2_token(
            belirtec,
            google_requests.Request(),
            ISTEMCI_KIMLIGI,
        )
    except ValueError as hata:
        # Kütüphane imza, süre ve alıcı denetimlerinin hepsinde
        # ValueError fırlatıyor. Ayrıntı kullanıcıya gösterilmiyor;
        # saldırgana hangi denetimin takıldığını söylemenin anlamı yok.
        raise GoogleHatasi(
            "Google girişi doğrulanamadı. Lütfen tekrar dene."
        ) from hata

    # Google bu adresin sahipliğini kendisi doğrulamadıysa ona
    # dayanarak hesap açmak ya da hesap eşleştirmek güvenli değil.
    if not veri.get("email_verified"):
        raise GoogleHatasi(
            "Google hesabının e-posta adresi doğrulanmamış; "
            "bu adresle giriş yapılamıyor."
        )

    eposta = (veri.get("email") or "").strip().lower()
    if not eposta:
        raise GoogleHatasi("Google hesabında e-posta adresi bulunamadı.")

    return {
        # Kişinin değişmeyen Google kimliği. E-posta adresi
        # değişebiliyor, bu değişmiyor; eşleştirmenin dayanağı bu.
        "sub": veri["sub"],
        "eposta": eposta,
        "ad": (veri.get("given_name") or "").strip() or None,
        "soyad": (veri.get("family_name") or "").strip() or None,
    }
