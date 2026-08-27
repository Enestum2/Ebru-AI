# -*- coding: utf-8 -*-
"""Dagitimdan once calisan denetim.

Amaci tek: bozuk kodun sunucuya gitmesini engellemek. Sunucuda soz
dizimi hatasi olan bir dosya varsa `ebru.service` hic kalkamiyor ve
site 502 veriyor; hata mesaji da ancak sunucu gunlugunde goruluyor.

Iki sey deneniyor:
  1. Python dosyalari derleniyor (calistirilmiyor - yan etkisi yok).
  2. Jinja sablonlari ayristiriliyor. Bozuk bir sablon servisi
     dusurmuyor ama o sayfayi 500 yapiyor.

Cikis kodu 0 ise dagitim yapilabilir, 1 ise YAPILMAMALI.
"""
import os
import py_compile
import sys

BURASI = os.path.dirname(os.path.abspath(__file__))

# Sunucuya giden Python dosyalari. Olmayan dosya atlanıyor: depo
# duzeni degisirse denetim bosuna alarm vermesin.
PYTHON_DOSYALARI = (
    "app.py",
    "kullanicilar.py",
    "eposta.py",
    "google_giris.py",
    "uretim_isci.py",
)


def web_klasoru():
    """app.py ile ayni mantik; ikisi ayrisirsa denetim yaniltici olur."""
    elle = os.environ.get("EBRU_WEB_DIR")
    if elle:
        return elle

    adaylar = (
        os.path.join(BURASI, "..", "web"),
        os.path.join(BURASI, "..", "..", "..", "Ebru_Web"),
    )
    for aday in adaylar:
        if os.path.isdir(os.path.join(aday, "templates")):
            return os.path.normpath(aday)
    return None


def python_denetle():
    hatalar = []
    for ad in PYTHON_DOSYALARI:
        yol = os.path.join(BURASI, ad)
        if not os.path.exists(yol):
            continue
        try:
            py_compile.compile(yol, doraise=True)
        except py_compile.PyCompileError as e:
            hatalar.append((ad, str(e).strip()))
    return hatalar


def sablon_denetle():
    kok = web_klasoru()
    if not kok:
        print("  ! Web klasoru bulunamadi, sablon denetimi atlandi")
        return []

    try:
        from jinja2 import Environment, FileSystemLoader, TemplateSyntaxError
    except ImportError:
        print("  ! jinja2 yok, sablon denetimi atlandi")
        return []

    ortam = Environment(loader=FileSystemLoader(os.path.join(kok, "templates")))
    hatalar = []
    for ad in sorted(ortam.list_templates()):
        try:
            ortam.get_template(ad)
        except TemplateSyntaxError as e:
            hatalar.append((ad, "satir %s: %s" % (e.lineno, e.message)))
        except Exception as e:                      # noqa: BLE001
            hatalar.append((ad, str(e)))
    return hatalar


def main():
    print("  Python dosyalari...")
    hatalar = python_denetle()

    print("  Jinja sablonlari...")
    hatalar += sablon_denetle()

    if not hatalar:
        print("  temiz")
        return 0

    print("")
    for ad, mesaj in hatalar:
        print("  HATA  %s" % ad)
        for satir in mesaj.splitlines():
            print("        %s" % satir)
    return 1


if __name__ == "__main__":
    sys.exit(main())
