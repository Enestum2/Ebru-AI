#!/usr/bin/env bash
#
# Ebru AI — Oracle Cloud (Ubuntu) sunucu kurulumu.
#
# Bu betik SUNUCUDA calisir. Elle calistirilmasi gerekmiyor;
# oracle_kurulum.sh sihirbazi dosyalari yukleyip bunu cagiriyor.
#
# Kurdugu yapi:
#
#     internet --443--> Caddy (HTTPS, sertifikayi kendi aliyor)
#                          |
#                          v
#                 gunicorn 127.0.0.1:5000  (Flask: site + API)
#                          |
#                          +--> uretim istegi --> ev bilgisayarindaki A1111
#
# GPU BURADA YOK. Bu makine yalnizca siteyi ayakta tutuyor; goruntuyu
# ev bilgisayari uretiyor ve adresini POST /register-backend ile
# bildiriyor.

set -euo pipefail

YUKLEME_DIZINI="${YUKLEME_DIZINI:-$HOME/ebru_yukleme}"
KURULUM_DIZINI="/opt/ebru"
VERI_DIZINI="/var/lib/ebru"
AYAR_DOSYASI="/etc/ebru/ebru.env"
SERVIS_KULLANICI="ebru"

ALAN_ADI="${ALAN_ADI:-ebruai.com}"
KAYIT_ANAHTARI="${KAYIT_ANAHTARI:-}"

renk_bilgi() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
renk_ok()    { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }
renk_uyari() { printf '\033[0;33m  ! %s\033[0m\n' "$1"; }

if [[ -z "$KAYIT_ANAHTARI" ]]; then
  echo "HATA: KAYIT_ANAHTARI verilmedi." >&2
  echo "Kullanim: KAYIT_ANAHTARI=... ALAN_ADI=... bash sunucu_kur.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1) GUVENLIK DUVARI — Oracle'in iki katmani
# ---------------------------------------------------------------------
# Oracle'da iki ayri guvenlik duvari var ve IKISI birden acilmadan site
# disaridan gorunmuyor:
#
#   a) VCN guvenlik listesi  -> bulut panelinden, sihirbazin 4. asamasi
#   b) makinedeki iptables   -> burasi
#
# Oracle'in Ubuntu imaji iptables-persistent ile geliyor ve INPUT
# zincirinin sonunda her seyi reddeden bir kural var. Kurallari sona
# EKLEMEK ise yaramaz; reddeden kuraldan ONCE araya sokulmalari gerekir.
# Bu ayrim, "panelden portu actim ama site hala acilmiyor" seklinde
# saatler yakan klasik tuzak.
renk_bilgi "Guvenlik duvari (iptables) duzenleniyor"

iptables_ac() {
  local port="$1"

  # Kural zaten varsa tekrar ekleme (betik birden fazla kez calisabilir).
  if sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    renk_ok "$port zaten acik"
    return 0
  fi

  # Reddeden ilk kuralin sira numarasini bul; kurali onun ustune sok.
  local reddeden
  reddeden="$(sudo iptables -L INPUT --line-numbers -n \
              | awk '$2 == "REJECT" || $2 == "DROP" { print $1; exit }')"

  if [[ -n "$reddeden" ]]; then
    sudo iptables -I INPUT "$reddeden" -p tcp --dport "$port" -j ACCEPT
  else
    sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  fi
  renk_ok "$port acildi"
}

iptables_ac 80
iptables_ac 443

# Kurallar yeniden baslatmada kaybolmasin.
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save >/dev/null
  renk_ok "kurallar kalici hale getirildi"
else
  renk_uyari "netfilter-persistent yok; kurallar yeniden baslatmada silinebilir"
fi

# ---------------------------------------------------------------------
# 2) TAKAS ALANI (yalnizca kucuk makinelerde)
# ---------------------------------------------------------------------
# Ucretsiz AMD sekli (E2.1.Micro) 1 GB bellekle geliyor; pip kurulumu
# bile bellegi doldurabiliyor. ARM sekli 12 GB ile geldigi icin orada
# bu adim atlaniyor.
#
# Bu bolum paket kurulumundan ONCE: dar bellekte asil zorlanan adim
# apt ve pip, takas alani sonradan acilirsa ise yaramiyor.
BELLEK_MB="$(free -m | awk '/^Mem:/ { print $2 }')"
if [[ "$BELLEK_MB" -lt 2000 && ! -f /swapfile ]]; then
  renk_bilgi "Bellek ${BELLEK_MB} MB — 2 GB takas alani ekleniyor"
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  renk_ok "takas alani acildi"
fi

# ---------------------------------------------------------------------
# 3) PAKETLER
# ---------------------------------------------------------------------
renk_bilgi "Paketler kuruluyor"
sudo apt-get update -qq

# BURADA AZ PAKET ISTEMEK ONEMLI.
#
# Ilk surumde Caddy'nin Debian talimatindan kopyalanan debian-keyring ve
# debian-archive-keyring de bu listedeydi. Ubuntu'da Caddy deposunu
# eklemek icin bunlar gerekmiyor -- curl ve gpg yetiyor -- ama
# debian-keyring tek basina 100 MB'in uzerinde.
#
# Olcum: ucretsiz E2.1.Micro makinede ag ~135 KB/s gidiyor (buyuk ve
# kucuk dosyada ayni, yani MTU degil, bant genisligi). O iki paket
# kurulumu 15 dakikadan fazla uzatti; 119 MB inmisti.
#
# apt-transport-https de cikarildi: modern Ubuntu'da https destegi
# apt'in icinde, o paket yalnizca gecis amacli duruyor. Yerine
# ca-certificates konuldu; cloudsmith'e https ile baglanilacak.
#
# --no-install-recommends: onerilen paketler bu dar baglantida gereksiz
# yuk. Ihtiyac duyulan her sey asagida acikca yaziliyor.
sudo apt-get install -y -qq --no-install-recommends \
  python3-venv python3-pip ca-certificates curl gnupg

# Caddy: HTTPS sertifikasini kendi aliyor ve kendi yeniliyor. nginx +
# certbot ile ayni isi yapmak belirgin sekilde daha fazla yapilandirma
# istiyordu; burada tek dosyalik bir ayar yetiyor.
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq --no-install-recommends caddy
fi
renk_ok "paketler hazir"

# ---------------------------------------------------------------------
# 4) KULLANICI VE DIZINLER
# ---------------------------------------------------------------------
renk_bilgi "Dizinler hazirlaniyor"

if ! id "$SERVIS_KULLANICI" >/dev/null 2>&1; then
  sudo useradd --system --home-dir "$KURULUM_DIZINI" --shell /usr/sbin/nologin "$SERVIS_KULLANICI"
fi

sudo mkdir -p "$KURULUM_DIZINI" "$VERI_DIZINI" /etc/ebru

# Uygulama dosyalari: her kurulumda yenilenir.
sudo rm -rf "$KURULUM_DIZINI/server" "$KURULUM_DIZINI/web"
sudo cp -r "$YUKLEME_DIZINI/server" "$KURULUM_DIZINI/server"
sudo cp -r "$YUKLEME_DIZINI/web"    "$KURULUM_DIZINI/web"

# Ev bilgisayarina ait olan seyler sunucuda ise yaramaz; kafa
# karistirmasinlar diye siliniyor.
sudo rm -f "$KURULUM_DIZINI/server/uretim_isci.py" \
           "$KURULUM_DIZINI/server/uretim_baslat.bat" \
           "$KURULUM_DIZINI/server/sunucu_baslat.bat" \
           "$KURULUM_DIZINI/server/tunel_baslat.bat"

# Veritabani: VARSA USTUNE YAZILMIYOR. Bu betik guncelleme icin tekrar
# calistirildiginda sunucuda birikmis hesaplarin silinmemesi gerekiyor.
if [[ -f "$YUKLEME_DIZINI/ebru.db" && ! -f "$VERI_DIZINI/ebru.db" ]]; then
  sudo cp "$YUKLEME_DIZINI/ebru.db" "$VERI_DIZINI/ebru.db"
  renk_ok "veritabani tasindi"
elif [[ -f "$VERI_DIZINI/ebru.db" ]]; then
  renk_ok "veritabani zaten var, korundu"
fi

# APK (58 MB) — depoya girmedigi icin ayrica yukleniyor.
if [[ -f "$YUKLEME_DIZINI/ebru-ai.apk" ]]; then
  sudo mkdir -p "$KURULUM_DIZINI/web/static/indir"
  sudo cp "$YUKLEME_DIZINI/ebru-ai.apk" "$KURULUM_DIZINI/web/static/indir/ebru-ai.apk"
  renk_ok "APK yerine kondu"
else
  renk_uyari "APK bulunamadi; /indir sayfasi 'henuz yuklenmedi' diyecek"
fi

sudo chown -R "$SERVIS_KULLANICI:$SERVIS_KULLANICI" "$KURULUM_DIZINI" "$VERI_DIZINI"

# ---------------------------------------------------------------------
# 5) PYTHON ORTAMI
# ---------------------------------------------------------------------
renk_bilgi "Python ortami kuruluyor"
sudo -u "$SERVIS_KULLANICI" python3 -m venv "$KURULUM_DIZINI/venv"
sudo -u "$SERVIS_KULLANICI" "$KURULUM_DIZINI/venv/bin/pip" install --quiet --upgrade pip
sudo -u "$SERVIS_KULLANICI" "$KURULUM_DIZINI/venv/bin/pip" install --quiet \
  -r "$KURULUM_DIZINI/server/requirements.txt" gunicorn
renk_ok "bagimliliklar kuruldu"

# ---------------------------------------------------------------------
# 6) AYARLAR
# ---------------------------------------------------------------------
# EBRU_LIGHTNING=1 KRITIK. Hizlandirma LoRA'sinin dosyasi bu makinede
# yok (A1111 ev bilgisayarinda). Kod eskiden dosyaya bakarak karar
# veriyordu; boyle bir sunucuda hizlandirma sessizce kapaniyor, adim
# 4 yerine 16 ve CFG 1.8 yerine 8.5 oluyordu. Yavaslama bir yana,
# Lightning LoRA'si yuksek CFG ile goruntuyu yakiyor. Yani bu satir
# unutulursa hata coküs olarak degil BOZUK CIKTI olarak gorunur.
renk_bilgi "Ayar dosyasi yaziliyor"

# Bu betik ayar dosyasini BASTAN yaziyor. Elle eklenmis gizli degerler
# (ornegin Resend anahtari, "sunucu.sh ayar" ile yazilanlar) yeniden
# kurulumda silinirdi ve e-posta gonderimi sessizce calismaz olurdu.
# Korunacak anahtarlar once okunuyor, sonra dosyanin sonuna geri
# ekleniyor.
KORUNACAK="EBRU_RESEND_API_KEY EBRU_EPOSTA_GONDEREN EBRU_SITE_URL"
ESKI_DEGERLER=""
if [[ -f "$AYAR_DOSYASI" ]]; then
  for anahtar in $KORUNACAK; do
    satir="$(sudo grep -E "^${anahtar}=" "$AYAR_DOSYASI" 2>/dev/null | tail -n1 || true)"
    if [[ -n "$satir" ]]; then
      ESKI_DEGERLER="${ESKI_DEGERLER}${satir}
"
      renk_ok "korunuyor: $anahtar"
    fi
  done
fi

sudo tee "$AYAR_DOSYASI" >/dev/null <<AYARLAR
# Ebru AI sunucu ayarlari. sunucu_kur.sh tarafindan yazildi.

# Ev bilgisayarindaki uretim makinesinin kaydolurken kullandigi anahtar.
# Buradaki deger ile oradaki uretim_ayarlar.bat AYNI olmali.
EBRU_REGISTER_TOKEN=$KAYIT_ANAHTARI

# Hizlandirma: dosya kontrolunu atlayip acik kabul et (yukaridaki nota bak).
EBRU_LIGHTNING=1

# Bu makinede GPU yok; 127.0.0.1:7860'i yoklamanin anlami yok.
EBRU_LOCAL_SD_URL=0

EBRU_DB=$VERI_DIZINI/ebru.db
EBRU_WEB_DIR=$KURULUM_DIZINI/web

# Hata ayiklayici uzaktan kod calistirmaya izin verebilir; kapali kalmali.
EBRU_DEBUG=0
AYARLAR

# Onceki kurulumdan korunan gizli degerler geri ekleniyor.
if [[ -n "$ESKI_DEGERLER" ]]; then
  printf '\n# Onceki kurulumdan korunan degerler\n%s' "$ESKI_DEGERLER" \
    | sudo tee -a "$AYAR_DOSYASI" >/dev/null
fi

sudo chmod 640 "$AYAR_DOSYASI"
sudo chown root:"$SERVIS_KULLANICI" "$AYAR_DOSYASI"
renk_ok "ayarlar yazildi ($AYAR_DOSYASI)"

# ---------------------------------------------------------------------
# 7) SERVIS
# ---------------------------------------------------------------------
# TEK ISCI (-w 1) ZORUNLU.
#
# Is numaralari, kuyruk uzunlugu ve kullanim sayaclari surecin
# belleginde tutuluyor (app.py: _jobs, _queue_length, _usage). Birden
# fazla gunicorn isciyle istekler surecler arasinda dagilir ve
# kullanici "is bulunamadi" hatasi alir. Ayni hata daha once iki Flask
# ayni porta baglandiginda yasandi. Es zamanlilik ihtiyaci --threads
# ile karsilaniyor; zaten ayni anda tek uretim calisiyor.
renk_bilgi "Servis kuruluyor"
sudo tee /etc/systemd/system/ebru.service >/dev/null <<SERVIS
[Unit]
Description=Ebru AI sitesi (Flask)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVIS_KULLANICI
Group=$SERVIS_KULLANICI
WorkingDirectory=$KURULUM_DIZINI/server
EnvironmentFile=$AYAR_DOSYASI

# Gunluk aninda gorunsun. Python'un stdout'u ucbirime bagli olmadigi
# icin blok tamponlu calisiyor; satirlar birikip tampon dolunca topluca
# yaziliyor. Olcum: 39 dakikaya yayilmis 38 satir journald'a tek
# saniyede dustu ve hepsi ayni zaman damgasini aldi. Hata ararken
# gunlugun gercek zamanli olmasi sart.
Environment=PYTHONUNBUFFERED=1
ExecStart=$KURULUM_DIZINI/venv/bin/gunicorn \\
    --workers 1 \\
    --threads 8 \\
    --timeout 600 \\
    --bind 127.0.0.1:5000 \\
    app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVIS

sudo systemctl daemon-reload
sudo systemctl enable --now ebru.service >/dev/null
renk_ok "ebru.service calisiyor"

# ---------------------------------------------------------------------
# 8) CADDY (HTTPS)
# ---------------------------------------------------------------------
# Sertifika alabilmesi icin alan adinin bu sunucuya bakiyor olmasi
# gerekiyor. Kurulum sirasinda DNS henuz cevrilmemis olabilir; Caddy
# basarisiz denemeleri kendisi tekrarliyor, DNS cevrilince sertifika
# kendiliginden geliyor. Bu yuzden burada hata sayilmiyor.
renk_bilgi "Caddy yapilandiriliyor"
sudo tee /etc/caddy/Caddyfile >/dev/null <<CADDY
# Ebru AI. sunucu_kur.sh tarafindan yazildi.

$ALAN_ADI, www.$ALAN_ADI {
    encode zstd gzip

    # APK 58 MB; varsayilan zaman asimlari yavas baglantida yetmiyor.
    reverse_proxy 127.0.0.1:5000 {
        transport http {
            read_timeout 600s
            write_timeout 600s
        }
    }
}
CADDY

sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy
renk_ok "Caddy calisiyor"

# ---------------------------------------------------------------------
# 9) YEREL DOGRULAMA
# ---------------------------------------------------------------------
renk_bilgi "Kontrol"
sleep 3

if curl -fsS -m 10 http://127.0.0.1:5000/health >/dev/null; then
  renk_ok "Flask cevap veriyor"
  curl -sS -m 10 http://127.0.0.1:5000/health | head -c 400
  echo
else
  echo
  echo "HATA: Flask cevap vermiyor. Gunluge bak:" >&2
  echo "  sudo journalctl -u ebru.service -n 50 --no-pager" >&2
  exit 1
fi

echo
renk_ok "Sunucu kurulumu tamam."
echo "   Gunlukler : sudo journalctl -u ebru.service -f"
echo "   Yeniden   : sudo systemctl restart ebru.service"
