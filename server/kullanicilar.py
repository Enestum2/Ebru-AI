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


def kur():
    """Tabloları oluşturur. Her açılışta çağrılabilir."""
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


class KayitHatasi(Exception):
    """Kullanıcıya gösterilebilecek kayıt/giriş hatası."""


def _dogrula(kullanici_adi, sifre):
    if not KULLANICI_ADI_DESENI.match(kullanici_adi or ""):
        raise KayitHatasi(
            "Kullanıcı adı 3-24 karakter olmalı; harf, rakam, "
            "nokta ve alt çizgi kullanabilirsin."
        )
    if len(sifre or "") < EN_KISA_SIFRE:
        raise KayitHatasi(
            f"Şifre en az {EN_KISA_SIFRE} karakter olmalı."
        )


def kayit_ol(kullanici_adi, sifre):
    """Yeni hesap oluşturur ve oturum anahtarı döner."""
    kullanici_adi = (kullanici_adi or "").strip()
    _dogrula(kullanici_adi, sifre)

    with _lock, _baglan() as db:
        mevcut = db.execute(
            "SELECT 1 FROM kullanicilar WHERE kullanici_adi = ? COLLATE NOCASE",
            (kullanici_adi,),
        ).fetchone()
        if mevcut:
            raise KayitHatasi("Bu kullanıcı adı zaten alınmış.")

        imlec = db.execute(
            "INSERT INTO kullanicilar "
            "(kullanici_adi, sifre_hash, olusturma) VALUES (?, ?, ?)",
            (kullanici_adi, generate_password_hash(sifre), time.time()),
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
            "       k.kullanici_adi "
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
    }


def cikis_yap(token):
    with _lock, _baglan() as db:
        db.execute("DELETE FROM oturumlar WHERE token = ?", (token,))


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


def kullanici_sayisi():
    with _lock, _baglan() as db:
        satir = db.execute(
            "SELECT COUNT(*) AS n FROM kullanicilar"
        ).fetchone()
    return satir["n"]
