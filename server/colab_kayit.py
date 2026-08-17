"""
COLAB TARAFINA EKLENECEK KOD
============================

Bu dosyayı çalıştırmana gerek yok; içeriği Colab notebook'unda
Stable Diffusion (A1111) başladıktan SONRA çalışan bir hücreye yapıştır.

Eskiden Colab tünel adresi Google Drive'daki bir dosyaya yazılıyor,
Flask sunucusu da her istekte oradan okuyordu. Bu hem yavaştı hem de
Drive'ın indirme onay sayfası yüzünden sessizce bozulabiliyordu.
Artık Colab kendi adresini doğrudan Flask sunucusuna bildiriyor.

ÖNEMLİ: Colab'ın Flask sunucusuna ulaşabilmesi için EBRU_SERVER_URL
internetten erişilebilir bir adres olmalı. Flask yalnızca kendi
bilgisayarında çalışıyorsa Colab ona ulaşamaz — bu durumda ya Flask'ı
bir tünelin arkasına al (Cloudflare Tunnel vb.) ya da aşağıdaki
"MANUEL KAYIT" yöntemini kullan.
"""

KOD = r'''
# ---- COLAB HÜCRESİ: TÜNEL ADRESİNİ SUNUCUYA BİLDİR ----
import re
import time
import requests

# Flask sunucunun internetten erişilebilir adresi:
EBRU_SERVER_URL = "https://SENIN-FLASK-ADRESIN"

# Flask açılışta konsola yazdığı kayıt anahtarı
# (kalıcı olması için EBRU_REGISTER_TOKEN ortam değişkenini ayarla):
EBRU_REGISTER_TOKEN = "BURAYA-ANAHTARI-YAPISTIR"


def tunel_adresini_bul(bekleme=180):
    """
    A1111 başlarken ürettiği tünel adresini yakalar.
    gradio / cloudflare / ngrok adreslerini destekler.
    """
    desen = re.compile(
        r"https://[\w.-]+\."
        r"(?:gradio\.live|trycloudflare\.com|ngrok-free\.app|ngrok\.io)"
    )
    bitis = time.time() + bekleme
    while time.time() < bitis:
        try:
            with open("/content/nohup.out", "r", errors="ignore") as dosya:
                eslesme = desen.findall(dosya.read())
                if eslesme:
                    return eslesme[-1]
        except FileNotFoundError:
            pass
        time.sleep(3)
    return None


def sunucuya_kaydet(tunel_url):
    cevap = requests.post(
        f"{EBRU_SERVER_URL}/register-backend",
        json={"url": tunel_url, "token": EBRU_REGISTER_TOKEN},
        timeout=20,
    )
    print("Kayıt sonucu:", cevap.status_code, cevap.text)
    return cevap.ok


# A1111'in tünel adresini zaten biliyorsan doğrudan yaz:
# tunel = "https://xxxx.trycloudflare.com"
tunel = tunel_adresini_bul()

if tunel:
    print("Tünel bulundu:", tunel)
    sunucuya_kaydet(tunel)
else:
    print("Tünel adresi bulunamadı. Adresi elle yazıp "
          "sunucuya_kaydet('https://...') çağır.")
'''


MANUEL_KAYIT = r'''
MANUEL KAYIT
============
Colab adresini elle bildirmek istersen, Flask'ın çalıştığı bilgisayarda:

  curl -X POST http://127.0.0.1:5000/register-backend ^
       -H "Content-Type: application/json" ^
       -d "{\"url\":\"https://xxxx.trycloudflare.com\",\"token\":\"ANAHTAR\"}"

Kaydın tuttuğunu doğrulamak için:

  curl http://127.0.0.1:5000/health
'''


if __name__ == "__main__":
    print(__doc__)
    print("=" * 60)
    print("COLAB HÜCRESİNE YAPIŞTIRILACAK KOD")
    print("=" * 60)
    print(KOD)
    print(MANUEL_KAYIT)
