"""Kullanıcı hesapları ve oturum yönetimi.

Veriler SQLite'ta tutuluyor: tek dosya, ayrı bir sunucu kurulumu
gerektirmiyor ve bu ölçek için fazlasıyla yeterli.

Şifreler asla düz metin saklanmıyor; Werkzeug'un scrypt tabanlı
karma fonksiyonu kullanılıyor. Sunucu veritabanını ele geçiren biri
bile şifreleri okuyamaz.
"""
import contextlib
import os
import re
import secrets
import sqlite3
import threading
import time

from werkzeug.security import check_password_hash, generate_password_hash

# Varsayılan olarak kod klasörünün yanında duruyor. Sunucu bir konteynerde
# çalışıyorsa bu klasör kapanışta siliniyor ve bütün hesaplar gidiyor;
# o yüzden EBRU_DB ile kalıcı bir diske taşınabilir olmalı.
VERITABANI = os.environ.get("EBRU_DB") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "ebru.db",
)

# Hedef klasör yoksa sqlite3 "unable to open database file" der; kurulumu
# kolaylaştırmak için klasörü kendimiz açıyoruz.
_db_klasoru = os.path.dirname(os.path.abspath(VERITABANI))
if _db_klasoru:
    os.makedirs(_db_klasoru, exist_ok=True)

# Oturum anahtarının geçerlilik süresi (saniye). 90 gün.
OTURUM_SURESI = int(os.environ.get("EBRU_OTURUM_SURESI", str(90 * 24 * 3600)))

KULLANICI_ADI_DESENI = re.compile(r'^[a-zA-Z0-9_.]{3,24}$')
EN_KISA_SIFRE = 6

# Ad ve soyadda kabul edilen harfler.
#
# Türkçe harfler tek bir aralıkta değil: ç, ö, ü Latin-1'de ama
# ğ, ı, ş Latin Extended-A'da duruyor. "A-Za-zÀ-ÿ" gibi genel bir
# aralık bu üçünü kaçırır ve "Işık" ya da "Çağla" reddedilirdi.
# Bu yüzden hepsi tek tek yazılı.
_AD_HARFLERI = "A-Za-zÇÖÜçöüĞğİıŞş"

# İlk karakter harf olmalı; devamında boşluk, kesme işareti ve tire de
# serbest ("Ayşe Nur", "O'Brien", "Kara-Demir"). Toplam 2-40 karakter.
AD_DESENI = re.compile(
    "^[%s][%s'\\- ]{1,39}$" % (_AD_HARFLERI, _AD_HARFLERI)
)

# E-posta için kasıtlı olarak sade bir denetim. RFC'ye tam uyan desen
# okunamayacak kadar uzun ve pratikte fayda getirmiyor; adresin gerçek
# olup olmadığını zaten doğrulama postası belirleyecek. Buradaki amaç
# yazım hatasını ve boş girdiyi elemek.
EPOSTA_DESENI = re.compile(r"^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$")

_lock = threading.Lock()


@contextlib.contextmanager
def _baglan():
    """
    Veritabanı bağlantısı açar, iş bitince kapatır.

    ÖNEMLİ: sqlite3.connect() bağlam yöneticisi olarak kullanıldığında
    işlemi tamamlar ama bağlantıyı KAPATMAZ. Önceki sürümde her sorgu
    yeni bir bağlantı açıp bırakıyordu; yüzlerce üretimden sonra
    biriken bağlantılar sunucuyu yanıt veremez hale getiriyordu.
    """
    baglanti = sqlite3.connect(VERITABANI, timeout=10)
    baglanti.row_factory = sqlite3.Row
    try:
        yield baglanti
        baglanti.commit()
    except Exception:
        baglanti.rollback()
        raise
    finally:
        baglanti.close()


# =====================================
# ŞEMA GÖÇLERİ
# =====================================
# Hesap tablosu başta yalnızca kullanıcı adı ve şifre tutuyordu.
# E-posta doğrulaması ve Google ile giriş için alan eklemek gerekti.
#
# Göçler bir sürüm numarasına değil, "sütun gerçekten var mı"
# sorusuna bakıyor. Sürüm numarası ayrı bir yerde tutulur ve elle
# müdahale edilmiş bir veritabanında gerçekle uyuşmayabilir;
# PRAGMA table_info ise her zaman doğruyu söylüyor. Bu yöntem aynı
# zamanda göçün kaç kez çalıştığından bağımsız — her açılışta
# çağrılması sorun değil.
YENI_SUTUNLAR = (
    ("eposta", "TEXT"),
    ("ad", "TEXT"),
    ("soyad", "TEXT"),
    # 0/1. Doğrulanmamış hesap üretim yapamıyor (karar: 19 Ağustos).
    ("eposta_dogrulandi", "INTEGER NOT NULL DEFAULT 0"),
    # 'sifre' ya da 'google'. Şifre sıfırlama gibi akışların hangi
    # hesapta anlamlı olduğunu bilmek için gerekiyor.
    ("kayit_yolu", "TEXT NOT NULL DEFAULT 'sifre'"),
    # Google hesabının değişmeyen kimliği. Kişinin e-postası
    # değişebiliyor, bu değişmiyor; eşleştirmenin dayanağı bu olmalı.
    ("google_sub", "TEXT"),
    # Yönetici yetkisi. Önceden yalnızca EBRU_ADMIN_USER ile eşleşen
    # kullanıcı adı yönetici sayılıyordu; artık panelden de verilebiliyor.
    # O ortam değişkenindeki hesap her koşulda yönetici kalıyor (bkz.
    # app.py: _yonetici_mi) — panelden herkesin yetkisi alınıp kimsenin
    # giremediği bir duruma düşülmesin diye.
    ("yonetici", "INTEGER NOT NULL DEFAULT 0"),
    # Kişiye özel günlük üretim hakkı. NULL ise genel değer (DAILY_LIMIT)
    # geçerli. 0 yazılırsa o kişi üretim yapamaz — bilinçli bir seçenek.
    ("gunluk_limit", "INTEGER"),
)


def _goc_uygula(db):
    """Eksik sütun, indeks ve tabloları tamamlar. Tekrar çalışabilir."""
    mevcut = {satir["name"] for satir in db.execute(
        "PRAGMA table_info(kullanicilar)"
    )}

    for ad, tanim in YENI_SUTUNLAR:
        if ad not in mevcut:
            # Sütun adları kod içinde sabit; dışarıdan veri gelmiyor.
            db.execute(
                "ALTER TABLE kullanicilar ADD COLUMN %s %s" % (ad, tanim)
            )

    # UNIQUE kısıtı ALTER TABLE ADD COLUMN ile verilemiyor; ayrı bir
    # benzersiz indeks olarak kuruluyor.
    #
    # Burada SQLite'ın bir davranışı işimize yarıyor: benzersiz
    # indekste NULL'lar birbirinden FARKLI sayılıyor. Yani e-postası
    # olmayan birden fazla hesap yan yana durabiliyor. Yönetici
    # hesabının e-postasız kalabilmesi bu sayede mümkün.
    db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS kullanici_eposta "
        "ON kullanicilar(eposta)"
    )
    db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS kullanici_google "
        "ON kullanicilar(google_sub)"
    )

    # E-posta doğrulama bağlantıları.
    #
    # Adres satırın içinde ayrıca tutuluyor. Sebep: kullanıcı bağlantıya
    # tıklamadan önce e-postasını değiştirirse, eski bağlantı YENİ
    # adresi doğrulamamalı. Doğrulama, gönderildiği adrese aittir.
    db.execute("""
        CREATE TABLE IF NOT EXISTS dogrulama_kodlari (
            token          TEXT PRIMARY KEY,
            kullanici_id   INTEGER NOT NULL,
            eposta         TEXT NOT NULL,
            olusturma      REAL NOT NULL,
            son_gecerlilik REAL NOT NULL,
            kullanildi     INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (kullanici_id) REFERENCES kullanicilar(id)
        )
    """)
    db.execute(
        "CREATE INDEX IF NOT EXISTS dogrulama_kullanici "
        "ON dogrulama_kodlari(kullanici_id)"
    )

    # Şifre sıfırlama bağlantıları.
    #
    # E-posta doğrulamayla aynı tabloyu paylaşmıyor: ikisinin ömrü ve
    # anlamı farklı. Doğrulama bağlantısı 24 saat yaşıyor ve ele
    # geçirilse en fazla bir adresi onaylatır; şifre bağlantısı ise
    # hesabı doğrudan devralmaya yarıyor, o yüzden çok daha kısa ömürlü.
    # Aynı tabloda tutup "tip" alanıyla ayırmak, bir sorgu unutulduğunda
    # bu iki süreyi karıştırma riski doğuruyordu.
    db.execute("""
        CREATE TABLE IF NOT EXISTS sifre_kodlari (
            token          TEXT PRIMARY KEY,
            kullanici_id   INTEGER NOT NULL,
            olusturma      REAL NOT NULL,
            son_gecerlilik REAL NOT NULL,
            kullanildi     INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (kullanici_id) REFERENCES kullanicilar(id)
        )
    """)
    db.execute(
        "CREATE INDEX IF NOT EXISTS sifre_kodu_kullanici "
        "ON sifre_kodlari(kullanici_id)"
    )

    # Yönetici hesabı doğrulamadan muaf (karar: 19 Ağustos 2026).
    # E-postası yok ve olmayacak; hiçbir akışta takılmaması için
    # doğrulanmış sayılıyor. Karşılaştırma büyük/küçük harf duyarsız,
    # çünkü veritabanındaki ad "Boss", ayardaki ise "boss".
    yonetici = (os.environ.get("EBRU_ADMIN_USER") or "boss").strip().lower()
    db.execute(
        "UPDATE kullanicilar SET eposta_dogrulandi = 1 "
        "WHERE lower(kullanici_adi) = ?",
        (yonetici,),
    )


def kur():
    """Tabloları oluşturur ve şema göçlerini uygular.

    Her açılışta çağrılabilir; adımların hepsi tekrara dayanıklı.
    """
    with _lock, _baglan() as db:
        db.execute("""
            CREATE TABLE IF NOT EXISTS kullanicilar (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                kullanici_adi TEXT UNIQUE NOT NULL,
                sifre_hash   TEXT NOT NULL,
                olusturma    REAL NOT NULL,
                son_giris    REAL
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS oturumlar (
                token        TEXT PRIMARY KEY,
                kullanici_id INTEGER NOT NULL,
                olusturma    REAL NOT NULL,
                son_kullanim REAL NOT NULL,
                FOREIGN KEY (kullanici_id) REFERENCES kullanicilar(id)
            )
        """)
        # Günlük üretim sayacı: sunucu yeniden başlasa da korunur.
        db.execute("""
            CREATE TABLE IF NOT EXISTS kullanim (
                kullanici_id INTEGER NOT NULL,
                gun          TEXT NOT NULL,
                sayi         INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (kullanici_id, gun)
            )
        """)
        db.execute(
            "CREATE INDEX IF NOT EXISTS oturum_kullanici "
            "ON oturumlar(kullanici_id)"
        )

        # Yukarıdaki CREATE TABLE'lar yalnızca boş bir veritabanında iş
        # görüyor; var olan bir tabloya sonradan alan eklemiyorlar.
        # Eksikleri bu tamamlıyor.
        _goc_uygula(db)


class KayitHatasi(Exception):
    """Kullanıcıya gösterilebilecek kayıt/giriş hatası."""


def _dogrula(kullanici_adi, sifre):
    if not KULLANICI_ADI_DESENI.match(kullanici_adi or ""):
        raise KayitHatasi(
            "Kullanıcı adı 3-24 karakter olmalı; harf, rakam, "
            "nokta ve alt çizgi kullanabilirsiniz."
        )
    if len(sifre or "") < EN_KISA_SIFRE:
        raise KayitHatasi(
            f"Şifre en az {EN_KISA_SIFRE} karakter olmalı."
        )


def _ad_dogrula(deger, alan_adi):
    """Ad ya da soyadı denetler ve temizlenmiş halini döner.

    Burada "doğrulama" yalnızca biçim denetimi. Bir kişinin gerçekten
    o isimde olduğu kimlik belgesi olmadan anlaşılamaz; amaç boş ya da
    anlamsız girdiyi elemek.
    """
    deger = " ".join((deger or "").split())  # baştaki/sondaki/çift boşluk
    if not AD_DESENI.match(deger):
        raise KayitHatasi(
            f"{alan_adi} 2-40 karakter olmalı ve yalnızca harf, "
            "boşluk, kesme işareti ya da tire içerebilir."
        )
    return deger


def _eposta_dogrula(eposta):
    """E-posta adresini denetler ve küçük harfe çevirip döner.

    Adres küçük harfe çevriliyor: benzersizlik indeksi büyük/küçük
    harfe duyarlı, yoksa "Ali@x.com" ve "ali@x.com" iki ayrı hesap
    açabilirdi.
    """
    eposta = (eposta or "").strip().lower()
    if not EPOSTA_DESENI.match(eposta) or len(eposta) > 254:
        raise KayitHatasi("Geçerli bir e-posta adresi girin.")
    return eposta


def kayit_ol(kullanici_adi, sifre, ad=None, soyad=None, eposta=None):
    """Yeni hesap oluşturur ve oturum anahtarı döner.

    Ad, soyad ve e-posta 19 Ağustos 2026'da zorunlu hale geldi.
    Bu alanları göndermeyen eski mobil sürüm kayıt yapamıyor; ne
    olduğunu anlatan bir mesaj alıyor ve siteye yönlendiriliyor.
    """
    kullanici_adi = (kullanici_adi or "").strip()
    _dogrula(kullanici_adi, sifre)

    if not (ad and soyad and eposta):
        raise KayitHatasi(
            "Kayıt için ad, soyad ve e-posta gerekiyor. "
            "Uygulamanın bu sürümü bunları gönderemiyor; "
            "hesabınızı ebruai.com üzerinden açabilirsiniz."
        )

    ad = _ad_dogrula(ad, "Ad")
    soyad = _ad_dogrula(soyad, "Soyad")
    eposta = _eposta_dogrula(eposta)

    with _lock, _baglan() as db:
        mevcut = db.execute(
            "SELECT 1 FROM kullanicilar WHERE kullanici_adi = ? COLLATE NOCASE",
            (kullanici_adi,),
        ).fetchone()
        if mevcut:
            raise KayitHatasi("Bu kullanıcı adı zaten alınmış.")

        # Benzersiz indeks bunu zaten engelliyor, ama oradan gelen hata
        # kullanıcıya gösterilemeyecek bir veritabanı mesajı olurdu.
        eposta_var = db.execute(
            "SELECT 1 FROM kullanicilar WHERE eposta = ?", (eposta,)
        ).fetchone()
        if eposta_var:
            raise KayitHatasi(
                "Bu e-posta adresiyle zaten bir hesap var. "
                "Giriş yapmayı deneyin."
            )

        imlec = db.execute(
            "INSERT INTO kullanicilar "
            "(kullanici_adi, sifre_hash, olusturma, ad, soyad, eposta, "
            " eposta_dogrulandi, kayit_yolu) "
            "VALUES (?, ?, ?, ?, ?, ?, 0, 'sifre')",
            (
                kullanici_adi,
                generate_password_hash(sifre),
                time.time(),
                ad,
                soyad,
                eposta,
            ),
        )
        kullanici_id = imlec.lastrowid

    return _oturum_ac(kullanici_id), kullanici_adi


def giris_yap(kullanici_adi, sifre):
    """Kimlik doğrular ve oturum anahtarı döner."""
    kullanici_adi = (kullanici_adi or "").strip()

    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT id, kullanici_adi, sifre_hash FROM kullanicilar "
            "WHERE kullanici_adi = ? COLLATE NOCASE",
            (kullanici_adi,),
        ).fetchone()

    # Kullanıcı yok ile şifre yanlış aynı mesajı veriyor: hangi
    # kullanıcı adlarının kayıtlı olduğu dışarıdan anlaşılmasın.
    if not satir or not check_password_hash(satir["sifre_hash"], sifre or ""):
        raise KayitHatasi("Kullanıcı adı veya şifre hatalı.")

    with _lock, _baglan() as db:
        db.execute(
            "UPDATE kullanicilar SET son_giris = ? WHERE id = ?",
            (time.time(), satir["id"]),
        )

    return _oturum_ac(satir["id"]), satir["kullanici_adi"]


def _oturum_ac(kullanici_id):
    token = secrets.token_urlsafe(32)
    simdi = time.time()

    with _lock, _baglan() as db:
        db.execute(
            "INSERT INTO oturumlar "
            "(token, kullanici_id, olusturma, son_kullanim) "
            "VALUES (?, ?, ?, ?)",
            (token, kullanici_id, simdi, simdi),
        )
    return token


def oturumu_coz(token):
    """
    Oturum anahtarından kullanıcıyı bulur.
    Döner: {"id": .., "kullanici_adi": ..} ya da None.
    """
    if not token:
        return None

    simdi = time.time()

    # Bloktan erken çıkılmıyor: erken return, bağlam yöneticisinin
    # commit adımını atlatıp süresi dolmuş oturumun silinmesini
    # kaydetmeden bırakıyordu.
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT o.token, o.kullanici_id, o.olusturma, "
            "       k.kullanici_adi, k.eposta, k.eposta_dogrulandi, "
            "       k.yonetici, k.gunluk_limit, k.kayit_yolu "
            "FROM oturumlar o JOIN kullanicilar k ON k.id = o.kullanici_id "
            "WHERE o.token = ?",
            (token,),
        ).fetchone()

        gecerli = False
        if satir:
            if simdi - satir["olusturma"] > OTURUM_SURESI:
                db.execute(
                    "DELETE FROM oturumlar WHERE token = ?", (token,)
                )
            else:
                gecerli = True
                db.execute(
                    "UPDATE oturumlar SET son_kullanim = ? WHERE token = ?",
                    (simdi, token),
                )

    if not gecerli:
        return None

    return {
        "id": satir["kullanici_id"],
        "kullanici_adi": satir["kullanici_adi"],
        "eposta": satir["eposta"],
        # Üretim uçları buna bakıyor: doğrulanmamış hesap üretemiyor.
        "eposta_dogrulandi": bool(satir["eposta_dogrulandi"]),
        "yonetici": bool(satir["yonetici"]),
        # NULL ise genel günlük hak geçerli. 0 geçerli bir değer,
        # bu yüzden "or" ile varsayılana düşülmemeli.
        "gunluk_limit": satir["gunluk_limit"],
        # "sifre" ya da "google". Google hesabının kullanılabilir bir
        # şifresi yok (kayıtta rastgele bir değer atanıyor), o yüzden
        # hesap silmede şifre yerine kullanıcı adı onayı isteniyor.
        "kayit_yolu": satir["kayit_yolu"] or "sifre",
    }


def cikis_yap(token):
    with _lock, _baglan() as db:
        db.execute("DELETE FROM oturumlar WHERE token = ?", (token,))


# =====================================
# E-POSTA DOĞRULAMA
# =====================================
# Bağlantının ömrü. Kısa tutmanın anlamı yok: kullanıcı postayı
# akşam açabilir. Uzun tutmanın da yok: eski bağlantılar birikir.
DOGRULAMA_SURESI = 24 * 3600

# İki gönderim arasında beklenmesi gereken süre. Hem posta kotasını
# hem de kullanıcının gelen kutusunu koruyor.
DOGRULAMA_BEKLEME = 120


def dogrulama_kodu_olustur(kullanici_id, eposta):
    """Yeni doğrulama belirteci üretir.

    Aynı kullanıcının önceki kullanılmamış belirteçleri geçersiz
    kılınıyor: aynı anda birden fazla geçerli bağlantı dolaşmasın.

    Döner: (token, bekle_saniye). bekle_saniye doluysa yeni belirteç
    üretilmedi; çok sık istenmiş demektir.
    """
    simdi = time.time()

    with _lock, _baglan() as db:
        son = db.execute(
            "SELECT olusturma FROM dogrulama_kodlari "
            "WHERE kullanici_id = ? ORDER BY olusturma DESC LIMIT 1",
            (kullanici_id,),
        ).fetchone()

        if son and simdi - son["olusturma"] < DOGRULAMA_BEKLEME:
            kalan = int(DOGRULAMA_BEKLEME - (simdi - son["olusturma"])) + 1
            return None, kalan

        # Eskiler kullanılmış sayılıyor (silinmiyor: ne zaman ne
        # gönderildiğini görmek hata ararken işe yarıyor).
        db.execute(
            "UPDATE dogrulama_kodlari SET kullanildi = 1 "
            "WHERE kullanici_id = ? AND kullanildi = 0",
            (kullanici_id,),
        )

        token = secrets.token_urlsafe(32)
        db.execute(
            "INSERT INTO dogrulama_kodlari "
            "(token, kullanici_id, eposta, olusturma, son_gecerlilik) "
            "VALUES (?, ?, ?, ?, ?)",
            (token, kullanici_id, eposta, simdi, simdi + DOGRULAMA_SURESI),
        )

    return token, None


def dogrulama_kodu_kullan(token):
    """Belirteci harcar ve hesabı doğrulanmış yapar.

    Döner: kullanıcı adı. Geçersiz durumlarda KayitHatasi fırlatır.
    """
    simdi = time.time()

    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT d.kullanici_id, d.eposta, d.son_gecerlilik, "
            "       d.kullanildi, k.kullanici_adi, k.eposta AS guncel_eposta, "
            "       k.eposta_dogrulandi "
            "FROM dogrulama_kodlari d "
            "JOIN kullanicilar k ON k.id = d.kullanici_id "
            "WHERE d.token = ?",
            (token,),
        ).fetchone()

        if not satir:
            raise KayitHatasi(
                "Bu doğrulama bağlantısı geçersiz. "
                "Giriş yapıp yeni bağlantı isteyebilirsiniz."
            )

        if satir["eposta_dogrulandi"]:
            # Aynı bağlantıya iki kez tıklamak hata sayılmamalı.
            return satir["kullanici_adi"]

        if satir["kullanildi"]:
            raise KayitHatasi(
                "Bu bağlantı daha önce kullanılmış ya da yerine yenisi "
                "gönderilmiş. Giriş yapıp yeni bağlantı isteyebilirsiniz."
            )

        if simdi > satir["son_gecerlilik"]:
            raise KayitHatasi(
                "Bu bağlantının süresi dolmuş. "
                "Giriş yapıp yeni bağlantı isteyebilirsiniz."
            )

        # Belirteç gönderildiği adrese ait. Kullanıcı arada e-postasını
        # değiştirdiyse eski bağlantı YENİ adresi doğrulamamalı.
        if (satir["guncel_eposta"] or "") != satir["eposta"]:
            raise KayitHatasi(
                "Bu bağlantı başka bir e-posta adresi için gönderilmiş. "
                "Giriş yapıp yeni bağlantı isteyin."
            )

        db.execute(
            "UPDATE dogrulama_kodlari SET kullanildi = 1 WHERE token = ?",
            (token,),
        )
        db.execute(
            "UPDATE kullanicilar SET eposta_dogrulandi = 1 WHERE id = ?",
            (satir["kullanici_id"],),
        )

    return satir["kullanici_adi"]


# ---------------------------------------------------------------
# Günlük kullanım sayacı
# ---------------------------------------------------------------

def gunluk_sayi(kullanici_id, gun=None):
    gun = gun or time.strftime("%Y-%m-%d")
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT sayi FROM kullanim WHERE kullanici_id = ? AND gun = ?",
            (kullanici_id, gun),
        ).fetchone()
    return satir["sayi"] if satir else 0


def kullanim_artir(kullanici_id, gun=None):
    gun = gun or time.strftime("%Y-%m-%d")
    with _lock, _baglan() as db:
        db.execute(
            "INSERT INTO kullanim (kullanici_id, gun, sayi) VALUES (?, ?, 1) "
            "ON CONFLICT(kullanici_id, gun) DO UPDATE SET sayi = sayi + 1",
            (kullanici_id, gun),
        )


def kullanim_azalt(kullanici_id, gun=None):
    """Üretim başarısız olduysa hakkı geri verir."""
    gun = gun or time.strftime("%Y-%m-%d")
    with _lock, _baglan() as db:
        db.execute(
            "UPDATE kullanim SET sayi = MAX(0, sayi - 1) "
            "WHERE kullanici_id = ? AND gun = ?",
            (kullanici_id, gun),
        )


def bugunku_kullanicilar():
    """İzleme ekranı için: bugün üretim yapanlar."""
    gun = time.strftime("%Y-%m-%d")
    with _lock, _baglan() as db:
        satirlar = db.execute(
            "SELECT k.kullanici_adi, u.sayi FROM kullanim u "
            "JOIN kullanicilar k ON k.id = u.kullanici_id "
            "WHERE u.gun = ? ORDER BY u.sayi DESC",
            (gun,),
        ).fetchall()
    return [
        {"kimlik": s["kullanici_adi"], "bugun": s["sayi"]}
        for s in satirlar
    ]


def hepsi():
    """
    Yönetim paneli için: kayıtlı bütün kullanıcılar, bugünkü ve
    toplam üretim sayılarıyla birlikte.
    """
    gun = time.strftime("%Y-%m-%d")
    with _lock, _baglan() as db:
        satirlar = db.execute(
            """
            SELECT k.id,
                   k.kullanici_adi,
                   k.ad,
                   k.soyad,
                   k.eposta,
                   k.eposta_dogrulandi,
                   k.yonetici,
                   k.gunluk_limit,
                   k.kayit_yolu,
                   k.google_sub,
                   k.olusturma,
                   k.son_giris,
                   COALESCE(b.sayi, 0)   AS bugun,
                   COALESCE(t.toplam, 0) AS toplam
            FROM kullanicilar k
            LEFT JOIN kullanim b
                   ON b.kullanici_id = k.id AND b.gun = ?
            LEFT JOIN (
                   SELECT kullanici_id, SUM(sayi) AS toplam
                   FROM kullanim GROUP BY kullanici_id
            ) t ON t.kullanici_id = k.id
            ORDER BY k.olusturma DESC
            """,
            (gun,),
        ).fetchall()

    return [
        {
            "id": s["id"],
            "kullanici_adi": s["kullanici_adi"],
            "ad": s["ad"],
            "soyad": s["soyad"],
            "eposta": s["eposta"],
            "eposta_dogrulandi": bool(s["eposta_dogrulandi"]),
            # Veritabanındaki bayrak. app.py ayrıca ortam değişkenindeki
            # yönetici hesabını da yönetici sayıyor; panel ikisini
            # birleştirip gösteriyor.
            "yonetici": bool(s["yonetici"]),
            "gunluk_limit": s["gunluk_limit"],
            "kayit_yolu": s["kayit_yolu"],
            # Sifreyle acilmis bir hesap sonradan Google'a baglanmis
            # olabilir; kayit_yolu tek basina bunu gostermiyor.
            "google_bagli": bool(s["google_sub"]),
            "olusturma": s["olusturma"],
            "son_giris": s["son_giris"],
            "bugun": s["bugun"],
            "toplam": s["toplam"],
        }
        for s in satirlar
    ]


def kullanici_sayisi():
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT COUNT(*) AS n FROM kullanicilar"
        ).fetchone()
    return satir["n"]


# =====================================
# GOOGLE İLE GİRİŞ
# =====================================
def google_ile_bul(sub):
    """Google kimliğine bağlı hesabı bulur."""
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT id, kullanici_adi FROM kullanicilar WHERE google_sub = ?",
            (sub,),
        ).fetchone()
    return dict(satir) if satir else None


def eposta_ile_bul(eposta):
    """E-posta adresine kayıtlı hesabı bulur."""
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT id, kullanici_adi, eposta_dogrulandi, kayit_yolu, "
            "       google_sub "
            "FROM kullanicilar WHERE eposta = ? COLLATE NOCASE",
            ((eposta or "").strip().lower(),),
        ).fetchone()
    return dict(satir) if satir else None


def google_bagla(kullanici_id, sub):
    """Var olan hesaba Google kimliğini bağlar."""
    with _lock, _baglan() as db:
        db.execute(
            "UPDATE kullanicilar SET google_sub = ? WHERE id = ?",
            (sub, kullanici_id),
        )


def google_kayit(kullanici_adi, eposta, sub, ad=None, soyad=None):
    """Google ile yeni hesap açar.

    Şifre alanı boş bırakılamıyor (NOT NULL), o yüzden kimsenin
    bilmediği rastgele bir değerin karması yazılıyor. Bu hesaba
    şifreyle girmek mümkün değil; şifre sıfırlama da `kayit_yolu`
    'google' olduğu için reddediliyor. İkisi bilerek böyle: hesabın
    tek kapısı Google.

    E-posta doğrulanmış sayılıyor, çünkü Google'ın kendisi doğruladı.
    """
    # Ad ve soyad Google'dan geliyor; boş olabilirler ama doluysa
    # bizim biçim kurallarımıza uymalılar.
    if ad:
        _ad_dogrula(ad, "Ad")
    if soyad:
        _ad_dogrula(soyad, "Soyad")

    if not KULLANICI_ADI_DESENI.match(kullanici_adi or ""):
        raise KayitHatasi(
            "Kullanıcı adı 3-24 karakter olmalı; harf, rakam, "
            "nokta ve alt çizgi kullanabilirsiniz."
        )

    temiz_eposta = (eposta or "").strip().lower()
    simdi = time.time()

    with _lock, _baglan() as db:
        var = db.execute(
            "SELECT 1 FROM kullanicilar "
            "WHERE kullanici_adi = ? COLLATE NOCASE",
            (kullanici_adi,),
        ).fetchone()
        if var:
            raise KayitHatasi("Bu kullanıcı adı alınmış, başka bir tane seçin.")

        try:
            imlec = db.execute(
                "INSERT INTO kullanicilar "
                "(kullanici_adi, sifre_hash, olusturma, eposta, ad, soyad, "
                " eposta_dogrulandi, kayit_yolu, google_sub) "
                "VALUES (?, ?, ?, ?, ?, ?, 1, 'google', ?)",
                (
                    kullanici_adi,
                    generate_password_hash(secrets.token_urlsafe(32)),
                    simdi,
                    temiz_eposta,
                    ad,
                    soyad,
                    sub,
                ),
            )
        except sqlite3.IntegrityError:
            raise KayitHatasi(
                "Bu e-posta adresi ya da hesap zaten kayıtlı."
            )

        kullanici_id = imlec.lastrowid

    return _oturum_ac(kullanici_id), kullanici_adi


def kullanici_adi_musait_mi(kullanici_adi):
    """Kullanıcı adı alınmış mı (Google akışında ön denetim için)."""
    if not KULLANICI_ADI_DESENI.match(kullanici_adi or ""):
        return False
    with _lock, _baglan() as db:
        var = db.execute(
            "SELECT 1 FROM kullanicilar "
            "WHERE kullanici_adi = ? COLLATE NOCASE",
            (kullanici_adi,),
        ).fetchone()
    return var is None


def oturum_ac_kullanici(kullanici_id):
    """Var olan hesap için oturum anahtarı üretir (Google girişi)."""
    return _oturum_ac(kullanici_id)


# =====================================
# ŞİFRE SIFIRLAMA
# =====================================
# Doğrulama bağlantısından belirgin şekilde kısa. Bu bağlantı hesabı
# devralmaya yarıyor; posta kutusu bir süre açık kalmış bir bilgisayarda
# 24 saat boyunca geçerli olmasını istemiyoruz.
SIFRE_KODU_SURESI = 60 * 60          # 1 saat
SIFRE_KODU_BEKLEME = 120             # iki istek arası


def sifre_kodu_olustur(eposta):
    """E-posta adresine ait hesap için sıfırlama belirteci üretir.

    Döner: (token, kullanici_adi) ya da (None, None).

    ÇAĞIRAN TARAFA NOT: sonuç ne olursa olsun kullanıcıya aynı mesaj
    gösterilmeli. "Bu adres kayıtlı değil" demek, kimin üye olduğunu
    dışarıya sızdırır.
    """
    simdi = time.time()
    temiz = (eposta or "").strip().lower()
    if not temiz:
        return None, None

    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT id, kullanici_adi, kayit_yolu FROM kullanicilar "
            "WHERE eposta = ? COLLATE NOCASE",
            (temiz,),
        ).fetchone()

        if not satir:
            return None, None

        # Google ile açılmış hesabın şifresi yok; sıfırlanacak bir şey
        # de yok. (Faz 3 geldiğinde bu dal anlam kazanacak.)
        if satir["kayit_yolu"] == "google":
            return None, None

        son = db.execute(
            "SELECT olusturma FROM sifre_kodlari "
            "WHERE kullanici_id = ? ORDER BY olusturma DESC LIMIT 1",
            (satir["id"],),
        ).fetchone()
        if son and simdi - son["olusturma"] < SIFRE_KODU_BEKLEME:
            return None, None

        # Önceki bağlantılar geçersiz: aynı anda birden fazla geçerli
        # sıfırlama bağlantısı dolaşmasın.
        db.execute(
            "UPDATE sifre_kodlari SET kullanildi = 1 "
            "WHERE kullanici_id = ? AND kullanildi = 0",
            (satir["id"],),
        )

        token = secrets.token_urlsafe(32)
        db.execute(
            "INSERT INTO sifre_kodlari "
            "(token, kullanici_id, olusturma, son_gecerlilik) "
            "VALUES (?, ?, ?, ?)",
            (token, satir["id"], simdi, simdi + SIFRE_KODU_SURESI),
        )

    return token, satir["kullanici_adi"]


def sifre_kodu_gecerli_mi(token):
    """Belirteç kullanılabilir durumda mı (sayfayı göstermeden önce)."""
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT kullanildi, son_gecerlilik FROM sifre_kodlari "
            "WHERE token = ?",
            (token,),
        ).fetchone()
    return bool(
        satir
        and not satir["kullanildi"]
        and time.time() <= satir["son_gecerlilik"]
    )


def sifre_kodu_kullan(token, yeni_sifre):
    """Belirteci harcar ve şifreyi değiştirir.

    Bütün oturumlar da kapatılıyor. Sebep: şifreyi sıfırlatan kişi
    genelde hesabının başkasının elinde olmasından şüpheleniyor.
    Eski oturum anahtarları açık kalsaydı şifre değişse bile o kişi
    içeride kalırdı.
    """
    if len(yeni_sifre or "") < EN_KISA_SIFRE:
        raise KayitHatasi(
            "Şifre en az %d karakter olmalı." % EN_KISA_SIFRE
        )

    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT kullanici_id, kullanildi, son_gecerlilik "
            "FROM sifre_kodlari WHERE token = ?",
            (token,),
        ).fetchone()

        if not satir or satir["kullanildi"]:
            raise KayitHatasi(
                "Bu bağlantı geçersiz ya da daha önce kullanılmış. "
                "Yeniden şifre sıfırlama isteyebilirsiniz."
            )

        if time.time() > satir["son_gecerlilik"]:
            raise KayitHatasi(
                "Bu bağlantının süresi dolmuş. "
                "Yeniden şifre sıfırlama isteyebilirsiniz."
            )

        db.execute(
            "UPDATE kullanicilar SET sifre_hash = ? WHERE id = ?",
            (generate_password_hash(yeni_sifre), satir["kullanici_id"]),
        )
        db.execute(
            "UPDATE sifre_kodlari SET kullanildi = 1 WHERE token = ?",
            (token,),
        )
        db.execute(
            "DELETE FROM oturumlar WHERE kullanici_id = ?",
            (satir["kullanici_id"],),
        )

        ad = db.execute(
            "SELECT kullanici_adi FROM kullanicilar WHERE id = ?",
            (satir["kullanici_id"],),
        ).fetchone()

    return ad["kullanici_adi"] if ad else None


# =====================================
# YÖNETİM İŞLEMLERİ
# =====================================
def yonetici_mi(kullanici_adi):
    """Veritabanındaki yönetici bayrağını okur.

    Ortam değişkenindeki yönetici hesabı burada görünmeyebilir; onu
    app.py ayrıca denetliyor.
    """
    if not kullanici_adi:
        return False
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT yonetici FROM kullanicilar "
            "WHERE kullanici_adi = ? COLLATE NOCASE",
            (kullanici_adi,),
        ).fetchone()
    return bool(satir and satir["yonetici"])


def kullanici_getir(kullanici_id):
    """Tek kullanıcıyı döner (şifre hash'i olmadan) ya da None."""
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT id, kullanici_adi, ad, soyad, eposta, "
            "       eposta_dogrulandi, yonetici, gunluk_limit "
            "FROM kullanicilar WHERE id = ?",
            (kullanici_id,),
        ).fetchone()
    if not satir:
        return None
    return dict(satir)


def yonetici_ayarla(kullanici_id, deger):
    """Yönetici yetkisini verir ya da alır."""
    with _lock, _baglan() as db:
        imlec = db.execute(
            "UPDATE kullanicilar SET yonetici = ? WHERE id = ?",
            (1 if deger else 0, kullanici_id),
        )
    if not imlec.rowcount:
        raise KayitHatasi("Kullanıcı bulunamadı.")


def limit_ayarla(kullanici_id, deger):
    """Kişiye özel günlük hakkı ayarlar.

    deger None ise kişisel hak kaldırılır ve genel değer geçerli olur.
    0 geçerli bir değer: o kullanıcı üretim yapamaz.
    """
    if deger is not None:
        try:
            deger = int(deger)
        except (TypeError, ValueError):
            raise KayitHatasi("Günlük hak bir sayı olmalı.")
        if deger < 0 or deger > 10000:
            raise KayitHatasi("Günlük hak 0 ile 10000 arasında olmalı.")

    with _lock, _baglan() as db:
        imlec = db.execute(
            "UPDATE kullanicilar SET gunluk_limit = ? WHERE id = ?",
            (deger, kullanici_id),
        )
    if not imlec.rowcount:
        raise KayitHatasi("Kullanıcı bulunamadı.")


def sifre_dogru_mu(kullanici_id, sifre):
    """Verilen şifre bu hesabın şifresi mi.

    Kimlik numarasıyla çalışıyor: `giris_yap` kullanıcı adı istiyor,
    oysa oturum açmış kişinin numarası zaten elimizde. Hesap silme
    gibi geri dönüşü olmayan işlemlerde son bir onay için var.

    Google ile açılmış hesaplarda şifre alanı rastgele bir değerle
    dolu; bu fonksiyon oralarda her zaman False döner, çağıran taraf
    onu `kayit_yolu` ile ayırt etmeli.
    """
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT sifre_hash FROM kullanicilar WHERE id = ?",
            (kullanici_id,),
        ).fetchone()

    if not satir:
        return False
    return check_password_hash(satir["sifre_hash"], sifre or "")


def sil(kullanici_id):
    """Hesabı ve ona bağlı her şeyi siler.

    Oturumlar, kullanım sayaçları ve doğrulama kodları da gidiyor:
    yabancı anahtar kısıtı SQLite'ta varsayılan olarak zorlanmıyor,
    yani bunlar temizlenmezse veritabanında sahipsiz satırlar kalır.
    """
    with _lock, _baglan() as db:
        db.execute(
            "DELETE FROM oturumlar WHERE kullanici_id = ?", (kullanici_id,)
        )
        db.execute(
            "DELETE FROM kullanim WHERE kullanici_id = ?", (kullanici_id,)
        )
        db.execute(
            "DELETE FROM dogrulama_kodlari WHERE kullanici_id = ?",
            (kullanici_id,),
        )
        # Şifre sıfırlama bağlantıları da gidiyor: kalırlarsa silinmiş
        # bir numaraya işaret eden geçerli bağlantılar dolaşır.
        db.execute(
            "DELETE FROM sifre_kodlari WHERE kullanici_id = ?",
            (kullanici_id,),
        )
        imlec = db.execute(
            "DELETE FROM kullanicilar WHERE id = ?", (kullanici_id,)
        )
    if not imlec.rowcount:
        raise KayitHatasi("Kullanıcı bulunamadı.")
