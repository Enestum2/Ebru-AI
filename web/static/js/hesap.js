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

    alan.innerHTML =
      '<div class="flex items-center gap-sm">' +
      '<div class="hidden sm:flex flex-col items-end leading-tight">' +
      '<span class="font-label-sm text-label-sm text-on-surface-variant">Merhaba</span>' +
      '<span class="font-label-md text-label-md text-on-surface" id="hesapAd"></span>' +
      '</div>' +
      '<div class="w-10 h-10 rounded-full bg-gold/20 ring-1 ring-gold/40 flex items-center ' +
      'justify-center text-gold font-label-md text-label-md" id="hesapBas"></div>' +
      '<button id="cikisDugmesi" title="Çıkış yap" ' +
      'class="w-10 h-10 rounded-full bg-surface-container hover:bg-surface-container-high ' +
      'text-on-surface-variant hover:text-error transition-colors flex items-center justify-center">' +
      '<span class="material-symbols-outlined text-[20px]">logout</span></button>' +
      '</div>';

    // Kullanıcı adı metin olarak yazılıyor: adın içindeki karakterler
    // işaretleme olarak yorumlanmasın.
    alan.querySelector('#hesapAd').textContent = ad;
    alan.querySelector('#hesapBas').textContent = bas;

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

  function kipiUygula() {
    baslik.textContent = kayitKipi ? 'Hesap oluştur' : 'Giriş yap';
    altBaslik.textContent = kayitKipi
      ? 'Ücretsiz hesap aç, eser üretmeye başla.'
      : 'Eser üretmek için hesabına giriş yap.';
    gonderBtn.querySelector('.dugme-metin').textContent =
      kayitKipi ? 'Hesap oluştur' : 'Giriş yap';
    gecisMetin.textContent = kayitKipi ? 'Zaten hesabın var mı?' : 'Hesabın yok mu?';
    gecisBtn.textContent = kayitKipi ? 'Giriş yap' : 'Kayıt ol';
    kayitIpucu.hidden = !kayitKipi;
    hataKutusu.hidden = true;

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

    try {
      const cevap = await fetch(kayitKipi ? '/auth/register' : '/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(govde),
      });
      const veri = await cevap.json();

      if (cevap.ok && veri.token) {
        EbruHesap.kaydet(veri.token, veri.username);
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

  kipiUygula();
});
