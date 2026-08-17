#!/usr/bin/env bash
#
# Ebru AI — pod durum kontrolü
#
# Bir şey ters gittiğinde ilk bakılacak yer. Hiçbir şeyi değiştirmez,
# yalnızca okur.
#
# Kullanım:  bash durum.sh
#
set -uo pipefail

KOK="${EBRU_KOK:-/workspace}"
A1111="$KOK/stable-diffusion-webui"
GUNLUK="$KOK/log"

[ -f "$KOK/ortam.sh" ] && source "$KOK/ortam.sh"

baslik() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
iyi()    { printf '   \033[1;32m✓\033[0m %s\n' "$1"; }
kotu()   { printf '   \033[1;31m✗\033[0m %s\n' "$1"; }
nokta()  { printf '     %s\n' "$1"; }

baslik "GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu \
             --format=csv,noheader | sed 's/^/   /'
else
  kotu "nvidia-smi yok"
fi

baslik "Modeller"
kontrol_dosya() {
  local yol="$1" ad
  ad="$(basename "$yol")"
  if [ -f "$yol" ]; then
    iyi "$ad ($(( $(stat -c%s "$yol") / 1024 / 1024 )) MB)"
  else
    kotu "$ad YOK"
  fi
}
kontrol_dosya "$A1111/models/Stable-diffusion/sd_xl_base_1.0.safetensors"
kontrol_dosya "$A1111/models/Lora/ebru_projesi-01.safetensors"
kontrol_dosya "$A1111/models/Lora/sdxl_lightning_4step_lora.safetensors"

baslik "Servisler"
if curl -sf -o /dev/null --max-time 5 "http://127.0.0.1:7860/"; then
  iyi "A1111 (7860) yanıt veriyor"
else
  kotu "A1111 (7860) yanıt vermiyor"
  [ -f "$GUNLUK/a1111.log" ] && nokta "son satır: $(tail -n 1 "$GUNLUK/a1111.log")"
fi

if saglik="$(curl -sf --max-time 10 "http://127.0.0.1:5000/health")"; then
  iyi "Flask (5000) yanıt veriyor"
  echo "$saglik" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("     /health JSON degil"); raise SystemExit
for k, v in d.items():
    print(f"     {k}: {v}")
' 2>/dev/null || nokta "$saglik"
else
  kotu "Flask (5000) yanıt vermiyor"
  [ -f "$GUNLUK/flask.log" ] && nokta "son satır: $(tail -n 1 "$GUNLUK/flask.log")"
fi

baslik "Veritabanı"
DB="${EBRU_DB:-$KOK/veri/ebru.db}"
if [ -f "$DB" ]; then
  iyi "$DB ($(( $(stat -c%s "$DB") / 1024 )) KB)"
  if command -v sqlite3 >/dev/null 2>&1; then
    nokta "kayıtlı hesap: $(sqlite3 "$DB" 'SELECT COUNT(*) FROM kullanicilar;' 2>/dev/null || echo '?')"
  fi
else
  kotu "$DB yok — ilk üretimde boş olarak oluşturulacak"
fi

baslik "Güvenlik"
if [ -n "${EBRU_DEBUG:-}" ]; then
  kotu "EBRU_DEBUG TANIMLI — halka açık pod'da uzaktan kod çalıştırmaya açar"
else
  iyi "EBRU_DEBUG kapalı"
fi

if [ -n "${EBRU_REGISTER_TOKEN:-}" ]; then
  iyi "EBRU_REGISTER_TOKEN tanımlı"
else
  kotu "EBRU_REGISTER_TOKEN yok — yönetim paneline erişilemez"
fi

baslik "Disk"
df -h "$KOK" | tail -n 1 | sed 's/^/   /'
echo
