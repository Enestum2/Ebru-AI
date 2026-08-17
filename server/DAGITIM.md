# Ebru AI — Dağıtım Rehberi

Uygulamayı telefonuna kuran herkesin çalıştırabilmesi için sunucunun
internetten erişilebilir olması gerekiyor. Bu doküman o kurulumu anlatıyor.

## Mimari

```
Telefon (APK)  ──HTTPS──>  Flask sunucusu  ──HTTP──>  Stable Diffusion (A1111)
                           (hafif, GPU yok)           (Colab tüneli veya yerel GPU)
```

Flask GPU kullanmıyor; sadece prompt hazırlıyor ve yönlendiriyor.
Asıl yük A1111 tarafında.

## 1. Flask'ı internete aç (Cloudflare Tunnel)

`cloudflared` kurulu değil. Kurulum:

```bash
winget install --id Cloudflare.cloudflared
```

### Hızlı yöntem — geçici adres (domain gerekmez)

```bash
cloudflared tunnel --url http://localhost:5000
```

Konsolda `https://xxxx.trycloudflare.com` benzeri bir adres verir.
Test için yeterli, ama **her açılışta adres değişir** — dağıtılan bir
APK'ya bu adresi gömmek işe yaramaz.

### Kalıcı yöntem — sabit adres (domain gerekir)

```bash
cloudflared tunnel login
cloudflared tunnel create ebru
cloudflared tunnel route dns ebru ebru.senindomainin.com
cloudflared tunnel run --url http://localhost:5000 ebru
```

Artık adres sabit: `https://ebru.senindomainin.com`. APK'ya bunu gömebilirsin.
Domain yıllık birkaç dolar; sabit adres olmadan gerçek dağıtım mümkün değil.

## 2. Ortam değişkenlerini ayarla

```bash
setx EBRU_REGISTER_TOKEN "kendi-uzun-gizli-anahtarin"
setx EBRU_DAILY_LIMIT "30"
setx EBRU_MAX_QUEUE "8"
```

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `EBRU_REGISTER_TOKEN` | rastgele | Colab'ın kayıt anahtarı |
| `EBRU_DAILY_LIMIT` | 30 | Cihaz başına günlük üretim |
| `EBRU_MIN_INTERVAL` | 3 | İki istek arası en az saniye |
| `EBRU_MAX_QUEUE` | 8 | Kuyrukta bekleyebilecek istek |
| `EBRU_QUEUE_TIMEOUT` | 240 | Sırada en fazla bekleme (sn) |
| `EBRU_LOCAL_SD_URL` / `SD_LOCAL_URL` | `http://127.0.0.1:7860` | Yerel A1111 adresi |
| `EBRU_DEBUG` | kapalı | `1` yaparsan Werkzeug debugger açılır (dağıtımda **açma**) |

## 3. Colab'ı bağla

`colab_kayit.py` içindeki hücreyi Colab notebook'una yapıştır,
`EBRU_SERVER_URL` alanına 1. adımdaki adresi yaz. Colab her açılışta
kendini otomatik kaydeder.

Elle kaydetmek istersen:

```bash
curl -X POST https://ebru.senindomainin.com/register-backend -H "Content-Type: application/json" -d "{\"url\":\"https://xxxx.trycloudflare.com\",\"token\":\"ANAHTAR\"}"
```

Durumu kontrol:

```bash
curl https://ebru.senindomainin.com/health
```

## 4. Üretim sunucusu olarak çalıştır

`app.run()` Flask'ın geliştirme sunucusu — tek başına dağıtıma uygun değil.
Windows'ta:

```bash
pip install waitress
waitress-serve --host=127.0.0.1 --port=5000 app:app
```

Cloudflare Tunnel zaten HTTPS'i üstlendiği için Flask'ın sadece
localhost'u dinlemesi yeterli ve daha güvenli.

## API uçları

| Uç | Ne yapar |
|---|---|
| `POST /generate` | Senkron üretim, sonucu bekleyip döner. **Web sitesi kullanıyor.** Uzun sürerse tünel 100 sn'de keser. |
| `POST /jobs` | Asenkron üretim. Hemen `job_id` döner (202). **Mobil uygulama bunu kullanır.** |
| `GET /jobs/<id>` | İşin durumu; bittiyse görsel de bu yanıtta gelir. |
| `GET /health` | Sunucu ve GPU durumu |
| `GET /progress` | Süren üretimin ilerlemesi |
| `POST /register-backend` | Colab'ın tünel adresini bildirmesi |

Asenkron akış neden gerekli: 6 GB kartta bir görsel ~95–110 saniye sürüyor,
Cloudflare tüneli ise ~100 saniyede bağlantıyı kesiyor (`HTTP 524`).
İş numarasıyla çalışınca uzun bağlantı hiç kurulmaz, kuyrukta bekleme de
sorun olmaktan çıkar.

## Üretim hızı

Ölçümler (RTX 3060 Laptop, 6 GB):

| Ayar | Süre |
|---|---|
| 832×1216, 24 adım | ~8 dk |
| 704×1024, 16 adım | ~3,5 dk |
| **704×1024, 4 adım + Lightning LoRA** | **~95 sn** |

`sdxl_lightning_4step_lora.safetensors` dosyası `models/Lora` içinde
varsa backend otomatik olarak 4 adım + CFG 1.8 + Euler/SGM Uniform
ayarına geçer. Kapatmak için `EBRU_LIGHTNING=0`.

6 GB VRAM SDXL için sınırda: model tek başına kartı dolduruyor.
Tarayıcı gibi GPU kullanan uygulamaları kapatmak süreyi kısaltır.

## Ölçek ve maliyet — dikkat

- **Tek GPU, tek kuyruk.** Aynı anda tek üretim çalışır. Bir görsel
  ~20–40 sn sürüyorsa, 10 kişi aynı anda istek atarsa sonuncusu
  5–7 dakika bekler. `EBRU_MAX_QUEUE` bunu sınırlar; dolduğunda
  kullanıcı "yoğunluk var" mesajı alır.
- **Colab ücretsiz katman rastgele kopar.** 7/24 açık bir servis için
  uygun değil. Gerçek dağıtımda ya kendi GPU'n sürekli açık olmalı ya da
  Replicate/RunPod gibi ücretli bir servise geçilmeli.
- **Kötüye kullanım.** Kimlik doğrulama yok; `X-Device-Id` başlığı
  kullanıcı tarafından değiştirilebilir. Ciddi dağıtımda gerçek bir
  hesap sistemi gerekir.

## Kontrol listesi

- [ ] `EBRU_DEBUG` ayarlı değil (Werkzeug debugger kapalı)
- [ ] `EBRU_REGISTER_TOKEN` kendi belirlediğin uzun bir değer
- [ ] Flask `waitress` ile çalışıyor
- [ ] Tünel sabit bir adrese bağlı
- [ ] Uygulamada sunucu adresi bu sabit adres
- [ ] `curl /health` → `"ready": true`
