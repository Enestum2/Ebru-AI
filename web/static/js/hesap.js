/* Hesap işlemleri.
 *
 * Oturum anahtarı localStorage'da tutuluyor ve üretim isteklerinde
 * Authorization başlığıyla gönderiliyor. Sunucu tarafı sözleşmesi
 * değişmedi: /auth/register, /auth/login, /auth/logout.
 */

const EbruHesap = {
  tokenAnahtari: 'ebru_token',
  adAnahtari: 'ebru_kullanici',

  token() {
    return localStorage.getItem(this.tokenAnahtari) || '';
  },

  kullaniciAdi() {
    return localStorage.getItem(this.adAnahtari) || '';
  },

  girisYapildiMi() {
    return this.token() !== '';
  },

  kaydet(token, ad) {
    localStorage.setItem(this.tokenAnahtari, token);
    localStorage.setItem(this.adAnahtari, ad);
  },

  temizle() {
    localStorage.removeItem(this.tokenAnahtari);
    localStorage.removeItem(this.adAnahtari);
  },

  basliklar() {
    const b = { 'Content-Type': 'application/json' };
    if (this.token()) b['Authorization'] = 'Bearer ' + this.token();
    return b;
  },

  async cikis() {
    try {
      await fetch('/auth/logout', { method: 'POST', headers: this.basliklar() });
    } catch (e) {
      // Sunucuya ulaşılamasa da yerel oturum temizlenir.
    }
    this.temizle();
    location.href = '/';
  },

  /* Üst çubuktaki hesap alanını dolduruyor. */
  basligiKur() {
    const alan = document.getElementById('hesapAlani');
    if (!alan) return;

    if (!this.girisYapildiMi()) {
      alan.innerHTML =
        '<a href="/giris" class="px-md py-base rounded-full bg-surface-container ' +
        'hover:bg-surface-container-high text-on-surface font-label-md text-label-md ' +
        'transition-colors flex items-center gap-xs">' +
        '<span class="material-symbols-outlined text-[18px]">login</span>' +
        '<span class="hidden sm:inline">Giriş</span></a>';
      return;
    }

    const ad = this.kullaniciAdi();
    const bas = ad ? ad.charAt(0).toLocaleUpperCase('tr') : '?';

    // Profil simgesi bir menü açıyor: küçük ekranda kullanıcı adı
    // başlıkta zaten görünmüyordu, hesap işlemleri de bir yerde
    // toplanmış oluyor.
    alan.innerHTML =
      '<div class="relative flex items-center gap-sm">' +
      '<div class="hidden sm:flex flex-col items-end leading-tight">' +
      '<span class="font-label-sm text-label-sm text-on-surface-variant">Merhaba</span>' +
      '<span class="font-label-md text-label-md text-on-surface" id="hesapAd"></span>' +
      '</div>' +
      '<button id="hesapDugmesi" type="button" title="Hesabım" ' +
      'aria-haspopup="true" aria-expanded="false" ' +
      'class="w-10 h-10 rounded-full bg-gold/20 ring-1 ring-gold/40 hover:bg-gold/30 ' +
      'transition-colors flex items-center justify-center text-gold ' +
      'font-label-md text-label-md"></button>' +
      '<div id="hesapMenu" role="menu" ' +
      'class="hidden absolute right-0 top-full mt-xs w-56 z-50 rounded-xl ' +
      'bg-surface-container-lowest border border-white/10 shadow-2xl overflow-hidden">' +
      '<div class="px-sm py-sm border-b border-white/10">' +
      '<p class="font-label-sm text-label-sm text-on-surface-variant">Giriş yapıldı</p>' +
      '<p class="font-label-md text-label-md text-on-surface truncate" id="hesapMenuAd"></p>' +
      '</div>' +
      '<a href="/hesap-sil" role="menuitem" ' +
      'class="w-full px-sm py-sm flex items-center gap-xs text-left ' +
      'font-label-md text-label-md text-error hover:bg-error/10 transition-colors">' +
      '<span class="material-symbols-outlined text-[18px]">delete_forever</span>' +
      'Hesabımı sil</a>' +
      '<button id="cikisDugmesi" type="button" role="menuitem" ' +
      'class="w-full px-sm py-sm flex items-center gap-xs text-left ' +
      'font-label-md text-label-md text-on-surface-variant ' +
      'hover:bg-white/5 hover:text-on-surface transition-colors border-t border-white/10">' +
      '<span class="material-symbols-outlined text-[18px]">logout</span>' +
      'Çıkış yap</button>' +
      '</div>' +
      '</div>';

    // Kullanıcı adı metin olarak yazılıyor: adın içindeki karakterler
    // işaretleme olarak yorumlanmasın.
    alan.querySelector('#hesapAd').textContent = ad;
    alan.querySelector('#hesapMenuAd').textContent = ad;

    const dugme = alan.querySelector('#hesapDugmesi');
    const menu = alan.querySelector('#hesapMenu');
    dugme.textContent = bas;

    // Görünürlük sınıfla yönetiliyor: "hidden" özniteliği Tailwind'in
    // display sınıflarını ezemiyor.
    const menuyuKapat = () => {
      menu.classList.add('hidden');
      dugme.setAttribute('aria-expanded', 'false');
    };

    dugme.addEventListener('click', (olay) => {
      olay.stopPropagation();
      const acik = !menu.classList.contains('hidden');
      menu.classList.toggle('hidden', acik);
      dugme.setAttribute('aria-expanded', acik ? 'false' : 'true');
    });

    // Menü dışına tıklayınca ve Esc ile kapanıyor.
    document.addEventListener('click', (olay) => {
      if (!menu.contains(olay.target)) menuyuKapat();
    });
    document.addEventListener('keydown', (olay) => {
      if (olay.key === 'Escape') menuyuKapat();
    });

    alan.querySelector('#cikisDugmesi').addEventListener('click', () => this.cikis());
  },
};

/* Yönetici hesabıyla girildiyse menüye "Yönetim" bağlantısı ekler.
   Aynı istek oturumun hâlâ geçerli olduğunu da doğruluyor: sunucu
   401 dönerse yerel oturum temizleniyor, yoksa kullanıcı giriş
   yapmış görünüp her üretimde hata alıyordu. */
EbruHesap.yoneticiKontrol = async function () {
  if (!this.girisYapildiMi()) return;

  let veri;
  try {
    const cevap = await fetch('/auth/me', { headers: this.basliklar() });
    if (cevap.status === 401) {
      this.temizle();
      this.basligiKur();
      return;
    }
    if (!cevap.ok) return;
    veri = await cevap.json();
  } catch (e) {
    return; // Sunucuya ulaşılamıyorsa menüyü olduğu gibi bırak.
  }

  if (!veri || !veri.is_admin) return;

  const ekle = (kap, sinif) => {
    if (!kap || kap.querySelector('[data-yonetim]')) return;
    const bag = document.createElement('a');
    bag.href = '/admin';
    bag.dataset.yonetim = '1';
    bag.className = sinif;
    bag.textContent = 'Yönetim';
    kap.appendChild(bag);
  };

  // Kimlikle seçiliyor: sınıf adında iki nokta olduğu için
  // ("lg:flex") kaçış gerekiyordu ve JavaScript metni kaçışı yiyip
  // geçersiz seçici üretiyordu; fonksiyon orada hata verip bağlantıyı
  // hiç eklemiyordu.
  ekle(
    document.getElementById('anaMenu'),
    'font-label-md text-label-md text-gold hover:text-ivory transition-colors'
  );
  ekle(
    document.getElementById('mobilMenuIcerik'),
    'py-sm font-label-md text-label-md text-gold hover:text-ivory transition-colors'
  );
};

document.addEventListener('DOMContentLoaded', () => {
  EbruHesap.basligiKur();
  EbruHesap.yoneticiKontrol();

  const form = document.getElementById('hesapForm');
  if (!form) return;

  // Giriş sayfasındayız.
  let kayitKipi = false;

  const baslik = document.getElementById('baslik');
  const altBaslik = document.getElementById('altBaslik');
  const gecisMetin = document.getElementById('gecisMetin');
  const gecisBtn = document.getElementById('gecisBtn');
  const gonderBtn = document.getElementById('gonderBtn');
  const hataKutusu = document.getElementById('hataKutusu');
  const kayitIpucu = document.getElementById('kayitIpucu');
  const kayitAlanlari = document.getElementById('kayitAlanlari');

  // Kayit kipinde zorunlu olan alanlar. Giris kipinde hem gizleniyor
  // hem de "required" kaldiriliyor; gizli bir zorunlu alan tarayicida
  // gonderimi sessizce kilitliyor.
  const kayitGirdileri = ['ad', 'soyad', 'eposta']
    .map((k) => document.getElementById(k))
    .filter(Boolean);

  function kipiUygula() {
    baslik.textContent = kayitKipi ? 'Hesap oluştur' : 'Giriş yap';
    altBaslik.textContent = kayitKipi
      ? 'Ücretsiz hesap açın, eser üretmeye başlayın.'
      : 'Eser üretmek için hesabınıza giriş yapın.';
    gonderBtn.querySelector('.dugme-metin').textContent =
      kayitKipi ? 'Hesap oluştur' : 'Giriş yap';
    gecisMetin.textContent = kayitKipi ? 'Zaten hesabınız var mı?' : 'Hesabınız yok mu?';
    gecisBtn.textContent = kayitKipi ? 'Giriş yap' : 'Kayıt ol';
    kayitIpucu.hidden = !kayitKipi;
    hataKutusu.hidden = true;

    // Gorunurluk SINIFLA yonetiliyor: "hidden" OZNITELIGI
    // Tailwind'in display siniflarini ezemiyor (tarayici
    // varsayilani daha dusuk oncelikli). Olcumle goruldu:
    // oznitelik true iken hesaplanan display hala "flex"ti,
    // yani alanlar giris kipinde de ekranda kaliyordu.
    const sifreUnuttumSatiri = document.getElementById('sifreUnuttumSatiri');
    if (sifreUnuttumSatiri) sifreUnuttumSatiri.classList.toggle('hidden', kayitKipi);
    if (kayitAlanlari) {
      kayitAlanlari.classList.toggle('hidden', !kayitKipi);
      kayitAlanlari.classList.toggle('flex', kayitKipi);
    }
    kayitGirdileri.forEach((girdi) => {
      girdi.required = kayitKipi;
      if (!kayitKipi) girdi.value = '';
    });

    document.getElementById('sifre').autocomplete =
      kayitKipi ? 'new-password' : 'current-password';
  }

  gecisBtn.addEventListener('click', (e) => {
    e.preventDefault();
    kayitKipi = !kayitKipi;
    kipiUygula();
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    hataKutusu.hidden = true;
    gonderBtn.disabled = true;
    gonderBtn.querySelector('.dugme-metin').textContent = 'Gönderiliyor...';

    const govde = {
      username: document.getElementById('kullaniciAdi').value.trim(),
      password: document.getElementById('sifre').value,
    };

    // Ad, soyad ve e-posta yalnizca kayitta gonderiliyor. Sunucu
    // bunlari zorunlu tutuyor; giriste beklemiyor.
    if (kayitKipi) {
      govde.first_name = document.getElementById('ad').value.trim();
      govde.last_name = document.getElementById('soyad').value.trim();
      govde.email = document.getElementById('eposta').value.trim();
    }

    try {
      const cevap = await fetch(kayitKipi ? '/auth/register' : '/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(govde),
      });
      const veri = await cevap.json();

      if (cevap.ok && veri.token) {
        EbruHesap.kaydet(veri.token, veri.username);

        // E-postasi onaylanmamis hesap uretim yapamiyor; onu
        // yonlendirmek yerine onay ekraninda tutuyoruz.
        // Dogrulanmamis hesap uretim yapamiyor; onu Olustur
        // ekranina gondermek 403 ile sonuclanirdi. Ne yapmasi
        // gerektigini anlatan sayfaya yonlendiriliyor.
        if (veri.email_verified === false) {
          location.href = '/onay-bekleniyor';
          return;
        }

        // Giriş sayfasına nereden gelindiyse oraya dön.
        const hedef = new URLSearchParams(location.search).get('devam');
        location.href = hedef && hedef.startsWith('/') ? hedef : '/';
        return;
      }

      hataKutusu.textContent = veri.message || 'İşlem başarısız.';
      hataKutusu.hidden = false;
    } catch (hata) {
      hataKutusu.textContent = 'Sunucuya ulaşılamadı.';
      hataKutusu.hidden = false;
    } finally {
      gonderBtn.disabled = false;
      kipiUygula();
    }
  });

  /* --------------------------------------------------------------
     Sifremi unuttum
     -------------------------------------------------------------- */
  const sifreUnuttumBtn = document.getElementById('sifreUnuttumBtn');
  const sifirlamaPaneli = document.getElementById('sifirlamaPaneli');
  const sifirlamaDurum = document.getElementById('sifirlamaDurum');
  const sifirlamaGonderBtn = document.getElementById('sifirlamaGonderBtn');
  const sifirlamaVazgecBtn = document.getElementById('sifirlamaVazgecBtn');
  const sifirlamaEposta = document.getElementById('sifirlamaEposta');

  /* Gorunurluk SINIFLA: "hidden" oznitelig Tailwind'in display
     siniflarini ezemiyor. */
  function goster(oge, gorunsun, kip) {
    if (!oge) return;
    oge.classList.toggle('hidden', !gorunsun);
    oge.classList.toggle(kip || 'block', gorunsun);
  }

  function sifirlamaEkrani(acik) {
    goster(form, !acik, 'flex');
    goster(gecisSatiri, !acik);
    goster(document.getElementById('sifreUnuttumSatiri'), !acik);
    goster(sifirlamaPaneli, acik, 'flex');
    // Google bolumu de gizlenmeli: sifre sifirlama ekraninda
    // "Google ile devam et" dugmesi baglami bozuyor.
    const gb = document.getElementById('googleBolumu');
    if (gb && !gb.dataset.kapali) goster(gb, !acik, 'flex');
    if (acik && sifirlamaEposta) sifirlamaEposta.focus();
  }

  function sifirlamaDurumGoster(mesaj, hataMi) {
    sifirlamaDurum.textContent = mesaj;
    sifirlamaDurum.classList.remove('hidden');
    sifirlamaDurum.classList.add('border');
    sifirlamaDurum.classList.toggle('bg-error/10', hataMi);
    sifirlamaDurum.classList.toggle('border-error/30', hataMi);
    sifirlamaDurum.classList.toggle('text-error', hataMi);
    sifirlamaDurum.classList.toggle('bg-gold/10', !hataMi);
    sifirlamaDurum.classList.toggle('border-gold/30', !hataMi);
    sifirlamaDurum.classList.toggle('text-on-surface', !hataMi);
  }

  if (sifreUnuttumBtn) {
    sifreUnuttumBtn.addEventListener('click', (e) => {
      e.preventDefault();
      sifirlamaEkrani(true);
    });
  }

  if (sifirlamaVazgecBtn) {
    sifirlamaVazgecBtn.addEventListener('click', (e) => {
      e.preventDefault();
      sifirlamaEkrani(false);
    });
  }

  if (sifirlamaGonderBtn) {
    sifirlamaGonderBtn.addEventListener('click', async () => {
      const adres = (sifirlamaEposta.value || '').trim();
      if (!adres) {
        sifirlamaDurumGoster('E-posta adresinizi yazın.', true);
        return;
      }

      sifirlamaGonderBtn.disabled = true;
      sifirlamaGonderBtn.querySelector('.dugme-metin').textContent = 'Gonderiliyor...';

      try {
        const cevap = await fetch('/auth/sifre-unuttum', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: adres }),
        });
        const veri = await cevap.json().catch(() => ({}));
        /* Sunucu adres kayitli olsa da olmasa da ayni cevabi donuyor;
           kimin uye oldugunu disariya sizdirmamak icin. */
        sifirlamaDurumGoster(veri.message || 'Istek alindi.', !cevap.ok);
      } catch (hata) {
        sifirlamaDurumGoster('Sunucuya ulasilamadi.', true);
      } finally {
        sifirlamaGonderBtn.disabled = false;
        sifirlamaGonderBtn.querySelector('.dugme-metin').textContent = 'Baglanti gonder';
      }
    });
  }

  /* --------------------------------------------------------------
     Google ile giris

     Akis: Google dugmesi bir kimlik belirteci veriyor, biz onu
     sunucuya yolluyoruz. Sunucu uc cevaptan birini donuyor:
       success            -> giris tamam
       username_required  -> yeni kullanici, ad secmesi gerekiyor
       error              -> mesaji goster
     -------------------------------------------------------------- */
  const googleBolumu = document.getElementById('googleBolumu');
  const googleAdPaneli = document.getElementById('googleAdPaneli');
  const googleDurum = document.getElementById('googleDurum');
  const googleAdDurum = document.getElementById('googleAdDurum');
  const googleAdKaydetBtn = document.getElementById('googleAdKaydetBtn');
  const googleKullaniciAdi = document.getElementById('googleKullaniciAdi');

  /* Belirteci saklıyoruz: kullanici adi secildikten sonra ikinci
     istekte tekrar gonderilecek ve sunucuda yeniden dogrulanacak.
     Boylece sunucuda "bekleyen kayit" diye bir durum tutmuyoruz. */
  let googleBelirteci = null;
  // Sunucu "kapali" derse bolum hic acilmiyor; sifirlama
  // ekrani kapandiginda yanlislikla gorunur olmasin.
  if (googleBolumu) googleBolumu.dataset.kapali = '1';

  function kutuGoster(kutu, mesaj, hataMi) {
    if (!kutu) return;
    kutu.textContent = mesaj;
    kutu.classList.remove('hidden');
    kutu.classList.add('border');
    kutu.classList.toggle('bg-error/10', hataMi);
    kutu.classList.toggle('border-error/30', hataMi);
    kutu.classList.toggle('text-error', hataMi);
    kutu.classList.toggle('bg-gold/10', !hataMi);
    kutu.classList.toggle('border-gold/30', !hataMi);
    kutu.classList.toggle('text-on-surface', !hataMi);
  }

  function girisTamamlandi(veri) {
    EbruHesap.kaydet(veri.token, veri.username);
    if (veri.email_verified === false) {
      location.href = '/onay-bekleniyor';
      return;
    }
    const hedef = new URLSearchParams(location.search).get('devam');
    location.href = hedef && hedef.startsWith('/') ? hedef : '/';
  }

  async function googleCevabi(cevap) {
    googleBelirteci = cevap.credential;
    kutuGoster(googleDurum, 'Google ile giriş yapılıyor...', false);

    try {
      const istek = await fetch('/auth/google', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ credential: googleBelirteci }),
      });
      const veri = await istek.json().catch(() => ({}));

      if (veri.status === 'success') {
        girisTamamlandi(veri);
        return;
      }

      if (veri.status === 'username_required') {
        googleDurum.classList.add('hidden');
        goster(form, false, 'flex');
        goster(gecisSatiri, false);
        goster(document.getElementById('sifreUnuttumSatiri'), false);
        goster(googleBolumu, false, 'flex');
        goster(googleAdPaneli, true, 'flex');
        document.getElementById('googleAdEposta').textContent = veri.email || '';
        googleKullaniciAdi.value = veri.suggested || '';
        googleKullaniciAdi.focus();
        return;
      }

      kutuGoster(googleDurum, veri.message || 'Google girişi başarısız.', true);
    } catch (hata) {
      kutuGoster(googleDurum, 'Sunucuya ulaşılamadı.', true);
    }
  }

  if (googleAdKaydetBtn) {
    googleAdKaydetBtn.addEventListener('click', async () => {
      const ad = (googleKullaniciAdi.value || '').trim();
      if (!ad) {
        kutuGoster(googleAdDurum, 'Kullanıcı adı yaz.', true);
        return;
      }

      googleAdKaydetBtn.disabled = true;
      googleAdKaydetBtn.querySelector('.dugme-metin').textContent = 'Oluşturuluyor...';

      try {
        const istek = await fetch('/auth/google/kullanici-adi', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ credential: googleBelirteci, username: ad }),
        });
        const veri = await istek.json().catch(() => ({}));
        if (veri.status === 'success') {
          girisTamamlandi(veri);
          return;
        }
        kutuGoster(googleAdDurum, veri.message || 'Hesap oluşturulamadı.', true);
      } catch (hata) {
        kutuGoster(googleAdDurum, 'Sunucuya ulaşılamadı.', true);
      } finally {
        googleAdKaydetBtn.disabled = false;
        googleAdKaydetBtn.querySelector('.dugme-metin').textContent = 'Hesabı oluştur';
      }
    });
  }

  /* Google dugmesini yalnizca sunucu "acik" derse kuruyoruz. */
  (async () => {
    let durum;
    try {
      durum = await fetch('/auth/google/durum').then((c) => c.json());
    } catch (hata) {
      return;
    }
    if (!durum.enabled || !durum.client_id) return;

    const betik = document.createElement('script');
    betik.src = 'https://accounts.google.com/gsi/client';
    betik.async = true;
    betik.defer = true;
    betik.onload = () => {
      if (!window.google || !google.accounts) return;
      google.accounts.id.initialize({
        client_id: durum.client_id,
        callback: googleCevabi,
      });
      google.accounts.id.renderButton(
        document.getElementById('googleDugme'),
        { theme: 'filled_black', size: 'large', shape: 'pill',
          text: 'continue_with', locale: 'tr', width: 300 }
      );
      delete googleBolumu.dataset.kapali;
      goster(googleBolumu, true, 'flex');
    };
    document.head.appendChild(betik);
  })();

  kipiUygula();
});
