import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

import '../models/ebru_design_model.dart';
import '../models/generation_request_model.dart';
import '../services/api_service.dart';
import '../services/google_giris_servisi.dart';
import '../services/notification_service.dart';
import '../services/server_directory.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';

/// Ana ekran, sonuç ekranı ve galeri arasında paylaşılan state.
class EbruViewModel extends ChangeNotifier {
  // Dart alt çizgiyle başlayan adlandırılmış parametreye izin vermediği
  // için alanlar gövdede atanıyor.
  late final SettingsService _settings;
  late final StorageService _storage;
  late final NotificationService _notifications;
  late ApiService _api;

  EbruViewModel({
    required SettingsService settings,
    required StorageService storage,
    required NotificationService notifications,
  }) {
    _settings = settings;
    _storage = storage;
    _notifications = notifications;
    _api = ApiService(
      baseUrl: _settings.serverUrl,
      deviceId: _settings.deviceId,
      sessionToken: _settings.sessionToken,
    );
    _loadHistory();
    _acilistaHazirla();
  }

  final ServerDirectory _directory = ServerDirectory();

  /// Açılış sırası önemli: önce güncel adres öğreniliyor, sonra sunucu
  /// yoklanıyor. Ters sırada, adres değişmişse eski adrese sorulup
  /// boşuna "sunucu kapalı" deniyor.
  Future<void> _acilistaHazirla() async {
    await refreshServerAddress();
    await refreshServerStatus();
  }

  // ---------------------------------------------------------------
  // Oturum
  // ---------------------------------------------------------------

  bool get isLoggedIn => _settings.sessionToken.isNotEmpty;
  String get username => _settings.username;

  /// Kayıtlı oturumun sunucuda hâlâ geçerli olduğunu doğrular.
  /// Ağ hatasında oturumu bozmuyor — çevrimdışı kullanıcı atılmamalı.
  Future<bool> validateSession() async {
    if (!isLoggedIn) return false;

    final sonuc = await _api.sessionValid();
    if (!sonuc.valid) {
      await _settings.clearSession();
      _api.sessionToken = '';
      notifyListeners();
      return false;
    }

    // Yöneticilik sunucudan geliyor; hesap yetkisi değişmişse yansısın.
    // Yetki artık panelden verilip alınabildiği için bu her açılışta
    // gerçekten değişebiliyor.
    if (sonuc.isAdmin != _settings.isAdmin) {
      await _settings.setIsAdmin(sonuc.isAdmin);
      notifyListeners();
    }

    if (sonuc.emailVerified != epostaOnayli || sonuc.email != eposta) {
      epostaOnayli = sonuc.emailVerified;
      eposta = sonuc.email;
      notifyListeners();
    }

    if (sonuc.hasPassword != sifresiVar) {
      sifresiVar = sonuc.hasPassword;
      notifyListeners();
    }
    return true;
  }

  /// Hesabın kullanılabilir bir şifresi var mı.
  ///
  /// Google ile açılmış hesaplarda yok; hesap silme ekranı o zaman
  /// şifre yerine kullanıcı adı onayı istiyor. Sunucudan geliyor,
  /// varsayılan "var": eski sunucuya bağlanıldığında şifre sorulması
  /// daha güvenli davranış.
  bool sifresiVar = true;

  /// E-posta onaylanmadan üretim yapılamıyor; ekranlar buna bakıyor.
  bool epostaOnayli = true;
  String? eposta;

  Future<void> register(
    String username,
    String password, {
    required String ad,
    required String soyad,
    required String epostaAdresi,
  }) async {
    final sonuc = await _api.register(
      username,
      password,
      ad: ad,
      soyad: soyad,
      eposta: epostaAdresi,
    );
    eposta = epostaAdresi;
    await _oturumKaydet(sonuc);
  }

  Future<void> login(String username, String password) async {
    final sonuc = await _api.login(username, password);
    await _oturumKaydet(sonuc);
  }

  /// Google ile giriş. Kullanıcı adı gerekiyorsa oturum açılmıyor.
  Future<GoogleGirisSonucu> googleGiris(String idToken) async {
    final sonuc = await _api.googleGiris(idToken);
    if (!sonuc.kullaniciAdiGerekiyor) {
      await _oturumKaydet(sonuc.oturum!);
    }
    return sonuc;
  }

  Future<void> googleKullaniciAdi(String idToken, String kullaniciAdi) async {
    final sonuc = await _api.googleKullaniciAdi(idToken, kullaniciAdi);
    await _oturumKaydet(sonuc);
  }

  Future<String> dogrulamaGonder() => _api.dogrulamaGonder();

  // --- Google ile giris ---
  final GoogleGirisServisi _google = GoogleGirisServisi();

  /// Google girisi kullanilabilir mi. Sunucu kapali derse dugme hic
  /// gosterilmiyor; calismayan bir dugme kullaniciyi bosuna ugrastirir.
  bool googleKullanilabilir = false;

  Future<void> googleHazirla() async {
    final durum = await _api.googleDurum();
    if (!durum.enabled || durum.clientId.isEmpty) {
      googleKullanilabilir = false;
      notifyListeners();
      return;
    }
    try {
      await _google.hazirla(durum.clientId);
      googleKullanilabilir = true;
    } catch (_) {
      // Eklenti hazirlanamadiysa dugmeyi gostermiyoruz.
      googleKullanilabilir = false;
    }
    notifyListeners();
  }

  /// Google hesabi sectirip belirteci doner. Vazgecilirse null.
  Future<String?> googleBelirtecAl() => _google.belirtecAl();

  Future<void> _oturumKaydet(AuthResult sonuc) async {
    await _settings.saveSession(
      sonuc.token,
      sonuc.username,
      isAdmin: sonuc.isAdmin,
    );
    _api.sessionToken = sonuc.token;
    epostaOnayli = sonuc.emailVerified;
    notifyListeners();
  }

  Future<void> logout() async {
    // Google oturumu da birakiliyor: yoksa bir sonraki giriste hesap
    // secme ekrani hic cikmiyor ve baska hesapla girmek mumkun olmuyor.
    await _google.cikis();
    await _api.logout();
    await _settings.clearSession();
    _api.sessionToken = '';
    notifyListeners();
  }

  /// Hesabı sunucudan kalıcı olarak siler ve oturumu kapatır.
  ///
  /// Sunucu reddederse (şifre yanlış, kurucu yönetici) hata yukarı
  /// fırlıyor ve yerel oturuma dokunulmuyor: hesap duruyorsa kullanıcı
  /// da uygulamadan atılmamalı.
  Future<void> hesabimiSil({String? sifre, String? onay}) async {
    await _api.hesabimiSil(sifre: sifre, onay: onay);

    // Sunucudaki oturum silme sırasında zaten kapandı; buradan sonrası
    // çıkışla aynı temizlik.
    await _google.cikis();
    await _settings.clearSession();
    _api.sessionToken = '';
    notifyListeners();
  }

  // --- Üretim durumu ---
  bool isLoading = false;
  String? errorMessage;
  EbruDesignModel? currentDesign;

  double progress = 0.0;
  double? etaSeconds;
  int queueLength = 0;

  // --- Sunucu durumu ---
  ServerStatus? serverStatus;
  bool isCheckingServer = false;

  /// Uygulama arka planda mı. Bildirimi yalnızca kullanıcı ekranda
  /// değilken göstermek için tutuluyor.
  bool _arkaPlanda = false;

  void setArkaPlanda(bool deger) => _arkaPlanda = deger;

  /// Kullanıcı uygulamaya döndüğünde bekleyen bildirimi kaldırır.
  void bildirimleriTemizle() => unawaited(_notifications.temizle());

  /// Bildirim iznini ilk girişten sonra ister.
  Future<void> bildirimIzniIste() => _notifications.izinIste();

  // --- Seçimler ---
  String selectedPalette = 'osmanli';

  /// Kullanıcının kendi seçtiği renkler. Boşsa hazır palet geçerli.
  /// Doluyken hazır palet seçimi görselde hiç kullanılmıyor.
  List<String> ozelRenkler = const [];

  bool get ozelRenkAcik => ozelRenkler.isNotEmpty;

  void setOzelRenkler(List<String> renkler) {
    ozelRenkler = renkler;
    notifyListeners();
  }

  void ozelRenkleriKapat() {
    ozelRenkler = const [];
    notifyListeners();
  }
  String selectedStyle = 'battal';
  String promptTr = '';

  /// Desen yoğunluğu (0-100) — sunucuda LoRA ağırlığına dönüşüyor.
  /// 50 varsayılanı ölçümlerde dengeli sonuç veren orta bant.
  int intensity = 50;

  /// Kaydırıcının o anki konumunun ne anlama geldiği.
  String get intensityLabel {
    if (intensity < 30) return 'Çok hafif';
    if (intensity < 50) return 'Hafif';
    if (intensity < 70) return 'Dengeli';
    if (intensity < 88) return 'Yoğun';
    return 'Çok yoğun';
  }

  // --- Galeri ---
  List<EbruDesignModel> history = [];
  bool showFavoritesOnly = false;

  String get serverUrl => _settings.serverUrl;

  List<EbruDesignModel> get visibleHistory => showFavoritesOnly
      ? history.where((d) => d.isFavorite).toList()
      : history;

  int get favoriteCount => history.where((d) => d.isFavorite).length;

  Future<void> _loadHistory() async {
    history = await _storage.getAllDesigns();
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // Sunucu
  // ---------------------------------------------------------------

  /// Kullanılan adresin nereden geldiği — ayarlar ekranında gösteriliyor.
  ServerUrlSource get serverUrlSource => _settings.serverUrlSource;

  /// Sunucu kapalıyken gösterilecek açıklama; adres dosyasından geliyor.
  String get serverMessage => _settings.directoryMessage;

  /// Uzaktaki adres dosyasını okur, adres değiştiyse uygular.
  ///
  /// Kullanıcı ayarlar ekranından kendi adresini yazmışsa sonuç yine
  /// saklanıyor ama kullanılmıyor; elle yazılan adres önceliğini
  /// koruyor (bkz. SettingsService.serverUrl).
  Future<void> refreshServerAddress() async {
    final sonuc = await _directory.fetch();
    if (sonuc == null) return;

    final oncekiAdres = _settings.serverUrl;
    await _settings.saveDiscoveredServerUrl(sonuc.url, sonuc.message);

    if (_settings.serverUrl != oncekiAdres) {
      _api = ApiService(
        baseUrl: _settings.serverUrl,
        deviceId: _settings.deviceId,
        sessionToken: _settings.sessionToken,
      );
    }
    notifyListeners();
  }

  /// Sunucunun üretime hazır olup olmadığını kontrol eder.
  Future<void> refreshServerStatus() async {
    isCheckingServer = true;
    notifyListeners();

    serverStatus = await _api.checkHealth();

    isCheckingServer = false;
    notifyListeners();
  }

  /// Sunucu adresini değiştirir ve yeni adresi hemen dener.
  Future<void> setServerUrl(String url) async {
    await _settings.setServerUrl(url);
    _api = ApiService(
      baseUrl: _settings.serverUrl,
      deviceId: _settings.deviceId,
      sessionToken: _settings.sessionToken,
    );
    await refreshServerStatus();
  }

  /// Elle yazılan adresi siler.
  ///
  /// Eskiden burada varsayılan adres `setServerUrl` ile yazılıyordu;
  /// bu da onu yeniden "elle yazılmış" saydığı için uygulama bir daha
  /// uzaktan öğrenilen adrese geçemiyordu. Artık kayıt siliniyor ve
  /// sıra yeniden uzaktan öğrenilen adrese düşüyor.
  Future<void> resetServerUrl() async {
    await _settings.resetServerUrl();
    _api = ApiService(
      baseUrl: _settings.serverUrl,
      deviceId: _settings.deviceId,
      sessionToken: _settings.sessionToken,
    );
    await refreshServerAddress();
    await refreshServerStatus();
  }

  // ---------------------------------------------------------------
  // Seçimler
  // ---------------------------------------------------------------

  void setPalette(String palette) {
    selectedPalette = palette;
    notifyListeners();
  }

  void setStyle(String style) {
    selectedStyle = style;
    notifyListeners();
  }

  void setIntensity(int value) {
    intensity = value;
    notifyListeners();
  }

  void setPrompt(String prompt) {
    // Her harfte tüm ekranı yeniden çizmeye gerek yok.
    promptTr = prompt;
  }

  // ---------------------------------------------------------------
  // Üretim
  // ---------------------------------------------------------------

  /// Üretim isteğini backend'e gönderir.
  ///
  /// [aspectRatio] telefon ekranının en/boy oranı; gönderilirse duvar
  /// kağıdı kırpılmadan oturur. [seed] verilirse aynı tasarım tekrar
  /// üretilir.
  /// [palet], [desen] ve [ekIstek] verilirse o anki seçimlerin yerine
  /// kullanılır. Sonuç ekranındaki "Yeni eser" ve "Benzerini üret"
  /// düğmeleri bunu kullanıyor: bakılan eserin kendi ayarlarıyla üretmek
  /// gerekiyor. Eskiden bu düğmeler her zaman güncel seçimleri
  /// kullanıyordu, yani baykuşa girip "Benzerini üret"e basınca en son
  /// hangi paleti seçtiysen ondan bir görsel çıkıyordu.
  Future<void> generateDesign({
    double? aspectRatio,
    int? seed,
    String? palet,
    String? desen,
    String? ekIstek,
  }) async {
    // Yarım kalmış bir üretim varsa önce onu tamamla, yenisini açma.
    // Bağlantı koptuktan sonra basılan her "üret", sunucuda ayrı bir iş
    // açıyor ve aynı üretimden kuyrukta birden fazla birikiyordu.
    if (_settings.pendingJobId.isNotEmpty) {
      final tamamlandi = await resumePendingJob(sessiz: false);

      // Kayıt hâlâ duruyorsa bağlantı sorunu var demektir; iş sunucuda
      // sürüyor, ikincisini açmıyoruz. Kayıt düşmüşse sunucuda öyle bir
      // iş kalmamış, aşağıdan yeni üretim başlatılabilir.
      if (tamamlandi || _settings.pendingJobId.isNotEmpty) return;
    }

    isLoading = true;
    errorMessage = null;
    progress = 0.0;
    etaSeconds = null;
    queueLength = 0;
    notifyListeners();

    // Bir kez çözülüp her yerde aynısı kullanılıyor: prompt, yarım
    // kalan iş kaydı ve kaydedilen eserin üstverisi tutarlı olmalı.
    final etkinPalet = palet ?? selectedPalette;
    final etkinDesen = desen ?? selectedStyle;
    final etkinIstek = ekIstek ?? promptTr;

    try {
      // Backend tek bir Türkçe prompt bekliyor; seçimler burada
      // birleştiriliyor. Sözlükteki anahtarlarla aynı kelimeler
      // kullanılıyor ki prompt motoru bunları yakalayabilsin.
      // Özel renk seçiliyse palet ifadesi yazılmıyor: sunucu renkleri
      // ayrı alandan alıyor ve hazır paleti yok sayıyor. Yazılsaydı
      // kelime serbest metne düşüp gereksiz yere çevrilirdi.
      final parcalar = <String>[
        if (ozelRenkler.isEmpty) '$etkinPalet renklerinde',
        '$etkinDesen deseninde',
        if (etkinIstek.isNotEmpty) etkinIstek,
      ];

      final request = GenerationRequestModel(
        prompt: parcalar.join(', '),
        aspectRatio: aspectRatio,
        seed: seed,
        intensity: intensity,
        colors: ozelRenkler,
      );

      final sonuc = await _api.generateDesign(
        request,
        onProgress: _ilerlemeGuncelle,
        // İş numarası hemen kaydediliyor: kullanıcı uygulamadan
        // çıkarsa sunucu üretimi bitirir, biz de açılışta sonucu
        // buradan alırız.
        onJobCreated: (jobId) {
          _settings.savePendingJob(
            jobId,
            '$etkinPalet|$etkinDesen|$etkinIstek',
          );
        },
      );

      await _settings.clearPendingJob();

      final design = await _storage.saveNewDesign(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imageBase64: sonuc.imageBase64,
        colorTheme: etkinPalet,
        style: etkinDesen,
        promptTr: etkinIstek,
        promptEn: sonuc.promptEn,
        seed: sonuc.seed,
        width: sonuc.width,
        height: sonuc.height,
      );

      currentDesign = design;
      history.insert(0, design);
      await _galeriyeKopyala(design);

      // Kullanıcı bu sırada uygulamadan çıkmış olabilir.
      if (_arkaPlanda) {
        unawaited(_notifications.uretimBitti());
      }

      // Üretim başarılıysa sunucu ayakta demektir. Önceden yalnızca
      // hata durumunda tazeleniyordu; bu yüzden bir kez düşmüş
      // bağlantının uyarı şeridi başarılı üretimden sonra da ekranda
      // kalıyordu.
      if (serverStatus?.ready != true) {
        unawaited(refreshServerStatus());
      }
    } on ApiException catch (e) {
      errorMessage = e.message;
      // Bağlantı koptuysa iş kaydı SİLİNMİYOR: üretim sunucuda sürüyor
      // ve uygulamaya dönüldüğünde resumePendingJob onu tamamlıyor.
      // Eskiden burada koşulsuz siliniyordu; bu yüzden kullanıcı tekrar
      // denediğinde aynı üretim ikinci kez kuyruğa giriyordu.
      if (!e.gecici) {
        await _settings.clearPendingJob();
      }
      unawaited(refreshServerStatus());
    } catch (e) {
      errorMessage = 'Beklenmeyen bir hata oluştu: $e';
      await _settings.clearPendingJob();
    } finally {
      isLoading = false;
      progress = 0.0;
      notifyListeners();
    }
  }

  void _ilerlemeGuncelle(GenerationProgress bilgi) {
    progress = bilgi.progress.clamp(0.0, 1.0);
    etaSeconds = bilgi.etaSeconds;
    queueLength = bilgi.queueLength;
    notifyListeners();
  }

  /// Uygulama kapatılırken yarım kalan bir üretim varsa devam ettirir.
  ///
  /// Sunucu işi zaten tamamlıyor; burada yalnızca sonucu alıp
  /// kaydediyoruz. Açılışta ve arka plandan dönüşte çağrılıyor.
  /// Üretim tamamlanıp kaydedildiyse true döner.
  ///
  /// [sessiz] arka plandan dönüşte true: kullanıcı bu üretimi beklemiyor,
  /// hata mesajı basmak kafa karıştırır. Kullanıcı "üret"e bastığı için
  /// çağrılıyorsa false verilip sonuç ekrana yansıtılıyor.
  Future<bool> resumePendingJob({bool sessiz = true}) async {
    final jobId = _settings.pendingJobId;
    if (jobId.isEmpty || isLoading) return false;

    final meta = _settings.pendingJobMeta.split('|');
    final palet = meta.isNotEmpty ? meta[0] : selectedPalette;
    final desen = meta.length > 1 ? meta[1] : selectedStyle;
    final ekIstek = meta.length > 2 ? meta[2] : '';

    isLoading = true;
    errorMessage = null;
    progress = 0.0;
    notifyListeners();

    var basarili = false;

    try {
      final sonuc = await _api.waitForJob(
        jobId,
        onProgress: _ilerlemeGuncelle,
      );

      final design = await _storage.saveNewDesign(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imageBase64: sonuc.imageBase64,
        colorTheme: palet,
        style: desen,
        promptTr: ekIstek,
        promptEn: sonuc.promptEn,
        seed: sonuc.seed,
        width: sonuc.width,
        height: sonuc.height,
      );

      currentDesign = design;
      history.insert(0, design);
      await _settings.clearPendingJob();
      basarili = true;
      await _galeriyeKopyala(design);

      // Kullanıcı uygulamada değilken bittiyse haber ver.
      unawaited(_notifications.uretimBitti());
    } on ApiException catch (e) {
      debugPrint('Yarım kalan iş kurtarılamadı: ${e.message}');

      // Kullanıcı bu üretimi kendisi başlatmadıysa ekrana hata basmak
      // kafa karıştırıyor; arka plandan dönüşte sessiz kalıyoruz.
      if (!sessiz) errorMessage = e.message;

      // Bağlantı sorunuysa kayıt duruyor, sonraki denemede
      // kurtarılabilir. Yalnızca sunucu "böyle bir iş yok" ya da
      // "üretim başarısız" dediğinde siliniyor.
      if (!e.gecici) {
        await _settings.clearPendingJob();
      }
    } catch (e) {
      debugPrint('Yarım kalan iş kurtarılamadı: $e');
      if (!sessiz) errorMessage = 'Beklenmeyen bir hata oluştu: $e';
      await _settings.clearPendingJob();
    } finally {
      isLoading = false;
      progress = 0.0;
      notifyListeners();
    }

    return basarili;
  }

  // ---------------------------------------------------------------
  // Galeri
  // ---------------------------------------------------------------

  // ---------------------------------------------------------------
  // İzleme (yalnızca yönetici)
  // ---------------------------------------------------------------

  /// İzleme ekranına erişim yetkisi. Sunucu, giriş yapan hesabın
  /// yönetici olup olmadığını bildiriyor; kullanıcının ayrıca bir
  /// anahtar girmesi gerekmiyor.
  bool get isAdmin => _settings.isAdmin;

  /// Sunucudaki kullanım istatistiklerini çeker.
  Future<UsageStats> fetchStats() => _api.fetchStats();

  /// Bekleyen ve süren üretimler.
  Future<List<ActiveJob>> fetchActiveJobs() => _api.fetchActiveJobs();

  /// Bir üretimi iptal eder.
  Future<void> cancelJob(String jobId) => _api.cancelJob(jobId);

  /// Görselin ham baytları (paylaşma, wallpaper, galeriye kaydetme için).
  Future<Uint8List> readImageBytes(EbruDesignModel design) =>
      _storage.readImageBytes(design);

  /// Otomatik galeri kaydı başarısız olduysa sebebi; yoksa null.
  ///
  /// Sessiz bırakılmıyor: kullanıcı eserlerinin yedeklendiğini sanıp
  /// aslında yedeklenmemesi, bu ayarın var olma amacını boşa çıkarır.
  String? galleryWarning;

  bool get autoSaveToGallery => _settings.autoSaveToGallery;

  Future<void> setAutoSaveToGallery(bool deger) async {
    await _settings.setAutoSaveToGallery(deger);
    if (deger) {
      // İzni şimdi isteyelim; üretim bittiğinde sormak kötü bir an.
      try {
        if (!await Gal.hasAccess()) await Gal.requestAccess();
      } catch (e) {
        debugPrint('Galeri izni istenemedi: $e');
      }
    } else {
      galleryWarning = null;
    }
    notifyListeners();
  }

  /// Üretilen eseri telefonun galerisine de kopyalar.
  ///
  /// Uygulamanın kendi galerisi uygulamaya özel klasörde duruyor ve
  /// uygulama kaldırılınca siliniyor — imza değişen bir güncelleme de
  /// kaldırma gerektirdiği için eserler böyle kaybolmuştu. Telefon
  /// galerisindeki kopya bundan etkilenmiyor.
  Future<void> _galeriyeKopyala(EbruDesignModel design) async {
    if (!_settings.autoSaveToGallery) return;

    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          galleryWarning =
              'Eserler telefon galerisine kaydedilemiyor: izin verilmedi.';
          return;
        }
      }

      final bytes = await _storage.readImageBytes(design);
      await Gal.putImageBytes(bytes, name: 'ebru_${design.id}');
      galleryWarning = null;
    } catch (e) {
      debugPrint('Galeriye kopyalanamadı: $e');
      galleryWarning = 'Eser telefon galerisine kaydedilemedi.';
    }
  }

  Future<void> toggleFavorite(EbruDesignModel design) async {
    await _storage.toggleFavorite(design);
    notifyListeners();
  }

  void toggleFavoritesFilter() {
    showFavoritesOnly = !showFavoritesOnly;
    notifyListeners();
  }

  /// Bir tasarımı geçmişten ve diskten siler.
  Future<void> deleteDesign(EbruDesignModel design) async {
    await _storage.deleteDesign(design);
    history.removeWhere((d) => d.id == design.id);

    if (currentDesign?.id == design.id) {
      currentDesign = null;
    }
    notifyListeners();
  }

}
