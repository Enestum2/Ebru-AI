/* Site geneli davranışlar: menü, kaydırınca beliren bölümler,
 * yazı makinesi başlıkları.
 *
 * Sayfaya özel iş yok — üretim akışı uretim.js'te, hesap işleri
 * hesap.js'te.
 */

(function () {
  'use strict';

  /* --------------------------------------------------------------
     Küçük ekran menüsü
     -------------------------------------------------------------- */
  function menuyuKur() {
    const dugme = document.getElementById('menuDugmesi');
    const menu = document.getElementById('mobilMenu');
    if (!dugme || !menu) return;

    dugme.addEventListener('click', () => {
      const acik = !menu.classList.contains('hidden');
      menu.classList.toggle('hidden', acik);
      dugme.setAttribute('aria-expanded', String(!acik));
      dugme.querySelector('.material-symbols-outlined').textContent =
        acik ? 'menu' : 'close';
    });

    // Bağlantıya basınca menü kapansın.
    menu.querySelectorAll('a').forEach((a) => {
      a.addEventListener('click', () => {
        menu.classList.add('hidden');
        dugme.setAttribute('aria-expanded', 'false');
        dugme.querySelector('.material-symbols-outlined').textContent = 'menu';
      });
    });
  }

  /* --------------------------------------------------------------
     Kaydırınca beliren bölümler

     IntersectionObserver yoksa (çok eski tarayıcı) hepsi doğrudan
     görünür yapılıyor — içerik gizli kalmasın.
     -------------------------------------------------------------- */
  function belirmeyiKur() {
    const ogeler = document.querySelectorAll('.ac');
    if (!ogeler.length) return;

    if (!('IntersectionObserver' in window)) {
      ogeler.forEach((o) => o.classList.add('gorundu'));
      return;
    }

    // Gozlemcinin hic calisip calismadigini anlamak icin bayrak.
    let bildirdi = false;

    const gozlemci = new IntersectionObserver(
      (girisler) => {
        bildirdi = true;
        girisler.forEach((giris) => {
          if (!giris.isIntersecting) return;
          giris.target.classList.add('gorundu');
          gozlemci.unobserve(giris.target);
        });
      },
      { rootMargin: '0px 0px -10% 0px', threshold: 0.12 }
    );

    ogeler.forEach((o) => gozlemci.observe(o));

    /* Guvenlik agi: gozlemci hicbir sey bildirmediyse (ornegin sayfa
       hic cizilmeyen bir sekmede acildiysa) icerik gizli kalmasin.
       Normal kullanimda gozlemci bu sure dolmadan calisir ve buraya
       girilmez. */
    setTimeout(() => {
      if (bildirdi) return;
      document.querySelectorAll('.ac').forEach((o) => o.classList.add('gorundu'));
    }, 3000);
  }

  /* --------------------------------------------------------------
     Yazı makinesi başlıkları

     Metin data-yazi özniteliğinde duruyor; JavaScript kapalıysa
     bile içerik kaybolmasın diye öğenin kendi metni de aynı.
     -------------------------------------------------------------- */
  function yaziMakinesiKur() {
    const ogeler = document.querySelectorAll('[data-yazi]');
    if (!ogeler.length || !('IntersectionObserver' in window)) return;

    const azHareket = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (azHareket) return;

    const gozlemci = new IntersectionObserver((girisler) => {
      girisler.forEach((giris) => {
        if (!giris.isIntersecting) return;

        const oge = giris.target;
        gozlemci.unobserve(oge);

        const metin = oge.dataset.yazi;
        oge.textContent = '';
        oge.classList.add('imlec');

        let i = 0;
        const hiz = metin.length > 120 ? 12 : 26;
        const sayac = setInterval(() => {
          oge.textContent = metin.slice(0, ++i);
          if (i >= metin.length) {
            clearInterval(sayac);
            oge.classList.remove('imlec');
          }
        }, hiz);
      });
    }, { threshold: 0.4 });

    ogeler.forEach((o) => gozlemci.observe(o));
  }

  document.addEventListener('DOMContentLoaded', () => {
    menuyuKur();
    belirmeyiKur();
    yaziMakinesiKur();
  });
})();
