# Pod kurulumu

Ebru AI'ın sunucu tarafını kiralanan bir RunPod GPU'suna kurmak için.
Üç betik var; sırayla kullanılıyor.

| Betik | Ne zaman | Ne yapıyor |
|---|---|---|
| `kurulum.sh` | bir kez | Depoyu, A1111'i ve modelleri volume'a kurar |
| `baslat.sh` | pod her açıldığında | A1111 ve Flask'ı başlatır |
| `durum.sh` | bir şey ters gidince | Her şeyi okur, hiçbir şeyi değiştirmez |

## 1. RunPod panelinde

**Önce network volume oluştur, sonra pod'u ona bağla.** Ters sırada
yaparsan modelleri iki kez indirirsin.

| Ayar | Değer | Neden |
|---|---|---|
| Network volume | 50 GB | Modeller 7,2 GB, kalanı A1111 + venv + çıktılar |
| GPU | RTX A5000, Community | Saati ~$0,16 |
| Template | RunPod PyTorch | CUDA hazır geliyor |
| Volume mount | `/workspace` | Betikler bu yolu varsayıyor |
| Expose HTTP port | `5000` | Flask; A1111 dışarı açılmıyor |

Pod ortam değişkenlerine ekle:

```
EBRU_REGISTER_TOKEN = <uzun gizli değer>
```

Yönetim paneline erişim de bu anahtara bağlı. `EBRU_DEBUG` **hiç
tanımlanmamalı** — halka açık bir pod'da Werkzeug hata ayıklayıcısı
uzaktan kod çalıştırmaya izin verir.

## 2. Pod terminalinde

```bash
git clone --depth 1 https://github.com/enestum2/Ebru-AI.git /workspace/ebru
bash /workspace/ebru/pod/kurulum.sh
```

İlk kurulum ~7,2 GB indirme ve A1111'in kendi ortamını kurmasını
içeriyor; bağlantıya göre 15–30 dakika sürebilir. Yarıda kesilirse
betiği tekrar çalıştır, kaldığı yerden devam eder.

### Eski hesapları taşıma

Kayıtlı kullanıcılar korunacaksa `ebru.db` dosyasını pod'a yükleyip
şuraya koy:

```
/workspace/veri/ebru.db
```

Koymazsan boş bir veritabanı oluşur ve herkesin yeniden kaydolması
gerekir. Şifreler hash'li olduğu için dosyayı taşımak yeterli.

## 3. Başlatma

```bash
bash /workspace/ebru/pod/baslat.sh
```

Önce A1111 kalkar, hazır olması beklenir, sonra Flask başlar. Sıra
önemli: Flask açılışta GPU'yu yokluyor, A1111 hazır değilken başlarsa
kendini "sunucu kapalı" sayıyor.

İlk açılış uzun (model belleğe alınıyor), sonrakiler hızlı.

## 4. Adresi duyurma

Pod'un dış adresini panelden al:

```
https://<podID>-5000.proxy.runpod.net
```

Depodaki `sunucu.json` dosyasında `sunucu` alanını bununla değiştir ve
GitHub'a it:

```json
{
  "sunucu": "https://xxxxxxxx-5000.proxy.runpod.net",
  "mesaj": "Sunucu hafta içi 19:00-23:00 arası açık."
}
```

Telefonlardaki uygulamalar bir sonraki açılışta yeni adrese geçer.
**APK yeniden dağıtmaya gerek yok.**

`mesaj` alanı, sunucuya ulaşılamadığında kullanıcıya gösteriliyor —
pod'u elle açıp kapattığın için burayı güncel tutmak işe yarıyor.

## Kapatırken

Pod saat başı ücretlendiği için işin bitince **durdur**. Volume ayrı
ücretlendirilir (~$3,5/ay) ve pod kapalıyken de durur, yani modelleri
tekrar indirmezsin.

Pod'u *silersen* proxy adresi değişir; yeni adresi `sunucu.json`'a
yazman yeterli, kurulum tekrarlanmaz.

## Sorun çıkarsa

```bash
bash /workspace/ebru/pod/durum.sh
```

Günlükler:

```
/workspace/log/a1111.log
/workspace/log/flask.log
```

Sık karşılaşılanlar:

- **A1111 açılmıyor** — `a1111.log`'a bak. Genelde eksik sistem
  paketi (`libgl1`) ya da model dosyasının yarım inmesi.
- **Üretim var ama ebru dokusu yok** — LoRA dosya adı yanlış olabilir.
  `durum.sh` üç model dosyasını da adıyla kontrol ediyor.
- **Üretim çok yavaş** — Lightning LoRA bulunamamış olabilir; o zaman
  app.py 4 adım yerine 16 adıma düşüyor. `EBRU_LORA_DIR` doğru mu bak.
