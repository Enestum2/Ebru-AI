/* Site tarafi hesap islemleri.
   Oturum anahtari localStorage'da tutuluyor ve uretim isteklerinde
   Authorization basligiyla gonderiliyor. */

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
        if (this.token()) {
            b['Authorization'] = 'Bearer ' + this.token();
        }
        return b;
    },

    async cikis() {
        try {
            await fetch('/auth/logout', {
                method: 'POST',
                headers: this.basliklar(),
            });
        } catch (e) {
            // Sunucuya ulasilamasa da yerel oturum temizlenir.
        }
        this.temizle();
        location.href = '/';
    },

    /* Ust menuye hesap durumunu yerlestirir. */
    menuyuGuncelle() {
        const nav = document.querySelector('#mainHeader nav ul');
        if (!nav) return;

        const li = document.createElement('li');
        if (this.girisYapildiMi()) {
            li.innerHTML =
                '<span class="hesap-durum">' +
                '<span class="kullanici">' + this.kullaniciAdi() + '</span>' +
                '<a href="#" id="cikisBtn">Çıkış</a></span>';
            nav.appendChild(li);
            document.getElementById('cikisBtn')
                .addEventListener('click', (e) => {
                    e.preventDefault();
                    this.cikis();
                });
        } else {
            li.innerHTML = '<a href="/giris">Giriş</a>';
            nav.appendChild(li);
        }
    },
};

document.addEventListener('DOMContentLoaded', () => {
    EbruHesap.menuyuGuncelle();

    const form = document.getElementById('hesapForm');
    if (!form) return;

    // Giris sayfasindayiz.
    let kayitKipi = false;

    const baslik = document.getElementById('baslik');
    const altBaslik = document.getElementById('altBaslik');
    const gecisMetin = document.getElementById('gecisMetin');
    const gecisBtn = document.getElementById('gecisBtn');
    const gonderBtn = document.getElementById('gonderBtn');
    const hataKutusu = document.getElementById('hataKutusu');
    const kayitIpucu = document.getElementById('kayitIpucu');

    function kipiUygula() {
        baslik.textContent = kayitKipi ? 'Hesap Oluştur' : 'Giriş Yap';
        altBaslik.textContent = kayitKipi
            ? 'Ücretsiz hesap aç, eser üretmeye başla.'
            : 'Eser üretmek için hesabına giriş yap.';
        gonderBtn.textContent = kayitKipi ? 'Hesap Oluştur' : 'Giriş Yap';
        gecisMetin.textContent = kayitKipi
            ? 'Zaten hesabın var mı?'
            : 'Hesabın yok mu?';
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
        gonderBtn.textContent = 'Gönderiliyor...';

        const govde = {
            username: document.getElementById('kullaniciAdi').value.trim(),
            password: document.getElementById('sifre').value,
        };

        try {
            const cevap = await fetch(
                kayitKipi ? '/auth/register' : '/auth/login',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(govde),
                }
            );
            const veri = await cevap.json();

            if (cevap.ok && veri.token) {
                EbruHesap.kaydet(veri.token, veri.username);
                location.href = '/';
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
