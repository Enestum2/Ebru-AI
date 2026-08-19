"""E-posta gönderimi (Resend).

NEDEN SMTP DEĞİL
----------------
Site Oracle Cloud'da çalışıyor ve Oracle giden 25. portu kapatıyor.
Klasik SMTP gönderimi bu yüzden hiç çalışmaz. Resend'in HTTP API'si
port meselesini tamamen ortadan kaldırıyor: sıradan bir HTTPS isteği.

AYARLAR
-------
    EBRU_RESEND_API_KEY   Resend panelinden alınan anahtar (re_...)
    EBRU_EPOSTA_GONDEREN  Gönderen adres. Varsayılan:
                          "Ebru AI <onay@ebruai.com>"
    EBRU_SITE_URL         Bağlantılarda kullanılacak adres.
                          Varsayılan: https://ebruai.com

Anahtar verilmezse modül çökmüyor: gönderim "yapılandırılmadı" diye
başarısız oluyor ve çağıran taraf buna göre davranıyor. Kayıt akışının
posta servisi yüzünden tamamen durmasını istemiyoruz.
"""
import os

import requests

API_ADRESI = "https://api.resend.com/emails"

API_ANAHTARI = os.environ.get("EBRU_RESEND_API_KEY", "").strip()

GONDEREN = (
    os.environ.get("EBRU_EPOSTA_GONDEREN")
    or "Ebru AI <onay@ebruai.com>"
)

SITE_URL = (
    os.environ.get("EBRU_SITE_URL") or "https://ebruai.com"
).rstrip("/")

ZAMAN_ASIMI = 15

# Gönderim için ayrı bir oturum: uzun süren üretim istekleri
# havuzu meşgul ettiğinde posta gönderimi beklemesin.
_http = requests.Session()


def yapilandirildi_mi():
    """Anahtar verilmiş mi."""
    return bool(API_ANAHTARI)


def gonder(alici, konu, html, duz_metin=None):
    """Tek bir e-posta gönderir.

    Döner: (basarili_mi, hata_mesaji). Hata mesajı kullanıcıya değil
    günlüğe yazılmak için; Resend'in cevabı adres hakkında bilgi
    sızdırabilir.
    """
    if not API_ANAHTARI:
        return False, "EBRU_RESEND_API_KEY ayarlanmamis"

    govde = {
        "from": GONDEREN,
        "to": [alici],
        "subject": konu,
        "html": html,
    }
    if duz_metin:
        # Düz metin karşılığı olmayan postalar spam puanı topluyor ve
        # metin tabanlı istemcilerde boş görünüyor.
        govde["text"] = duz_metin

    try:
        cevap = _http.post(
            API_ADRESI,
            json=govde,
            headers={"Authorization": "Bearer %s" % API_ANAHTARI},
            timeout=ZAMAN_ASIMI,
        )
    except Exception as hata:
        return False, "istek gonderilemedi: %s" % hata

    if cevap.status_code in (200, 201):
        return True, None

    return False, "Resend %d: %s" % (cevap.status_code, cevap.text[:300])


# ---------------------------------------------------------------
# Doğrulama postası
# ---------------------------------------------------------------
def dogrulama_baglantisi(token):
    return "%s/dogrula/%s" % (SITE_URL, token)


def dogrulama_postasi_gonder(alici, ad, token):
    """Hesap doğrulama bağlantısını yollar."""
    baglanti = dogrulama_baglantisi(token)
    selam = ("Merhaba %s," % ad) if ad else "Merhaba,"

    # Şablon bilerek sade ve tek dosyada: harici CSS ve görsel
    # kullanılmıyor, çünkü e-posta istemcilerinin çoğu ikisini de
    # engelliyor. Satır içi stil en güvenli yol.
    html = """
<div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;
            background:#0b1220;padding:32px 16px;">
  <div style="max-width:520px;margin:0 auto;background:#111a2e;
              border:1px solid rgba(255,255,255,0.08);border-radius:14px;
              padding:32px;color:#e6e9f0;">
    <p style="margin:0 0 8px;font-size:13px;letter-spacing:2px;
              text-transform:uppercase;color:#c9a227;">Ebru AI</p>
    <h1 style="margin:0 0 16px;font-size:22px;color:#ffffff;">
      E-posta adresini onayla
    </h1>
    <p style="margin:0 0 20px;font-size:15px;line-height:1.6;color:#b9c0cf;">
      %s Ebru AI hesabın oluşturuldu. Eser üretmeye başlayabilmen için
      bu adresin sana ait olduğunu doğrulaman gerekiyor.
    </p>
    <p style="margin:0 0 24px;">
      <a href="%s"
         style="display:inline-block;background:#c9a227;color:#1a1300;
                text-decoration:none;font-weight:600;font-size:15px;
                padding:12px 24px;border-radius:999px;">
        Adresimi onayla
      </a>
    </p>
    <p style="margin:0 0 8px;font-size:13px;line-height:1.6;color:#8b93a5;">
      Düğme çalışmazsa bu bağlantıyı tarayıcına yapıştır:
    </p>
    <p style="margin:0 0 24px;font-size:13px;word-break:break-all;
              color:#7aa2f7;">%s</p>
    <p style="margin:0;font-size:13px;line-height:1.6;color:#8b93a5;">
      Bağlantı 24 saat geçerli. Bu hesabı sen açmadıysan bu postayı
      yok sayabilirsin; onaylanmayan hesap üretim yapamaz.
    </p>
  </div>
</div>
""" % (selam, baglanti, baglanti)

    duz = (
        "%s\n\n"
        "Ebru AI hesabin olusturuldu. Eser uretmeye baslayabilmen icin\n"
        "e-posta adresini onaylaman gerekiyor:\n\n"
        "%s\n\n"
        "Baglanti 24 saat gecerli. Bu hesabi sen acmadiysan bu postayi\n"
        "yok sayabilirsin.\n"
    ) % (selam, baglanti)

    return gonder(alici, "Ebru AI — e-posta adresini onayla", html, duz)
