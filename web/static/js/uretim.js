/* Site üzerinden görsel üretimi.
 *
 * Akış mobil uygulamanın "Oluştur" ekranıyla aynı: palet, desen,
 * desen yoğunluğu ve isteğe bağlı serbest metin seçiliyor; bunlar
 * tek bir Türkçe prompt'a birleştirilip sunucuya gönderiliyor.
 * Birleştirme kuralı uygulamadaki EbruViewModel.generateDesign ile
 * birebir aynı olmak zorunda, yoksa aynı seçim iki yerde farklı
 * sonuç verir.
 *
 * Üretim ~95 saniye sürdüğü için senkron /generate değil asenkron
 * /jobs kullanılıyor: iş numarası alınıyor, sonra durumu sorgulanıyor.
 * İş numarası tarayıcıda saklanıyor; sayfa yenilenirse üretim
 * kaybolmuyor, kaldığı yerden izlenmeye devam ediyor.
 */

(function () {
  'use strict';

  const ONIZLEME = '/static/onizleme/';
  const BEKLEYEN_IS = 'ebru_bekleyen_is';

  /* Palet kimlikleri sunucudaki COLOR_PROMPTS anahtarlarıyla ve
     uygulamadaki design_options.dart ile birebir aynı. */
  /* "Kendi rengim" ilk acildiginda gelen renkler: ebruda en sik
     kullanilan kizil-altin ikilisi. Bos kutularla acmak kullaniciyi
     bos ekranda birakiyordu. */
  const VARSAYILAN_OZEL_RENKLER = ['#C1272D', '#D4AF37'];

  const PALETLER = [
    { id: 'osmanli',       ad: 'Osmanlı',      aciklama: 'Kızıl, altın ve fildişi' },
    { id: 'zumrut',        ad: 'Zümrüt',       aciklama: 'Derin yeşil, altın damarlı' },
    { id: 'okyanus',       ad: 'Okyanus',      aciklama: 'Mavi tonları ve beyaz köpük' },
    { id: 'gece',          ad: 'Gece',         aciklama: 'Lacivert, gümüş ve mor' },
    { id: 'lale',          ad: 'Lale',         aciklama: 'Gül pembesi ve kızıl' },
    { id: 'pastel',        ad: 'Pastel',       aciklama: 'Yumuşak, soluk tonlar' },
    { id: 'sari-kirmizi',  ad: 'Sarı-Kırmızı', aciklama: 'Altın sarısı ve derin kırmızı' },
    { id: 'sari-lacivert', ad: 'Sarı-Lacivert', aciklama: 'Altın sarısı ve lacivert' },
    { id: 'siyah-beyaz',   ad: 'Siyah-Beyaz',  aciklama: 'Yüksek kontrast, tek renk' },
  ];

  /* id doğrudan prompt'a giriyor ("<id> deseninde"), slug dosya adında. */
  const DESENLER = [
    { id: 'battal',        ad: 'Battal',        slug: 'battal',        aciklama: 'Serbest damlatılmış organik lekeler' },
    { id: 'hatip',         ad: 'Hatip',         slug: 'hatip',         aciklama: 'Merkezî çiçek ve rozet motifi' },
    { id: 'taraklı',       ad: 'Taraklı',       slug: 'tarakli',       aciklama: 'Tarakla çekilmiş düzenli dalgalar' },
    { id: 'bülbül yuvası', ad: 'Bülbül yuvası', slug: 'bulbul_yuvasi', aciklama: 'İç içe sarmal girdaplar' },
    { id: 'gelgit',        ad: 'Gelgit',        slug: 'gelgit',        aciklama: 'İleri geri çekilmiş S kıvrımları' },
    { id: 'şal',           ad: 'Şal',           slug: 'sal',           aciklama: 'İç içe geçen tüy benzeri doku' },
  ];

  /* Sunucunun desteklediği çözünürlükler (app.py: SUPPORTED_SIZES).
     Oran gönderiliyor, sunucu en yakın boyutu seçiyor. */
  const ORANLAR = [
    { ad: 'Dikey', oran: 704 / 1024, olcu: '704×1024' },
    { ad: 'Kare',  oran: 1,          olcu: '768×768' },
    { ad: 'Yatay', oran: 1024 / 704, olcu: '1024×704' },
  ];

  const durum = {
    palet: 'osmanli',
    // Kullanicinin kendi sectigi renkler. Bos dizi -> hazir palet
    // gecerli. Doluysa sunucu hazir paleti yok sayiyor.
    ozelRenkler: [],
    desen: 'battal',
    yogunluk: 50,
    oran: ORANLAR[0].oran,
    uretiliyor: false,
    // Görseli üreten bilgisayar bağlı mı? Bilinene kadar "açık"
    // varsayılıyor: /health cevap vermeden butonu kilitlemek, üretim
    // aslında açıkken kullanıcıyı boşuna çevirirdi.
    uretimAcik: true,
  };

  /* --------------------------------------------------------------
     Yardımcılar
     -------------------------------------------------------------- */
  const $ = (id) => document.getElementById(id);

  function yogunlukEtiketi(deger) {
    if (deger < 30) return 'Çok hafif';
    if (deger < 50) return 'Hafif';
    if (deger < 70) return 'Dengeli';
    if (deger < 88) return 'Yoğun';
    return 'Çok yoğun';
  }

  function desenGorseli(desen, paletId) {
    return ONIZLEME + 'desen_' + paletId + '_' + desen.slug + '.jpg';
  }

  /* --------------------------------------------------------------
     Seçicileri kur
     -------------------------------------------------------------- */
  function paletleriCiz() {
    const kap = $('paletListesi');
    if (!kap) return;

    kap.innerHTML = '';
    PALETLER.forEach((palet) => {
      const dugme = document.createElement('button');
      dugme.type = 'button';
      dugme.className = 'palet-dugme flex flex-col items-center gap-xs shrink-0 focus:outline-none';
      dugme.setAttribute('aria-pressed', String(durum.palet === palet.id));
      dugme.title = palet.ad + ' — ' + palet.aciklama;
      dugme.innerHTML =
        '<span class="palet-halka block w-16 h-16 rounded-full overflow-hidden bg-surface-container">' +
        '<img class="palet-gorsel w-full h-full object-cover" alt="" loading="lazy" ' +
        'src="' + ONIZLEME + 'palet_' + palet.id + '.jpg">' +
        '</span>' +
        '<span class="palet-ad font-label-sm text-label-sm text-on-surface-variant whitespace-nowrap"></span>';
      dugme.querySelector('.palet-ad').textContent = palet.ad;

      dugme.addEventListener('click', () => {
        durum.palet = palet.id;
        paletleriTazele();
        desenleriTazele();
      });

      kap.appendChild(dugme);
    });

    kap.appendChild(ozelPaletDugmesi());
    ozelKutulariBagla();
    paletleriTazele();
  }

  /* Hazir paletlerin yanindaki "Kendi rengim" secenegi. */
  function ozelPaletDugmesi() {
    const dugme = document.createElement('button');
    dugme.type = 'button';
    dugme.id = 'ozelPaletDugmesi';
    dugme.className = 'palet-dugme flex flex-col items-center gap-xs shrink-0 focus:outline-none';
    dugme.title = 'Kendi renklerinizi secin';
    dugme.innerHTML =
      '<span class="palet-halka block w-16 h-16 rounded-full overflow-hidden ' +
      'flex items-center justify-center" id="ozelPaletHalka">' +
      '<span class="material-symbols-outlined text-[26px] text-on-surface">tune</span>' +
      '</span>' +
      '<span class="palet-ad font-label-sm text-label-sm text-on-surface-variant ' +
      'whitespace-nowrap">Kendi rengim</span>';

    dugme.addEventListener('click', () => {
      const acik = durum.ozelRenkler.length > 0;
      durum.ozelRenkler = acik ? [] : VARSAYILAN_OZEL_RENKLER.slice();
      ozelPaneliTazele();
      paletleriTazele();
    });
    return dugme;
  }

  function paletleriTazele() {
    const kap = $('paletListesi');
    if (!kap) return;

    const ozel = durum.ozelRenkler.length > 0;

    Array.from(kap.children).forEach((dugme, i) => {
      if (dugme.id === 'ozelPaletDugmesi') {
        dugme.setAttribute('aria-pressed', String(ozel));
        return;
      }
      // Ozel renk aciksa hazir paletlerin hicbiri secili gorunmemeli.
      dugme.setAttribute(
        'aria-pressed',
        String(!ozel && PALETLER[i] && PALETLER[i].id === durum.palet)
      );
    });

    const bilgi = $('paletAciklama');
    if (!bilgi) return;
    if (ozel) {
      bilgi.textContent = 'Kendi renkleriniz kullanilacak';
      return;
    }
    const secili = PALETLER.find((p) => p.id === durum.palet);
    if (secili) bilgi.textContent = secili.aciklama;
  }

  /* Renk kutularini bir kez dinlemeye al. */
  let _kutularBagli = false;

  function ozelKutulariBagla() {
    if (_kutularBagli) return;
    const panel = $('ozelRenkPaneli');
    if (!panel) return;
    _kutularBagli = true;

    const oku = () => {
      const ucuncu = $('ozelRenk3Acik');
      const renkler = [$('ozelRenk1').value, $('ozelRenk2').value];
      if (ucuncu && ucuncu.checked) renkler.push($('ozelRenk3').value);
      durum.ozelRenkler = renkler;
      ozelPaneliTazele();
      paletleriTazele();
    };

    panel.querySelectorAll('input').forEach((kutu) => {
      kutu.addEventListener('input', oku);
      kutu.addEventListener('change', oku);
    });
  }

  /* Renk kutulari: acik/kapali durumu ve degerleri. */
  function ozelPaneliTazele() {
    const panel = $('ozelRenkPaneli');
    if (!panel) return;

    const acik = durum.ozelRenkler.length > 0;
    // Gorunurluk sinifla yonetiliyor: "hidden" ozniteligi Tailwind'in
    // display siniflarini ezemiyor.
    panel.classList.toggle('hidden', !acik);
    panel.classList.toggle('flex', acik);

    const halka = $('ozelPaletHalka');
    if (halka) {
      halka.style.background = acik
        ? 'linear-gradient(135deg, ' + durum.ozelRenkler.join(', ') + ')'
        : '';
    }
    if (!acik) return;

    panel.querySelectorAll('input[type=color]').forEach((kutu, i) => {
      if (durum.ozelRenkler[i]) kutu.value = durum.ozelRenkler[i];
    });
  }

  function desenleriCiz() {
    const kap = $('desenListesi');
    if (!kap) return;

    kap.innerHTML = '';
    DESENLER.forEach((desen) => {
      const dugme = document.createElement('button');
      dugme.type = 'button';
      dugme.className =
        'desen-kart w-full flex items-center gap-sm p-base rounded-xl ' +
        'bg-surface-container-low text-left focus:outline-none';
      dugme.setAttribute('aria-pressed', String(durum.desen === desen.id));
      dugme.innerHTML =
        '<img class="desen-gorsel w-16 h-16 rounded-lg object-cover shrink-0 bg-surface-container" ' +
        'alt="" loading="lazy" src="' + desenGorseli(desen, durum.palet) + '">' +
        '<span class="flex-1 min-w-0">' +
        '<span class="block font-body-md text-body-md text-on-surface desen-ad"></span>' +
        '<span class="block font-label-sm text-label-sm text-outline desen-aciklama"></span>' +
        '</span>' +
        '<span class="desen-tik material-symbols-outlined text-gold">check_circle</span>';
      dugme.querySelector('.desen-ad').textContent = desen.ad;
      dugme.querySelector('.desen-aciklama').textContent = desen.aciklama;

      dugme.addEventListener('click', () => {
        durum.desen = desen.id;
        desenleriTazele();
      });

      kap.appendChild(dugme);
    });
  }

  function desenleriTazele() {
    const kap = $('desenListesi');
    if (!kap) return;

    Array.from(kap.children).forEach((dugme, i) => {
      const desen = DESENLER[i];
      dugme.setAttribute('aria-pressed', String(desen.id === durum.desen));
      // Örnek görsel seçili palete göre değişiyor: kullanıcı deseni
      // kendi renginde görsün.
      dugme.querySelector('img').src = desenGorseli(desen, durum.palet);
    });
  }

  /* Kaydirici: uygulamadaki Slider gibi 20 bolmeli (centikli) ve
     suruklerken deger balonu gosteriyor. Centiklerle balonun konumu
     tarayicinin thumb konumuyla ayni formulden hesaplaniyor:
     x = (deger/100) * (genislik - thumb) + thumb/2  */
  const THUMB = 20;

  function kaydiriciKonumu(kaydirici, deger) {
    const genislik = kaydirici.getBoundingClientRect().width;
    if (!genislik) return 0;
    return (deger / 100) * (genislik - THUMB) + THUMB / 2;
  }

  function kaydiriciyiKur() {
    const kaydirici = $('yogunluk');
    if (!kaydirici) return;

    const kap = kaydirici.closest('.kaydirici-kap');
    const balon = $('yogunlukBalon');
    const centikKap = $('yogunlukCentik');

    // 0'dan 100'e 5'er adim: uygulamadaki divisions: 20 ile ayni.
    const centikler = [];
    if (centikKap) {
      centikKap.innerHTML = '';
      for (let d = 0; d <= 100; d += 5) {
        const nokta = document.createElement('span');
        nokta.className = 'kaydirici-centik';
        nokta.dataset.deger = String(d);
        centikKap.appendChild(nokta);
        centikler.push(nokta);
      }
    }

    function yerlestir() {
      centikler.forEach((nokta) => {
        const d = Number(nokta.dataset.deger);
        nokta.style.left = kaydiriciKonumu(kaydirici, d) + 'px';
        nokta.classList.toggle('dolu', d <= durum.yogunluk);
      });
      if (balon) balon.style.left = kaydiriciKonumu(kaydirici, durum.yogunluk) + 'px';
    }

    function tazele() {
      durum.yogunluk = Number(kaydirici.value);
      kaydirici.style.setProperty('--dolu', durum.yogunluk + '%');
      const etiket = $('yogunlukEtiket');
      if (etiket) etiket.textContent = yogunlukEtiketi(durum.yogunluk);
      if (balon) balon.textContent = '%' + durum.yogunluk;
      yerlestir();
    }

    function balonuGoster(goster) {
      if (kap) kap.classList.toggle('etkin', goster);
    }

    kaydirici.addEventListener('input', tazele);
    kaydirici.addEventListener('pointerdown', () => balonuGoster(true));
    kaydirici.addEventListener('focus', () => balonuGoster(true));
    kaydirici.addEventListener('blur', () => balonuGoster(false));
    window.addEventListener('pointerup', () => balonuGoster(false));
    // Genislik degisince centikler kaymasin.
    window.addEventListener('resize', yerlestir);

    tazele();
  }

  function oranlariKur() {
    const kap = $('oranListesi');
    if (!kap) return;

    kap.innerHTML = '';
    ORANLAR.forEach((secenek, i) => {
      const dugme = document.createElement('button');
      dugme.type = 'button';
      dugme.className =
        'flex-1 py-base rounded-lg font-label-md text-label-md transition-colors ' +
        (i === 0
          ? 'bg-surface-container-high text-on-surface'
          : 'text-on-surface-variant hover:text-on-surface');
      dugme.textContent = secenek.ad;
      dugme.title = secenek.olcu;
      dugme.setAttribute('aria-pressed', String(i === 0));

      dugme.addEventListener('click', () => {
        durum.oran = secenek.oran;
        Array.from(kap.children).forEach((d, j) => {
          const etkin = i === j;
          d.setAttribute('aria-pressed', String(etkin));
          d.className =
            'flex-1 py-base rounded-lg font-label-md text-label-md transition-colors ' +
            (etkin
              ? 'bg-surface-container-high text-on-surface'
              : 'text-on-surface-variant hover:text-on-surface');
        });
      });

      kap.appendChild(dugme);
    });
  }

  /* --------------------------------------------------------------
     Ekran durumları
     -------------------------------------------------------------- */
  function ekraniGoster(hangi) {
    ['bosluk', 'yukleniyor', 'sonuc'].forEach((ad) => {
      const oge = $(ad);
      if (oge) oge.classList.toggle('hidden', ad !== hangi);
    });
  }

  function hataGoster(mesaj) {
    const kutu = $('hataKutusu');
    if (!kutu) return;
    kutu.textContent = mesaj;
    kutu.classList.remove('hidden');
  }

  function hatayiGizle() {
    const kutu = $('hataKutusu');
    if (kutu) kutu.classList.add('hidden');
  }

  function ilerlemeYaz(yuzde, mesaj) {
    const dolgu = $('ilerlemeDolgu');
    const oran = $('ilerlemeOran');
    const metin = $('ilerlemeMetin');
    if (dolgu) dolgu.style.width = Math.max(2, yuzde) + '%';
    if (oran) oran.textContent = yuzde > 0 ? '%' + yuzde : '';
    if (metin && mesaj) metin.textContent = mesaj;
  }

  function dugmeyiKilitle(kilitli) {
    const dugme = $('uretDugmesi');
    if (!dugme) return;

    // İki ayrı sebeple kilitlenebiliyor: üretim sürüyor olabilir ya da
    // üreten bilgisayar kapalı olabilir. İkisi de aynı butonu etkilediği
    // için karar tek yerde veriliyor, yoksa biri diğerinin metnini
    // eziyordu.
    const kapali = !durum.uretimAcik;
    dugme.disabled = kilitli || kapali;

    let metin = 'Ebruyu oluştur';
    if (kilitli) metin = 'Üretiliyor...';
    else if (kapali) metin = 'Üretim şu anda kapalı';

    dugme.querySelector('.dugme-metin').textContent = metin;
  }

  /* --------------------------------------------------------------
     Üretim sunucusunun durumu

     Site her zaman ayakta; görseli üreten bilgisayar ayrı ve yalnızca
     açıkken bağlı. Durum baştan gösteriliyor ki kullanıcı bütün
     seçimleri yapıp butona bastıktan sonra "kapalı" cevabı almasın.
     Düzenli aralıkla tazeleniyor: üretim açıldığında sayfayı
     yenilemek gerekmiyor.
     -------------------------------------------------------------- */
  const DURUM_ARALIGI = 30000;

  async function durumuSorgula() {
    let acik;
    try {
      const cevap = await fetch('/health');
      if (!cevap.ok) return;
      const veri = await cevap.json();
      acik = veri.ready !== false;
    } catch (hata) {
      // Sitenin kendisine ulaşılamıyorsa bunu "üretim kapalı" diye
      // göstermek yanıltıcı olur; eldeki duruma dokunma.
      return;
    }

    if (acik === durum.uretimAcik) return;
    durum.uretimAcik = acik;

    const uyari = $('uretimKapaliUyarisi');
    if (uyari) {
      uyari.classList.toggle('hidden', acik);
      uyari.classList.toggle('flex', !acik);
    }

    // Üretim sürerken buton zaten kilitli; metnini bozmamak için
    // yalnızca boştayken tazeleniyor.
    if (!durum.uretiliyor) dugmeyiKilitle(false);
  }

  /* --------------------------------------------------------------
     Üretim
     -------------------------------------------------------------- */
  function promptKur() {
    // Uygulamadaki birleştirmenin aynısı (EbruViewModel.generateDesign).
    const ek = ($('ekIstek') ? $('ekIstek').value.trim() : '');
    // Ozel renk secildiyse palet ifadesi yazilmiyor: sunucu renkleri
    // ayri alandan aliyor ve hazir paleti yok sayiyor. Yazilsaydi
    // kelime serbest metne dusup gereksiz yere cevrilirdi.
    const parcalar = [];
    if (durum.ozelRenkler.length === 0) {
      parcalar.push(durum.palet + ' renklerinde');
    }
    parcalar.push(durum.desen + ' deseninde');
    if (ek) parcalar.push(ek);
    return parcalar.join(', ');
  }

  async function isOlustur() {
    const cevap = await fetch('/jobs', {
      method: 'POST',
      headers: EbruHesap.basliklar(),
      body: JSON.stringify({
        prompt: promptKur(),
        intensity: durum.yogunluk,
        aspect_ratio: durum.oran,
        colors: durum.ozelRenkler,
      }),
    });

    const veri = await cevap.json().catch(() => ({}));

    if (cevap.status === 401) {
      EbruHesap.temizle();
      throw new Error('Oturumunuz sona ermiş. Lütfen tekrar giriş yapın.');
    }
    if (!cevap.ok) {
      throw new Error(veri.message || 'Üretim başlatılamadı.');
    }
    return veri;
  }

  async function sonucuBekle(jobId) {
    const bitis = Date.now() + 15 * 60 * 1000;

    while (Date.now() < bitis) {
      await new Promise((r) => setTimeout(r, 3000));

      let cevap;
      try {
        cevap = await fetch('/jobs/' + jobId, { headers: EbruHesap.basliklar() });
      } catch (e) {
        // Geçici ağ hatası üretimi iptal etmesin; iş sunucuda sürüyor.
        continue;
      }

      if (cevap.status === 404) {
        throw new Error('Bu üretimin kaydı sunucuda kalmamış.');
      }

      const veri = await cevap.json().catch(() => ({}));

      if (veri.job_status === 'done') return veri;
      if (veri.job_status === 'error') {
        throw new Error(veri.message || 'Üretim tamamlanamadı.');
      }

      const yuzde = Math.round((veri.progress || 0) * 100);
      if (veri.queue_length > 1) {
        ilerlemeYaz(yuzde, 'Sırada bekleniyor (' + veri.queue_length + ' iş)');
      } else if (veri.eta_seconds) {
        ilerlemeYaz(yuzde, 'Yaklaşık ' + Math.round(veri.eta_seconds) + ' saniye kaldı');
      } else {
        ilerlemeYaz(yuzde, 'Boyalar suya damlatılıyor...');
      }
    }

    throw new Error('Üretim çok uzun sürdü. Lütfen tekrar deneyin.');
  }

  function sonucuYaz(sonuc) {
    const gorsel = $('sonucGorsel');
    gorsel.src = sonuc.image;
    gorsel.classList.remove('eser-belir');
    // Sınıfı yeniden eklemek animasyonu baştan çalıştırıyor.
    void gorsel.offsetWidth;
    gorsel.classList.add('eser-belir');

    const paletAdi = (PALETLER.find((p) => p.id === durum.palet) || {}).ad || durum.palet;
    const desenAdi = (DESENLER.find((d) => d.id === durum.desen) || {}).ad || durum.desen;

    $('sonucPalet').textContent = paletAdi;
    $('sonucDesen').textContent = desenAdi;
    $('sonucYogunluk').textContent = '%' + durum.yogunluk + ' · ' + yogunlukEtiketi(durum.yogunluk);
    $('sonucBoyut').textContent = (sonuc.width || '?') + '×' + (sonuc.height || '?');
    $('sonucSeed').textContent = sonuc.seed != null ? sonuc.seed : '—';

    const indir = $('indirDugmesi');
    indir.onclick = () => {
      const bag = document.createElement('a');
      bag.href = gorsel.src;
      bag.download = 'ebru-' + (sonuc.seed != null ? sonuc.seed : Date.now()) + '.png';
      document.body.appendChild(bag);
      bag.click();
      document.body.removeChild(bag);
    };

    ekraniGoster('sonuc');
  }

  async function uret() {
    if (durum.uretiliyor) return;

    if (!EbruHesap.girisYapildiMi()) {
      location.href = '/giris?devam=' + encodeURIComponent('/#olustur');
      return;
    }

    durum.uretiliyor = true;
    hatayiGizle();
    dugmeyiKilitle(true);
    ilerlemeYaz(0, 'Sunucuya bağlanılıyor...');
    ekraniGoster('yukleniyor');

    try {
      const is = await isOlustur();
      localStorage.setItem(BEKLEYEN_IS, is.job_id);

      const sonuc = await sonucuBekle(is.job_id);
      localStorage.removeItem(BEKLEYEN_IS);
      sonucuYaz(sonuc);
    } catch (hata) {
      localStorage.removeItem(BEKLEYEN_IS);
      hataGoster(hata.message);
      ekraniGoster('bosluk');
    } finally {
      durum.uretiliyor = false;
      dugmeyiKilitle(false);
    }
  }

  /* Sayfa yenilendiğinde yarım kalan üretimi kaldığı yerden izler. */
  async function bekleyeniSurdur() {
    const jobId = localStorage.getItem(BEKLEYEN_IS);
    if (!jobId || !EbruHesap.girisYapildiMi()) return;

    durum.uretiliyor = true;
    dugmeyiKilitle(true);
    ilerlemeYaz(0, 'Süren üretim bulundu, izleniyor...');
    ekraniGoster('yukleniyor');

    try {
      const sonuc = await sonucuBekle(jobId);
      sonucuYaz(sonuc);
    } catch (hata) {
      // Kayıt düşmüşse sessizce boş ekrana dön: kullanıcı bir hata
      // yapmadı, iş sunucuda süresi dolduğu için silinmiş.
      ekraniGoster('bosluk');
    } finally {
      localStorage.removeItem(BEKLEYEN_IS);
      durum.uretiliyor = false;
      dugmeyiKilitle(false);
    }
  }

  /* Giris yapilmamissa panelin ustunde uyari gosterilir. Sunucu da
     giris istiyor (POST /jobs -> 401); bu yalnizca kullaniciyi
     bosuna secim yaptirip sonunda cevirmemek icin. */
  function girisDurumunuYansit() {
    const uyari = $('girisUyarisi');
    if (!uyari) return;
    uyari.classList.toggle('hidden', EbruHesap.girisYapildiMi());
    uyari.classList.toggle('flex', !EbruHesap.girisYapildiMi());
  }

  document.addEventListener('DOMContentLoaded', () => {
    if (!$('uretDugmesi')) return; // Üretim paneli bu sayfada yok.

    girisDurumunuYansit();

    paletleriCiz();
    desenleriCiz();
    kaydiriciyiKur();
    oranlariKur();

    $('uretDugmesi').addEventListener('click', uret);

    durumuSorgula();
    setInterval(durumuSorgula, DURUM_ARALIGI);

    const yeni = $('yeniDugmesi');
    if (yeni) {
      yeni.addEventListener('click', () => {
        ekraniGoster('bosluk');
        document.getElementById('olustur').scrollIntoView({ behavior: 'smooth' });
      });
    }

    const benzer = $('benzerDugmesi');
    if (benzer) benzer.addEventListener('click', uret);

    bekleyeniSurdur();
  });
})();
