# -*- coding: utf-8 -*-
"""Kullanicinin sectigi renkleri prompt tarifine cevirir.

Hazir paletler COLOR_PROMPTS'ta metin olarak duruyor. Kullanici kendi
rengini sectiginde elimizde yalnizca bir hex kodu oluyor; model ise
"deep crimson red" gibi bir ifade bekliyor. Burasi o cevirimi yapiyor.

Dev bir renk tablosu tutulmuyor: ton (hue), doygunluk ve aciklik
uzerinden siniflandiriliyor. Tablo yaklasimi ara tonlarda ("#8B4513
neydi?") tutarsiz isimler uretiyor, bu yontem her girdi icin ayni
mantikla calisiyor.
"""
import colorsys

# Ton araliklari: (ust_sinir_derece, ad). Sirali taranir.
# Ebruda sik gecen tonlara daha ozgul adlar verildi.
_TONLAR = (
    (10,  "red"),
    (20,  "vermilion"),
    (33,  "orange"),
    (45,  "amber"),
    (60,  "gold"),
    (72,  "yellow"),
    (90,  "chartreuse"),
    (150, "green"),
    (168, "emerald green"),
    (186, "teal"),
    (200, "cyan"),
    (218, "azure blue"),
    (243, "blue"),
    (260, "indigo"),
    (285, "violet"),
    (310, "purple"),
    (330, "magenta"),
    (345, "crimson"),
    (360, "red"),
)

# Griler icin aciklik araliklari.
_GRILER = (
    (0.08, "near-black"),
    (0.22, "charcoal grey"),
    (0.42, "slate grey"),
    (0.62, "soft grey"),
    (0.82, "pale grey"),
    (1.01, "ivory white"),
)


def _hex_coz(deger):
    """'#a1b2c3' -> (161, 178, 195). Gecersizse None."""
    if not deger:
        return None
    s = str(deger).strip().lstrip("#")
    if len(s) == 3:                      # kisa yazim: #abc
        s = "".join(h * 2 for h in s)
    if len(s) != 6:
        return None
    try:
        return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def renk_adi(deger):
    """Hex kodu -> Ingilizce renk ifadesi. Gecersizse None."""
    rgb = _hex_coz(deger)
    if rgb is None:
        return None

    r, g, b = (k / 255.0 for k in rgb)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    ton = h * 360.0

    # Doygunluk cok dusukse renk degil, gri tonu.
    if s < 0.12:
        for sinir, ad in _GRILER:
            if l < sinir:
                return ad
        return "ivory white"

    temel = next(ad for sinir, ad in _TONLAR if ton < sinir)

    # Ozel adi olan bolgeler. Ton + aciklik birlikte bakilmadan
    # bulunamiyorlar: kahverengi "koyu turuncu", pembe "acik kirmizi"
    # olarak cikiyordu ve model ikisini de yanlis anliyordu.
    # Kahverengiyi bordodan TON ayiriyor, doygunluk degil: kahverengi
    # koyu turuncudur (ton ~25), bordo koyu kirmizidir (ton ~0).
    # Doygunluk sarti denendi, saddle brown'i disarida biraktigi icin
    # kaldirildi.
    if 8 <= ton < 50 and l < 0.36:
        return "dark brown" if l < 0.22 else "brown"
    if (ton < 12 or ton >= 320) and l > 0.72:
        return "rose pink"
    if 45 <= ton < 75 and l > 0.80 and s < 0.62:
        return "cream ivory"

    # Aciklik ve doygunluga gore niteleme.
    if l < 0.25:
        return "deep %s" % temel
    if l > 0.82:
        return "pale %s" % temel
    if s < 0.35:
        return "muted %s" % temel
    if s > 0.75 and l < 0.55:
        return "vivid %s" % temel
    return temel


def palet_tarifi(renkler):
    """Hex listesi -> "x, y and z color palette". Gecersizse None.

    Ebruda genellikle iki uc renk kullaniliyor; liste o yuzden kisa
    tutuluyor. Ayni ada cikan renkler tekrar edilmiyor.
    """
    if not renkler:
        return None

    adlar = []
    for deger in renkler[:3]:
        ad = renk_adi(deger)
        if ad and ad not in adlar:
            adlar.append(ad)

    if not adlar:
        return None
    if len(adlar) == 1:
        return "%s color palette" % adlar[0]
    return "%s and %s color palette" % (", ".join(adlar[:-1]), adlar[-1])
