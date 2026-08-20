#!/usr/bin/env bash
#
# Ebru AI — sunucu bakim araclari.
#
# Site artik Oracle Cloud'da calisiyor. Kod bu bilgisayarda yaziliyor
# ama orada kosuyor; arada hafif bir kopru gerekiyordu. Tek secenek
# sunucu_kur.sh'i bastan calistirmakti, o da her seferinde 58 MB APK'yi
# yeniden yukleyip pip kurulumunu tekrarliyor. Bu dosya o isi saniyelere
# indiriyor.
#
# Kullanim (genelde .bat baslaticilardan cagriliyor):
#
#     bash sunucu.sh guncelle     kodu gonder ve servisi yeniden baslat
#     bash sunucu.sh veritabani   veritabaninin tutarli bir kopyasini indir
#     bash sunucu.sh durum        servislerin ve /health'in durumu
#     bash sunucu.sh gunluk       canli gunluk akisi (Ctrl+C ile cik)
#
# Baglanti bilgileri .env dosyasindan okunuyor; onu oracle_kurulum.sh
# yazdi. .env yoksa once o sihirbaz calistirilmali.

set -euo pipefail

BETIK_DIZINI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BETIK_DIZINI"

BACKEND_DIZINI="$BETIK_DIZINI"
WEB_DIZINI="$(cd "$BETIK_DIZINI/../../../Ebru_Web" 2>/dev/null && pwd || echo "")"
YEDEK_DIZINI="$BETIK_DIZINI/veritabani_yedek"

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  YESIL=$(tput setaf 2); SARI=$(tput setaf 3); KIRMIZI=$(tput setaf 1)
else
  BOLD=""; DIM=""; RESET=""; YESIL=""; SARI=""; KIRMIZI=""
fi

bilgi() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
ok()    { printf '%s  ✓ %s%s\n' "$YESIL" "$1" "$RESET"; }
uyari() { printf '%s  ! %s%s\n' "$SARI" "$1" "$RESET"; }
hata()  { printf '%s  ✗ %s%s\n' "$KIRMIZI" "$1" "$RESET"; }

# ---------------------------------------------------------------
# Baglanti ayarlari
# ---------------------------------------------------------------
if [[ ! -f .env ]]; then
  hata ".env bulunamadi: $BETIK_DIZINI/.env"
  echo "     Once kurulum sihirbazini calistir: oracle_kurulum_baslat.bat"
  exit 1
fi

# .env'den yalnizca ihtiyac duyulan uc deger okunuyor; dosyayi
# oldugu gibi kaynak almak (source) icindeki kayit anahtarini da
# ortama tasirdi, gereksiz.
oku() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- | tr -d '\r'; }

SUNUCU_IP="$(oku SUNUCU_IP)"
SUNUCU_KULLANICI="$(oku SUNUCU_KULLANICI)"
SSH_ANAHTAR="$(oku SSH_ANAHTAR)"

if [[ -z "$SUNUCU_IP" || -z "$SSH_ANAHTAR" ]]; then
  hata ".env icinde SUNUCU_IP ya da SSH_ANAHTAR yok."
  exit 1
fi
SUNUCU_KULLANICI="${SUNUCU_KULLANICI:-ubuntu}"

uzak() {
  ssh -i "$SSH_ANAHTAR" \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=15 \
      "$SUNUCU_KULLANICI@$SUNUCU_IP" "$@"
}

# ---------------------------------------------------------------
# guncelle — kodu gonder, veritabanini yedekle, servisi yenile
# ---------------------------------------------------------------
komut_guncelle() {
  if [[ -z "$WEB_DIZINI" || ! -d "$WEB_DIZINI/templates" ]]; then
    hata "Site klasoru bulunamadi (aranan: ../../../Ebru_Web)"
    exit 1
  fi

  bilgi "Kod paketleniyor ve gonderiliyor"
  uzak "rm -rf ~/ebru_guncelleme && mkdir -p ~/ebru_guncelleme"

  # Disarida birakilanlar: venv (yuzlerce MB), gunlukler, yedekler,
  # veritabani (sunucudaki korunacak) ve gizli anahtar dosyalari.
  printf '%s  sunucu kodu%s\n' "$DIM" "$RESET"
  tar -czf - \
      --exclude=venv --exclude=__pycache__ --exclude='*.pyc' \
      --exclude='*.log' --exclude='*.bak' --exclude='*.yedek_*' \
      --exclude='ebru.db' --exclude='.env' \
      --exclude='uretim_ayarlar.bat' \
      --exclude='veritabani_yedek' \
      -C "$BACKEND_DIZINI" . \
    | uzak "mkdir -p ~/ebru_guncelleme/server && tar -xzf - -C ~/ebru_guncelleme/server"

  # APK gonderilmiyor: 58 MB ve degismiyor. Sunucudaki yerinde korunuyor.
  printf '%s  site sablonlari%s\n' "$DIM" "$RESET"
  tar -czf - \
      --exclude='./static/indir' --exclude='static/indir' --exclude=.vscode \
      -C "$WEB_DIZINI" . \
    | uzak "mkdir -p ~/ebru_guncelleme/web && tar -xzf - -C ~/ebru_guncelleme/web"

  ok "dosyalar sunucuda"

  bilgi "Veritabani yedekleniyor (sunucuda)"
  # Sema gocleri app.py'nin kur() cagrisiyla ACILISTA kendiliginden
  # calisiyor. Yani her guncelleme bir goc calistirabilir; oncesinde
  # yedek almak pazarlik konusu degil. Son 10 yedek tutuluyor.
  uzak '
    set -e
    # Klasor sudo ile aciliyor, yani sahibi root oluyor. Yedegi alan
    # Python ise "ebru" kullanicisi olarak calisiyor ve root
    # klasorune yazamiyor; sqlite bunu "unable to open database file"
    # diye bildiriyor, izin hatasi gibi gorunmuyor. Sahiplik veriliyor.
    sudo mkdir -p /var/lib/ebru/yedek
    sudo chown ebru:ebru /var/lib/ebru/yedek
    if [ -f /var/lib/ebru/ebru.db ]; then
      AD="ebru.db.$(date +%Y%m%d-%H%M%S)"
      sudo -u ebru /opt/ebru/venv/bin/python3 - "$AD" <<PY
import sqlite3, sys
kaynak = sqlite3.connect("/var/lib/ebru/ebru.db")
hedef  = sqlite3.connect("/var/lib/ebru/yedek/" + sys.argv[1])
kaynak.backup(hedef)
hedef.close(); kaynak.close()
PY
      echo "  yedek: /var/lib/ebru/yedek/$AD"
      sudo ls -1t /var/lib/ebru/yedek/ | tail -n +11 | while read -r e; do
        sudo rm -f "/var/lib/ebru/yedek/$e"
      done
    else
      echo "  veritabani henuz yok, yedek atlandi"
    fi
  '
  ok "yedek alindi"

  bilgi "Yerine konuyor ve servis yenileniyor"
  uzak '
    set -e
    # APK yerinde kalsin: web klasoru silinmeden once kenara aliniyor.
    if [ -d /opt/ebru/web/static/indir ]; then
      sudo rm -rf /tmp/ebru_indir
      sudo mv /opt/ebru/web/static/indir /tmp/ebru_indir
    fi

    sudo rm -rf /opt/ebru/server /opt/ebru/web
    sudo cp -r ~/ebru_guncelleme/server /opt/ebru/server
    sudo cp -r ~/ebru_guncelleme/web    /opt/ebru/web

    if [ -d /tmp/ebru_indir ]; then
      sudo mkdir -p /opt/ebru/web/static
      sudo mv /tmp/ebru_indir /opt/ebru/web/static/indir
    fi

    # Ev bilgisayarina ait dosyalar sunucuda ise yaramiyor.
    sudo rm -f /opt/ebru/server/uretim_isci.py \
               /opt/ebru/server/uretim_baslat.bat \
               /opt/ebru/server/sunucu_baslat.bat \
               /opt/ebru/server/tunel_baslat.bat \
               /opt/ebru/server/oracle_kurulum.sh \
               /opt/ebru/server/oracle_kurulum_baslat.bat

    sudo chown -R ebru:ebru /opt/ebru
    sudo systemctl restart ebru
  '
  ok "ebru.service yeniden baslatildi"

  bilgi "Kontrol"
  # Servisin ayaga kalkmasi ve varsa gocun islemesi icin kisa bekleme.
  sleep 4
  if uzak 'curl -fsS -m 10 http://127.0.0.1:5000/health' >/dev/null 2>&1; then
    ok "site cevap veriyor"
    uzak 'curl -sS -m 10 http://127.0.0.1:5000/health' | head -c 300
    printf '\n'
  else
    hata "site cevap vermiyor — gunluge bak:"
    echo "     bash sunucu.sh gunluk"
    uzak 'sudo journalctl -u ebru.service -n 25 --no-pager' 2>/dev/null | tail -25
    exit 1
  fi
}

# ---------------------------------------------------------------
# veritabani — tutarli bir kopyayi bu bilgisayara indir
# ---------------------------------------------------------------
komut_veritabani() {
  mkdir -p "$YEDEK_DIZINI"
  local ad="ebru-$(date +%Y%m%d-%H%M%S).db"
  local hedef="$YEDEK_DIZINI/$ad"

  bilgi "Veritabaninin tutarli kopyasi aliniyor"
  # Calisan bir SQLite dosyasini dogrudan kopyalamak (cat/scp) yazma
  # anina denk gelirse yarim kayit veriyor. sqlite3'un backup API'si
  # tutarli anlik goruntu aliyor; sunucuda zaten Python var.
  uzak '
    set -e
    sudo -u ebru /opt/ebru/venv/bin/python3 - <<PY
import sqlite3
kaynak = sqlite3.connect("/var/lib/ebru/ebru.db")
hedef  = sqlite3.connect("/tmp/ebru_kopya.db")
kaynak.backup(hedef)
hedef.close(); kaynak.close()
PY
    sudo chmod 644 /tmp/ebru_kopya.db
  '

  # Ikili dosya: ssh ciktisi dogrudan dosyaya yonlendiriliyor (-t yok).
  uzak 'cat /tmp/ebru_kopya.db' > "$hedef"

  # Silme sudo istiyor: dosyayi "ebru" kullanicisi olusturdu ve /tmp
  # yapiskan bit tasiyor, baskasinin dosyasi silinemiyor. Temizlik
  # basarisiz olursa is yine bitmis sayilir, betigi dusurmesin.
  uzak 'sudo rm -f /tmp/ebru_kopya.db' || true

  ok "indirildi: $hedef  ($(du -h "$hedef" | cut -f1))"
  printf '\n'
  printf '  %sIcerigine bakmak icin:%s\n' "$BOLD" "$RESET"
  printf '    - DB Browser for SQLite (ucretsiz, cift tiklayip acabilirsin)\n'
  printf '    - ya da: bash sunucu.sh veritabani-ozet\n'
}

# ---------------------------------------------------------------
# veritabani-ozet — indirmeden, sunucuda hizli bakis
# ---------------------------------------------------------------
komut_ozet() {
  bilgi "Kayitli kullanicilar (sunucudan, sifre hash'leri gosterilmiyor)"
  uzak '
    sudo -u ebru /opt/ebru/venv/bin/python3 - <<PY
import sqlite3, time
db = sqlite3.connect("/var/lib/ebru/ebru.db")
db.row_factory = sqlite3.Row

sutunlar = [s[1] for s in db.execute("PRAGMA table_info(kullanicilar)")]
print("  tablo alanlari:", ", ".join(sutunlar))
print()

gosterilecek = [s for s in sutunlar if s != "sifre_hash"]
satirlar = db.execute("SELECT %s FROM kullanicilar ORDER BY id" % ", ".join(gosterilecek)).fetchall()
print("  %d kullanici" % len(satirlar))
print()
for r in satirlar:
    parcalar = []
    for s in gosterilecek:
        d = r[s]
        if s in ("olusturma", "son_giris") and d:
            d = time.strftime("%Y-%m-%d %H:%M", time.localtime(d))
        parcalar.append("%s=%s" % (s, d))
    print("   ", "  ".join(parcalar))
PY
  '
}

# ---------------------------------------------------------------
# apk — yeni derlenmis APK'yi siteye yukle
# ---------------------------------------------------------------
# "guncelle" APK gondermiyor: 58 MB ve her kod degisikliginde
# degismiyor, yavas baglantida bosuna dakikalar yakardi. Yeni surum
# ciktiginda bu komut calistiriliyor.
komut_apk() {
  local kaynak="${2:-}"
  if [[ -z "$kaynak" ]]; then
    # Flutter'in varsayilan cikti yolu.
    kaynak="$BETIK_DIZINI/../../../../ebru_ai_wallpaper/build/app/outputs/flutter-apk/app-release.apk"
    kaynak="$(cd "$(dirname "$kaynak")" 2>/dev/null && pwd)/$(basename "$kaynak")" || true
  fi

  if [[ ! -f "$kaynak" ]]; then
    hata "APK bulunamadi: $kaynak"
    echo "     Once derle:  flutter build apk --release"
    echo "     Ya da yolu ver:  bash sunucu.sh apk /yol/app-release.apk"
    exit 1
  fi

  local boyut
  boyut="$(du -h "$kaynak" | cut -f1)"
  bilgi "APK yukleniyor ($boyut) — yavas baglantida birkac dakika surer"
  echo "  kaynak: $kaynak"

  # Once gecici ada yukleniyor, sonra yerine tasiniyor. Yukleme
  # yarida kalirsa site bozuk bir dosyayi sunmaya baslamasin.
  scp -i "$SSH_ANAHTAR" -o StrictHostKeyChecking=accept-new \
      "$kaynak" "$SUNUCU_KULLANICI@$SUNUCU_IP:/tmp/ebru-yeni.apk"

  uzak '
    set -e
    sudo mkdir -p /opt/ebru/web/static/indir
    sudo mv /tmp/ebru-yeni.apk /opt/ebru/web/static/indir/ebru-ai.apk
    sudo chown ebru:ebru /opt/ebru/web/static/indir/ebru-ai.apk
    sudo chmod 644 /opt/ebru/web/static/indir/ebru-ai.apk
    ls -lh /opt/ebru/web/static/indir/ebru-ai.apk | awk "{print \"  sunucuda: \" \$5}"
  '
  ok "APK yayinda"

  bilgi "Kontrol"
  curl -s -m 60 -r 0-1048575 -o /dev/null \
    -w "  /apk -> HTTP %{http_code}  hiz: %{speed_download} B/s\n" \
    https://ebruai.com/apk
}


# ---------------------------------------------------------------
# ayar — sunucudaki /etc/ebru/ebru.env icine bir deger yaz
# ---------------------------------------------------------------
# Gizli degerler (ornegin Resend anahtari) depoya ve betiklere
# girmemeli. Bu komut degeri gizli okuyup dogrudan sunucudaki ayar
# dosyasina yaziyor; hicbir yerde iz birakmiyor.
komut_ayar() {
  local anahtar="${2:-}"
  if [[ -z "$anahtar" ]]; then
    hata "Kullanim: bash sunucu.sh ayar ANAHTAR_ADI"
    echo "     ornek: bash sunucu.sh ayar EBRU_RESEND_API_KEY"
    exit 1
  fi

  local deger=""
  printf '  %s%s degeri:%s ' "$BOLD" "$anahtar" "$RESET"
  # Gizli okuma: anahtar ekranda ve kabuk gecmisinde gorunmesin.
  #
  # "|| true" sart: deger boruyla beslendiginde (echo ... | sunucu.sh
  # ayar ...) girdi satir sonuyla bitmiyorsa read dosya sonuna carpip
  # sifirdan farkli donuyor ve "set -e" yuzunden betik sessizce
  # kapaniyor. Okunan deger yine de elimizde oluyor.
  read -rs deger || true
  printf '\n'

  if [[ -z "$deger" ]]; then
    hata "Bos deger yazilmadi."
    exit 1
  fi

  bilgi "Sunucudaki ayar dosyasi guncelleniyor"
  # Deger stdin ile gonderiliyor: komut satirinda gecerse sunucunun
  # surec listesinde ve kabuk gecmisinde gorunurdu.
  printf '%s' "$deger" | uzak "
    set -e
    DEGER=\$(cat)
    sudo touch /etc/ebru/ebru.env
    sudo sed -i '/^${anahtar}=/d' /etc/ebru/ebru.env
    echo \"${anahtar}=\$DEGER\" | sudo tee -a /etc/ebru/ebru.env >/dev/null
    sudo chmod 640 /etc/ebru/ebru.env
    sudo chown root:ebru /etc/ebru/ebru.env
    sudo systemctl restart ebru
  "
  ok "$anahtar yazildi ve servis yeniden baslatildi"

  sleep 4
  bilgi "Kontrol"
  if uzak 'curl -fsS -m 10 http://127.0.0.1:5000/health' >/dev/null 2>&1; then
    ok "site cevap veriyor"
  else
    hata "site cevap vermiyor — bash sunucu.sh gunluk"
  fi
}


# ---------------------------------------------------------------
# durum / gunluk
# ---------------------------------------------------------------
komut_durum() {
  bilgi "Sunucu durumu"
  # Ic ice tirnak yok: disaridaki komut tek tirnakli oldugu icin awk
  # ifadeleri kacislarla yazmak gerekiyordu ve kolay bozuluyordu.
  # Ham cikti yeterince okunakli.
  uzak '
    echo "  ebru.service  : $(systemctl is-active ebru)"
    echo "  caddy         : $(systemctl is-active caddy)"
    echo "  calisma suresi: $(uptime -p)"
    echo
    echo "  --- bellek ---"
    free -h | head -3
    echo "  --- disk ---"
    df -h /
  '
  printf '\n'
  bilgi "/health (disaridan)"
  curl -fsS -m 20 https://ebruai.com/health 2>/dev/null | head -c 300 || uyari "ebruai.com cevap vermedi"
  printf '\n'
}

komut_gunluk() {
  bilgi "Canli gunluk — cikmak icin Ctrl+C"
  uzak -t 'sudo journalctl -u ebru.service -f -n 40'
}

# ---------------------------------------------------------------
case "${1:-}" in
  guncelle)          komut_guncelle ;;
  ayar)              komut_ayar "$@" ;;
  apk)               komut_apk "$@" ;;
  veritabani)        komut_veritabani ;;
  veritabani-ozet)   komut_ozet ;;
  durum)             komut_durum ;;
  gunluk)            komut_gunluk ;;
  *)
    echo "Kullanim: bash sunucu.sh <komut>"
    echo
    echo "  guncelle         kodu gonder, veritabanini yedekle, servisi yenile"
    echo "  ayar ANAHTAR     sunucudaki gizli ayari yaz (deger gizli sorulur)"
    echo "  apk [yol]        yeni APK yi siteye yukle"
    echo "  veritabani       veritabaninin tutarli kopyasini indir"
    echo "  veritabani-ozet  kullanicilari indirmeden listele"
    echo "  durum            servisler, bellek, disk, /health"
    echo "  gunluk           canli gunluk akisi"
    exit 1
    ;;
esac
