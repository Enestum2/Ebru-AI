import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Sunucu adresi gibi kalıcı ayarları yönetir.
///
/// Sunucu adresi eskiden kodda sabitti; IP değişince uygulamayı yeniden
/// derlemek gerekiyordu. Artık kullanıcı ayarlar ekranından değiştirebilir.
/// Kullanılan sunucu adresinin nereden geldiği.
enum ServerUrlSource {
  /// Kullanıcı ayarlar ekranından kendi yazdı.
  manuel,

  /// Uygulama açılışta uzaktaki adres dosyasından öğrendi.
  bulunan,

  /// Hiçbiri yok; uygulamaya gömülü adres kullanılıyor.
  varsayilan,
}

class SettingsService {
  static const String _serverUrlKey = 'server_url';
  static const String _deviceIdKey = 'device_id';
  static const String _adminTokenKey = 'admin_token';
  static const String _discoveredUrlKey = 'discovered_server_url';
  static const String _directoryMessageKey = 'directory_message';
  static const String _autoGalleryKey = 'auto_save_gallery';

  /// Uygulamaya gömülü adres. Yalnızca son çare: adres dosyasına hiç
  /// ulaşılamamışsa ve kullanıcı da bir şey yazmamışsa kullanılıyor.
  ///
  /// Normal durumda adres [ServerDirectory] ile uzaktan öğreniliyor,
  /// bu yüzden buradaki değerin güncel kalması kritik değil.
  static const String defaultServerUrl = 'https://ebruai.com';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Cihaz kimliği bir kez üretilir; sunucu günlük üretim hakkını
    // bununla takip ediyor.
    if (_prefs.getString(_deviceIdKey) == null) {
      await _prefs.setString(_deviceIdKey, _generateDeviceId());
    }
  }

  /// Kullanıcının elle yazdığı adres. Yazmadıysa null.
  String? get manualServerUrl => _prefs.getString(_serverUrlKey);

  /// Uzaktaki adres dosyasından öğrenilen adres. Öğrenilmediyse null.
  String? get discoveredServerUrl => _prefs.getString(_discoveredUrlKey);

  /// Sunucuya ulaşılamadığında gösterilecek açıklama; adres dosyasından
  /// geliyor, boş olabilir.
  String get directoryMessage => _prefs.getString(_directoryMessageKey) ?? '';

  /// Sıra: kullanıcının yazdığı > uzaktan öğrenilen > gömülü.
  ///
  /// Elle yazılan adres en üstte, çünkü bir şey ters gittiğinde
  /// kullanıcının kendi kurduğu sunucuya yönelebilmesi gerekiyor;
  /// uzaktan gelen değer onu ezmemeli.
  String get serverUrl =>
      manualServerUrl ?? discoveredServerUrl ?? defaultServerUrl;

  ServerUrlSource get serverUrlSource {
    if (manualServerUrl != null) return ServerUrlSource.manuel;
    if (discoveredServerUrl != null) return ServerUrlSource.bulunan;
    return ServerUrlSource.varsayilan;
  }

  /// Üretilen eser telefonun galerisine de kopyalanıyor mu?
  ///
  /// Varsayılan açık. Uygulamanın kendi galerisi uygulamaya özel
  /// klasörde duruyor ve uygulama kaldırıldığında siliniyor; telefon
  /// galerisine kopyalanan eserler bundan etkilenmiyor.
  bool get autoSaveToGallery => _prefs.getBool(_autoGalleryKey) ?? true;

  Future<void> setAutoSaveToGallery(bool deger) async {
    await _prefs.setBool(_autoGalleryKey, deger);
  }

  String get deviceId => _prefs.getString(_deviceIdKey) ?? 'bilinmiyor';

  Future<void> setServerUrl(String url) async {
    await _prefs.setString(_serverUrlKey, normalizeUrl(url));
  }

  /// Adres dosyasından öğrenilen değeri saklar. Çevrimdışı açılışta
  /// son bilinen adresle devam edilebilsin diye kalıcı yazılıyor.
  Future<void> saveDiscoveredServerUrl(String url, String message) async {
    await _prefs.setString(_discoveredUrlKey, normalizeUrl(url));
    await _prefs.setString(_directoryMessageKey, message);
  }

  /// Sunucunun izleme uçlarına erişim anahtarı.
  /// Yalnızca uygulamayı yöneten kişide olur; boşsa izleme ekranı gizli.
  String get adminToken => _prefs.getString(_adminTokenKey) ?? '';

  Future<void> setAdminToken(String token) async {
    await _prefs.setString(_adminTokenKey, token.trim());
  }

  // --- Hesap oturumu ---

  static const String _sessionTokenKey = 'session_token';
  static const String _usernameKey = 'username';

  static const String _isAdminKey = 'is_admin';

  String get sessionToken => _prefs.getString(_sessionTokenKey) ?? '';
  String get username => _prefs.getString(_usernameKey) ?? '';

  /// Bu hesap izleme ekranına erişebiliyor mu. Sunucu belirliyor.
  bool get isAdmin => _prefs.getBool(_isAdminKey) ?? false;

  Future<void> saveSession(
    String token,
    String username, {
    bool isAdmin = false,
  }) async {
    await _prefs.setString(_sessionTokenKey, token);
    await _prefs.setString(_usernameKey, username);
    await _prefs.setBool(_isAdminKey, isAdmin);
  }

  Future<void> setIsAdmin(bool deger) async {
    await _prefs.setBool(_isAdminKey, deger);
  }

  Future<void> clearSession() async {
    await _prefs.remove(_sessionTokenKey);
    await _prefs.remove(_usernameKey);
    await _prefs.remove(_isAdminKey);
  }

  // --- Yarım kalan üretim ---
  //
  // Üretim ~90 saniye sürüyor ve kullanıcı bu sırada uygulamadan
  // çıkabiliyor. Sunucu işi tamamlıyor ama uygulama sonucu alamıyordu.
  // İş numarası burada saklanıyor, uygulama açılınca kaldığı yerden
  // devam ediyor.

  static const String _pendingJobKey = 'pending_job';
  static const String _pendingJobMetaKey = 'pending_job_meta';

  String get pendingJobId => _prefs.getString(_pendingJobKey) ?? '';

  /// İşin üretim ayarları: sonuç geldiğinde kaydedebilmek için.
  /// Biçim: "palet|desen|prompt"
  String get pendingJobMeta => _prefs.getString(_pendingJobMetaKey) ?? '';

  Future<void> savePendingJob(String jobId, String meta) async {
    await _prefs.setString(_pendingJobKey, jobId);
    await _prefs.setString(_pendingJobMetaKey, meta);
  }

  Future<void> clearPendingJob() async {
    await _prefs.remove(_pendingJobKey);
    await _prefs.remove(_pendingJobMetaKey);
  }

  Future<void> resetServerUrl() async {
    await _prefs.remove(_serverUrlKey);
  }

  /// Kullanıcının yazdığı adresi kullanılabilir hale getirir:
  /// baştaki/sondaki boşlukları ve sondaki eğik çizgiyi temizler,
  /// şema yoksa http:// ekler.
  static String normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Adresin biçimsel olarak geçerli olup olmadığını söyler.
  static bool isValidUrl(String raw) {
    final url = normalizeUrl(raw);
    if (url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    return uri != null && uri.host.isNotEmpty;
  }

  static String _generateDeviceId() {
    final rastgele = Random.secure();
    final parcalar = List<int>.generate(8, (_) => rastgele.nextInt(256));
    return parcalar
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
