#!/usr/bin/env bash
#
# Ebru AI — pod ilk kurulumu
#
# Bir kez çalıştırılır. Her şeyi /workspace altına, yani network
# volume'a kurar. Pod silinip yeniden yaratıldığında volume durduğu
# sürece bu adım tekrarlanmaz; yeni pod'da doğrudan baslat.sh yeter.
#
# Betik yarıda kesilirse tekrar çalıştırılabilir: indirilenler
# atlanır, yarım kalan dosyalar kaldığı yerden devam eder.
#
# Kullanım:  bash kurulum.sh
#
set -euo pipefail

KOK="${EBRU_KOK:-/workspace}"
DEPO="$KOK/ebru"
A1111="$KOK/stable-diffusion-webui"
VERI="$KOK/veri"
GUNLUK="$KOK/log"

DEPO_ADRESI="https://github.com/enestum2/Ebru-AI.git"
A1111_ADRESI="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"

# Dosya adları koda gömülü; app.py bunları birebir bu adlarla arıyor.
# Yanlış ad hata vermez, sessizce kaliteyi ve hızı düşürür.
CHECKPOINT="sd_xl_base_1.0.safetensors"
EBRU_LORA="ebru_projesi-01.safetensors"
HIZ_LORA="sdxl_lightning_4step_lora.safetensors"

baslik() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
bilgi()  { printf '   %s\n' "$1"; }
uyari()  { printf '\033[1;33m   ! %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------
# İndirme: dosya varsa ve makul boyuttaysa atlanır.
# Yarım kalmışsa wget -c kaldığı yerden devam eder.
# ---------------------------------------------------------------
indir() {
  local adres="$1" hedef="$2" asgari="$3" ad
  ad="$(basename "$hedef")"

  if [ -f "$hedef" ]; then
    local boyut
    boyut="$(stat -c%s "$hedef")"
    if [ "$boyut" -ge "$asgari" ]; then
      bilgi "$ad zaten var ($((boyut / 1024 / 1024)) MB), atlanıyor"
      return 0
    fi
    uyari "$ad eksik görünüyor, indirme sürdürülüyor"
  fi

  bilgi "$ad indiriliyor…"
  wget -c -q --show-progress -O "$hedef" "$adres"

  local son
  son="$(stat -c%s "$hedef")"
  if [ "$son" -lt "$asgari" ]; then
    echo "HATA: $ad beklenenden küçük ($son bayt). İndirme başarısız." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------

baslik "Sistem paketleri"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# libgl1 ve libglib2.0-0: A1111'in kullandığı opencv bunlar olmadan
# içe aktarılamıyor ve hata mesajı yanıltıcı oluyor.
apt-get install -y -qq git wget python3-venv libgl1 libglib2.0-0 >/dev/null
bilgi "tamam"

baslik "Klasörler"
mkdir -p "$VERI" "$GUNLUK"
bilgi "$VERI"
bilgi "$GUNLUK"

baslik "Ebru deposu"
if [ -d "$DEPO/.git" ]; then
  git -C "$DEPO" pull --ff-only
  bilgi "güncellendi"
else
  git clone --depth 1 "$DEPO_ADRESI" "$DEPO"
  bilgi "klonlandı"
fi

baslik "Stable Diffusion WebUI"
if [ -d "$A1111/.git" ]; then
  bilgi "zaten kurulu, atlanıyor"
else
  git clone --depth 1 "$A1111_ADRESI" "$A1111"
  bilgi "klonlandı"
fi

mkdir -p "$A1111/models/Stable-diffusion" "$A1111/models/Lora"

baslik "Modeller (~7,2 GB, ilk seferde uzun sürer)"
indir \
  "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/$CHECKPOINT" \
  "$A1111/models/Stable-diffusion/$CHECKPOINT" \
  6000000000

indir \
  "https://huggingface.co/enestum2/ebru-lora-sdxl/resolve/main/$EBRU_LORA" \
  "$A1111/models/Lora/$EBRU_LORA" \
  150000000

indir \
  "https://huggingface.co/ByteDance/SDXL-Lightning/resolve/main/$HIZ_LORA" \
  "$A1111/models/Lora/$HIZ_LORA" \
  300000000

baslik "Flask ortamı"
if [ ! -d "$KOK/venv" ]; then
  python3 -m venv "$KOK/venv"
  bilgi "venv oluşturuldu"
fi
# waitress requirements.txt'te yok; app.run() geliştirme sunucusu
# olduğu için halka açık pod'da onunla çalışmak istemiyoruz.
"$KOK/venv/bin/pip" install -q --upgrade pip
"$KOK/venv/bin/pip" install -q -r "$DEPO/server/requirements.txt" waitress
bilgi "bağımlılıklar kuruldu"

baslik "Ortam dosyası"
# Gizli değerler buraya yazılmıyor; RunPod'un kendi ortam
# değişkenlerinden geliyor ki depoya sızmasınlar.
cat > "$KOK/ortam.sh" <<'ORTAM'
# Ebru AI — pod ortam değişkenleri. baslat.sh bunu okuyor.

export EBRU_DB=/workspace/veri/ebru.db
export EBRU_WEB_DIR=/workspace/ebru/web
export EBRU_LORA_DIR=/workspace/stable-diffusion-webui/models/Lora
export EBRU_LOCAL_SD_URL=http://127.0.0.1:7860
export EBRU_ADMIN_USER=boss
export EBRU_DAILY_LIMIT=30

# Üretim ayarları: ilk taşımada çıktının yereldekiyle birebir aynı
# olması isteniyor, o yüzden bilerek belirtilmiyor — app.py Lightning
# LoRA'sını bulunca 4 adım / CFG 1.8'e kendisi geçiyor.

# EBRU_DEBUG kesinlikle ayarlanmıyor: Werkzeug hata ayıklayıcısı
# halka açık bir pod'da uzaktan kod çalıştırmaya izin verir.
unset EBRU_DEBUG

# A1111 başlatma argümanları.
#   --no-download-sd-model : SD 1.5'i indirmesin, SDXL'i biz koyduk
#   --opt-sdp-attention    : xformers derlemeye gerek kalmadan hızlanma
# 24 GB kartta --medvram gerekmiyor; koyarsak yavaşlatır.
export COMMANDLINE_ARGS="--api --listen --port 7860 --opt-sdp-attention --no-download-sd-model --no-half-vae"
ORTAM
bilgi "$KOK/ortam.sh yazıldı"

baslik "Kurulum bitti"
cat <<SON

   Sırada:

   1) Kayıt anahtarını pod ortam değişkenlerine ekle:
        EBRU_REGISTER_TOKEN = <uzun gizli değer>
      Yönetim paneline erişim de buna bağlı.

   2) Eski hesapları taşıyacaksan ebru.db dosyasını şuraya koy:
        $VERI/ebru.db
      Koymazsan boş bir veritabanı oluşur ve herkes yeniden kaydolur.

   3) Servisleri başlat:
        bash $DEPO/pod/baslat.sh

SON
