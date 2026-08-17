#!/usr/bin/env bash
#
# Ebru AI — servisleri başlatır
#
# Pod her açıldığında çalıştırılır. Kurulum yapmaz; onu kurulum.sh
# bir kez yapıyor ve sonuçları network volume'da duruyor.
#
# Önce A1111 kalkar, hazır olması beklenir, sonra Flask başlar.
# Sıra önemli: Flask açılışta GPU'yu yokluyor, A1111 hazır değilken
# başlarsa kendini "sunucu kapalı" sayıyor.
#
# Kullanım:  bash baslat.sh
#
set -euo pipefail

KOK="${EBRU_KOK:-/workspace}"
DEPO="$KOK/ebru"
A1111="$KOK/stable-diffusion-webui"
GUNLUK="$KOK/log"

# A1111 ilk açılışta ek dosyalar indirip modeli belleğe alıyor;
# bu yüzden ilk bekleme uzun. Sonraki açılışlar çok daha hızlı.
A1111_BEKLEME=1200   # saniye
FLASK_BEKLEME=90     # saniye

baslik() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
bilgi()  { printf '   %s\n' "$1"; }
hata()   { printf '\033[1;31m   HATA: %s\033[0m\n' "$1" >&2; }

if [ ! -f "$KOK/ortam.sh" ]; then
  hata "$KOK/ortam.sh yok. Önce kurulum.sh çalıştırılmalı."
  exit 1
fi

# shellcheck disable=SC1090
source "$KOK/ortam.sh"
mkdir -p "$GUNLUK"

if [ -z "${EBRU_REGISTER_TOKEN:-}" ]; then
  hata "EBRU_REGISTER_TOKEN tanımlı değil."
  bilgi "RunPod'da pod ortam değişkenlerine ekleyip pod'u yeniden başlat."
  bilgi "Bu anahtar olmadan yönetim paneline erişilemiyor."
  exit 1
fi

# Güvenlik: bu değişken bir şekilde ortama sızmışsa temizle.
unset EBRU_DEBUG

# ---------------------------------------------------------------
# Bir adresin yanıt vermesini bekler.
# ---------------------------------------------------------------
bekle() {
  local adres="$1" saniye="$2" ad="$3" gecen=0
  while [ "$gecen" -lt "$saniye" ]; do
    if curl -sf -o /dev/null --max-time 5 "$adres"; then
      bilgi "$ad hazır (${gecen} sn)"
      return 0
    fi
    sleep 5
    gecen=$((gecen + 5))
    if [ $((gecen % 60)) -eq 0 ]; then
      bilgi "$ad bekleniyor… ${gecen} sn"
    fi
  done
  return 1
}

calisiyor_mu() {
  curl -sf -o /dev/null --max-time 5 "$1" 2>/dev/null
}

# ---------------------------------------------------------------

baslik "Stable Diffusion WebUI"
if calisiyor_mu "http://127.0.0.1:7860/internal/ping" ||
   calisiyor_mu "http://127.0.0.1:7860/"; then
  bilgi "zaten çalışıyor"
else
  cd "$A1111"
  # -f: webui.sh root kullanıcıda çalışmayı reddediyor, bu izin veriyor.
  nohup ./webui.sh -f > "$GUNLUK/a1111.log" 2>&1 &
  bilgi "başlatıldı, günlük: $GUNLUK/a1111.log"

  if ! bekle "http://127.0.0.1:7860/" "$A1111_BEKLEME" "A1111"; then
    hata "A1111 $A1111_BEKLEME saniyede açılmadı."
    bilgi "Son satırlar:"
    tail -n 25 "$GUNLUK/a1111.log" >&2
    exit 1
  fi
fi

baslik "Flask"
if calisiyor_mu "http://127.0.0.1:5000/health"; then
  bilgi "zaten çalışıyor"
else
  cd "$DEPO/server"
  # waitress-serve modülü çalışma klasöründen bulduğu için cd şart.
  nohup "$KOK/venv/bin/waitress-serve" \
        --host=0.0.0.0 --port=5000 app:app \
        > "$GUNLUK/flask.log" 2>&1 &
  bilgi "başlatıldı, günlük: $GUNLUK/flask.log"

  if ! bekle "http://127.0.0.1:5000/health" "$FLASK_BEKLEME" "Flask"; then
    hata "Flask $FLASK_BEKLEME saniyede yanıt vermedi."
    tail -n 25 "$GUNLUK/flask.log" >&2
    exit 1
  fi
fi

baslik "Durum"
"$KOK/venv/bin/python" - <<'PY'
import json, urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:5000/health", timeout=10) as c:
        d = json.load(c)
    print(f"   üretime hazır : {d.get('ready')}")
    print(f"   GPU kaynağı   : {d.get('source') or d.get('kaynak') or '-'}")
except Exception as e:
    print(f"   /health okunamadı: {e}")
PY

baslik "Son adım"
cat <<'SON'

   Pod'un dış adresini RunPod panelinden al (5000 portu):
     https://<podID>-5000.proxy.runpod.net

   Sonra depodaki sunucu.json dosyasında "sunucu" alanını bu adresle
   değiştir ve GitHub'a it. Telefonlardaki uygulamalar bir sonraki
   açılışta yeni adrese geçer — APK dağıtmaya gerek yok.

   Pod'u kapatmadan önce kullanıcıları bilgilendirmek istersen aynı
   dosyadaki "mesaj" alanını kullanabilirsin.

SON
