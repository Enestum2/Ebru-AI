import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import '../models/generation_request_model.dart';

/// Sunucunun üretime hazır olup olmadığını anlatan durum bilgisi.
class ServerStatus {
  final bool ready;
  final String message;
  final String? activeSource;
  final int queueLength;

  const ServerStatus({
    required this.ready,
    required this.message,
    this.activeSource,
    this.queueLength = 0,
  });

  factory ServerStatus.unreachable(String message) =>
      ServerStatus(ready: false, message: message);
}

/// Süren üretimin ilerleme bilgisi.
class GenerationProgress {
  final double progress;
  final double? etaSeconds;
  final int queueLength;

  const GenerationProgress({
    required this.progress,
    this.etaSeconds,
    this.queueLength = 0,
  });
}

/// Üretim sonucu.
class GenerationResult {
  final String imageBase64;
  final int seed;
  final int width;
  final int height;
  final String promptEn;

  const GenerationResult({
    required this.imageBase64,
    required this.seed,
    required this.width,
    required this.height,
    required this.promptEn,
  });
}

/// Sunucudaki tek bir istek kaydı.
class UsageRecord {
  final DateTime time;
  final String deviceId;
  final String ip;
  final String prompt;
  final bool success;
  final double duration;
  final String? message;

  const UsageRecord({
    required this.time,
    required this.deviceId,
    required this.ip,
    required this.prompt,
    required this.success,
    required this.duration,
    this.message,
  });

  factory UsageRecord.fromMap(Map veri) {
    // Sunucu zamanı unix saniye olarak gönderiyor.
    final saniye = (veri['zaman'] as num?)?.toDouble() ?? 0;

    return UsageRecord(
      time: DateTime.fromMillisecondsSinceEpoch((saniye * 1000).round()),
      deviceId: veri['kimlik'] as String? ?? '-',
      ip: veri['ip'] as String? ?? '-',
      prompt: veri['prompt'] as String? ?? '',
      success: veri['durum'] == 'success',
      duration: (veri['sure'] as num?)?.toDouble() ?? 0,
      message: veri['mesaj'] as String?,
    );
  }
}

/// Bekleyen ya da süren bir üretim.
class ActiveJob {
  final String id;
  final String status;
  final String owner;
  final double elapsed;
  final bool cancelled;

  const ActiveJob({
    required this.id,
    required this.status,
    required this.owner,
    required this.elapsed,
    required this.cancelled,
  });

  bool get isRunning => status == 'running';

  factory ActiveJob.fromMap(Map veri) {
    return ActiveJob(
      id: veri['job_id'] as String? ?? '',
      status: veri['durum'] as String? ?? '',
      owner: veri['kimlik'] as String? ?? '-',
      elapsed: (veri['gecen'] as num?)?.toDouble() ?? 0,
      cancelled: veri['iptal'] == true,
    );
  }
}

/// Sunucunun kullanım özeti.
class UsageStats {
  final int total;
  final int success;
  final int failed;
  final int queue;
  final int activeJobs;
  final int dailyLimit;
  final List<({String id, int count})> devices;
  final List<UsageRecord> records;

  const UsageStats({
    required this.total,
    required this.success,
    required this.failed,
    required this.queue,
    required this.activeJobs,
    required this.dailyLimit,
    required this.devices,
    required this.records,
  });

  factory UsageStats.fromMap(Map veri) {
    final sayaclar = (veri['sayaclar'] as Map?) ?? {};
    final cihazlar = (veri['cihazlar'] as List?) ?? [];
    final istekler = (veri['istekler'] as List?) ?? [];

    return UsageStats(
      total: sayaclar['toplam'] as int? ?? 0,
      success: sayaclar['basarili'] as int? ?? 0,
      failed: sayaclar['hatali'] as int? ?? 0,
      queue: veri['kuyruk'] as int? ?? 0,
      activeJobs: veri['aktif_isler'] as int? ?? 0,
      dailyLimit: veri['gunluk_limit'] as int? ?? 0,
      devices: cihazlar
          .map((c) => (
                id: (c as Map)['kimlik'] as String? ?? '-',
                count: c['bugun'] as int? ?? 0,
              ))
          .toList(),
      records: istekler
          .map((r) => UsageRecord.fromMap(r as Map))
          .toList(),
    );
  }
}

/// Kullanıcıya gösterilebilecek, sebebi belli hata.
class ApiException implements Exception {
  final String message;

  /// Bağlantı koptuğu için oluştuysa true; iş sunucuda sürüyor olabilir.
  ///
  /// Telefonun ekranı kapandığında işletim sistemi uygulamayı dondurup
  /// açık soketleri kapatıyor. Bu, üretimin başarısız olduğu anlamına
  /// gelmiyor — sunucu işi bitiriyor. Bu ayrım olmadan uygulama yarım
  /// kalan işin kaydını siliyor, kullanıcı tekrar denediğinde de aynı
  /// üretim ikinci kez kuyruğa giriyordu.
  final bool gecici;

  const ApiException(this.message, {this.gecici = false});

  @override
  String toString() => message;
}

/// Flask backend ile iletişimi yöneten servis.
/// Giriş/kayıt sonucu.
class AuthResult {
  final String token;
  final String username;

  /// Sunucu bu hesabın izleme ekranına erişebileceğini bildiriyor.
  final bool isAdmin;

  /// E-posta onaylanmadan üretim yapılamıyor. Uygulama bu bilgiyle
  /// kullanıcıyı doğrudan üretim ekranına değil, onay ekranına
  /// götürüyor; yoksa seçimleri yapıp sonunda reddedilirdi.
  final bool emailVerified;

  const AuthResult({
    required this.token,
    required this.username,
    this.isAdmin = false,
    this.emailVerified = true,
  });
}

/// Google ile girişin sonucu.
///
/// İki durumdan biri: ya oturum açıldı, ya da kişi ilk kez geliyor ve
/// kullanıcı adı seçmesi gerekiyor. Sunucu bu iki durumu ayrı
/// bildirdiği için burada da ayrı temsil ediliyor; tek bir nullable
/// alanla anlatmaya çalışmak çağıran tarafta karışıklık yaratıyordu.
class GoogleGirisSonucu {
  /// Oturum açıldıysa dolu.
  final AuthResult? oturum;

  /// Kullanıcı adı gerekiyorsa dolu (sunucunun önerdiği ad).
  final String? onerilenKullaniciAdi;
  final String? eposta;

  const GoogleGirisSonucu.girildi(AuthResult this.oturum)
      : onerilenKullaniciAdi = null,
        eposta = null;

  const GoogleGirisSonucu.kullaniciAdiGerekli({
    this.onerilenKullaniciAdi,
    this.eposta,
  }) : oturum = null;

  bool get kullaniciAdiGerekiyor => oturum == null;
}

class ApiService {
  final Dio _dio;
  String baseUrl;
  final String deviceId;

  /// Oturum anahtarı. Boşsa korumalı uçlara erişilemez.
  String sessionToken;

  ApiService({
    required this.baseUrl,
    required this.deviceId,
    this.sessionToken = '',
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            // Üretim uzun sürebilir; sırada bekleme de buna dahil.
            receiveTimeout: const Duration(minutes: 5),
            sendTimeout: const Duration(seconds: 30),
            // Hata kodlarını Dio fırlatmasın, kendimiz yorumlayalım.
            validateStatus: (_) => true,
          ),
        );

  Map<String, String> get _headers => {
        'X-Device-Id': deviceId,
        // ngrok ücretsiz katmanı tarayıcı isteklerine uyarı sayfası
        // döndürüyor; bu başlık onu atlatıp doğrudan JSON almamızı sağlar.
        'ngrok-skip-browser-warning': 'true',
        if (sessionToken.isNotEmpty)
          'Authorization': 'Bearer $sessionToken',
      };

  // ---------------------------------------------------------------
  // Hesap
  // ---------------------------------------------------------------

  /// Yeni hesap açar.
  ///
  /// Ad, soyad ve e-posta artık zorunlu: sunucu bunlar olmadan kaydı
  /// reddediyor ve hesap e-posta onaylanana kadar üretim yapamıyor.
  Future<AuthResult> register(
    String username,
    String password, {
    required String ad,
    required String soyad,
    required String eposta,
  }) =>
      _authIstegi('/auth/register', username, password, ekler: {
        'first_name': ad,
        'last_name': soyad,
        'email': eposta,
      });

  Future<AuthResult> login(String username, String password) =>
      _authIstegi('/auth/login', username, password);

  Future<AuthResult> _authIstegi(
    String yol,
    String username,
    String password, {
    Map<String, dynamic> ekler = const {},
  }) async {
    late final Response cevap;

    try {
      cevap = await _dio.post(
        '$baseUrl$yol',
        data: {'username': username, 'password': password, ...ekler},
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    final veri = cevap.data;
    if (cevap.statusCode == 200 || cevap.statusCode == 201) {
      if (veri is Map && veri['token'] != null) {
        return _authSonucu(veri, username);
      }
      throw const ApiException('Sunucu beklenmedik yanıt verdi');
    }

    // Sunucu neyin yanlış olduğunu zaten anlaşılır biçimde yazıyor.
    throw ApiException(
      (veri is Map ? veri['message'] as String? : null) ??
          'İşlem başarısız (kod: ${cevap.statusCode})',
    );
  }

  /// Sunucunun giriş/kayıt cevabını ortak biçimde okur.
  AuthResult _authSonucu(Map veri, String yedekKullaniciAdi) => AuthResult(
        token: veri['token'] as String,
        username: veri['username'] as String? ?? yedekKullaniciAdi,
        isAdmin: veri['is_admin'] == true,
        // Alan yoksa "onaylı" kabul ediliyor: eski sunucu sürümüne
        // bağlanıldığında kullanıcı gereksiz yere onay ekranında
        // kilitlenmesin.
        emailVerified: veri['email_verified'] != false,
      );

  /// Kayıtlı oturumun hâlâ geçerli olup olmadığını sorar.
  ///
  /// Ağ hatasında oturum geçerli sayılıyor — kullanıcı çevrimdışıyken
  /// uygulamadan atılmamalı. Aynı sebeple e-posta da onaylı kabul
  /// ediliyor; sunucuya sorulamadığı için onay ekranında kilitlemek
  /// yanlış olur.
  Future<
      ({
        bool valid,
        bool isAdmin,
        bool emailVerified,
        String? email,
        bool hasPassword
      })> sessionValid() async {
    if (sessionToken.isEmpty) {
      return (
        valid: false,
        isAdmin: false,
        emailVerified: true,
        email: null,
        hasPassword: true,
      );
    }

    try {
      final cevap = await _dio.get(
        '$baseUrl/auth/me',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (cevap.statusCode != 200) {
        return (
          valid: false,
          isAdmin: false,
          emailVerified: true,
          email: null,
          hasPassword: true,
        );
      }

      final veri = cevap.data;
      final m = veri is Map ? veri : const {};
      return (
        valid: true,
        isAdmin: m['is_admin'] == true,
        emailVerified: m['email_verified'] != false,
        email: m['email'] as String?,
        // Alan yoksa "sifresi var" kabul ediliyor: eski sunucu surumune
        // baglanildiginda silme ekrani sifre sorsun, kullanici adi degil.
        hasPassword: m['has_password'] != false,
      );
    } catch (_) {
      return (
        valid: true,
        isAdmin: false,
        emailVerified: true,
        email: null,
        hasPassword: true,
      );
    }
  }

  /// Doğrulama bağlantısını yeniden gönderir.
  Future<String> dogrulamaGonder() async {
    late final Response cevap;
    try {
      cevap = await _dio.post(
        '$baseUrl/auth/dogrulama-gonder',
        options: Options(headers: _headers),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    final veri = cevap.data;
    final mesaj = veri is Map ? veri['message'] as String? : null;
    if (cevap.statusCode == 200) {
      return mesaj ?? 'Doğrulama bağlantısı gönderildi.';
    }
    throw ApiException(mesaj ?? 'Bağlantı gönderilemedi.');
  }

  // ---------------------------------------------------------------
  // Google ile giriş
  // ---------------------------------------------------------------
  // Google'dan alınan kimlik belirteci sunucuya gönderiliyor; doğrulama
  // orada yapılıyor. Sunucu ya oturum açıyor ya da "bu kişi yeni,
  // kullanıcı adı seçsin" diyor.
  //
  // Belirteç ikinci istekte tekrar gönderiliyor ve yeniden
  // doğrulanıyor. Böylece sunucuda "bekleyen kayıt" diye bir durum
  // tutmak gerekmiyor.

  /// Google girişi açık mı ve hangi istemci kimliği kullanılacak.
  ///
  /// Kimlik uygulamaya gömülmüyor; sunucudan okunuyor. Böylece
  /// değişmesi gerektiğinde yeni APK çıkarmak gerekmiyor.
  Future<({bool enabled, String clientId})> googleDurum() async {
    try {
      final cevap = await _dio.get(
        '$baseUrl/auth/google/durum',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final veri = cevap.data;
      if (cevap.statusCode == 200 && veri is Map) {
        return (
          enabled: veri['enabled'] == true,
          clientId: (veri['client_id'] as String?) ?? '',
        );
      }
    } catch (_) {
      // Ulaşılamıyorsa Google düğmesi gösterilmiyor; giriş formu
      // zaten çalışıyor.
    }
    return (enabled: false, clientId: '');
  }

  Future<GoogleGirisSonucu> googleGiris(String idToken) async {
    final cevap = await _googleIstegi('/auth/google', {
      'credential': idToken,
    });

    final veri = cevap.data;
    final m = veri is Map ? veri : const {};

    if (m['status'] == 'username_required') {
      return GoogleGirisSonucu.kullaniciAdiGerekli(
        onerilenKullaniciAdi: m['suggested'] as String?,
        eposta: m['email'] as String?,
      );
    }

    if (m['token'] != null) {
      return GoogleGirisSonucu.girildi(_authSonucu(m, ''));
    }

    throw ApiException(
      (m['message'] as String?) ?? 'Google girişi tamamlanamadı.',
    );
  }

  Future<AuthResult> googleKullaniciAdi(
    String idToken,
    String kullaniciAdi,
  ) async {
    final cevap = await _googleIstegi('/auth/google/kullanici-adi', {
      'credential': idToken,
      'username': kullaniciAdi,
    });

    final veri = cevap.data;
    final m = veri is Map ? veri : const {};
    if (m['token'] != null) return _authSonucu(m, kullaniciAdi);

    throw ApiException(
      (m['message'] as String?) ?? 'Hesap oluşturulamadı.',
    );
  }

  Future<Response> _googleIstegi(String yol, Map<String, dynamic> govde) async {
    late final Response cevap;
    try {
      cevap = await _dio.post(
        '$baseUrl$yol',
        data: govde,
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 25),
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    if (cevap.statusCode == 200 || cevap.statusCode == 201) return cevap;

    final veri = cevap.data;
    throw ApiException(
      (veri is Map ? veri['message'] as String? : null) ??
          'Google girişi başarısız (kod: ${cevap.statusCode})',
    );
  }

  Future<void> logout() async {
    if (sessionToken.isEmpty) return;
    try {
      await _dio.post(
        '$baseUrl/auth/logout',
        options: Options(headers: _headers),
      );
    } catch (_) {
      // Sunucuya ulaşılamasa da yerel oturum temizlenecek.
    }
  }

  /// Hesabı ve sunucudaki bütün verilerini kalıcı olarak siler.
  ///
  /// Son onay hesabın açılış yoluna göre değişiyor: şifreyle açılmış
  /// hesap [sifre], Google ile açılmış hesap kullanıcı adını [onay]
  /// alanında gönderiyor. Google hesaplarının kullanılabilir bir
  /// şifresi olmadığı için tek bir alan ikisine birden yetmiyor.
  ///
  /// Çıkıştan farklı olarak hata yutulmuyor: silinmediği hâlde
  /// "silindi" demek, kullanıcının hesabının durduğunu bilmemesi
  /// demek olurdu.
  Future<void> hesabimiSil({String? sifre, String? onay}) async {
    late final Response cevap;

    try {
      cevap = await _dio.post(
        '$baseUrl/auth/hesabimi-sil',
        data: {
          'sifre': ?sifre,
          'onay': ?onay,
        },
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    if (cevap.statusCode == 200) return;

    final veri = cevap.data;
    throw ApiException(
      (veri is Map ? veri['message'] as String? : null) ??
          'Hesap silinemedi (kod: ${cevap.statusCode})',
    );
  }

  /// Sunucunun ve GPU'nun durumunu sorar.
  Future<ServerStatus> checkHealth() async {
    try {
      final cevap = await _dio.get(
        '$baseUrl/health',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (cevap.statusCode != 200 || cevap.data is! Map) {
        return ServerStatus.unreachable('Sunucu beklenmedik yanıt verdi');
      }

      final veri = cevap.data as Map;
      return ServerStatus(
        ready: veri['ready'] == true,
        message: veri['message'] as String? ?? '',
        activeSource: veri['active_source'] as String?,
        queueLength: veri['queue_length'] as int? ?? 0,
      );
    } on DioException catch (e) {
      return ServerStatus.unreachable(_dioMesaji(e));
    } catch (_) {
      return ServerStatus.unreachable('Sunucuya ulaşılamadı');
    }
  }

  /// Sunucudaki kullanım istatistiklerini çeker.
  /// Yalnızca yönetici anahtarıyla erişilebilir.
  Future<UsageStats> fetchStats() async {
    late final Response cevap;

    try {
      cevap = await _dio.get(
        '$baseUrl/stats',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    if (cevap.statusCode == 403) {
      throw const ApiException('Yönetici anahtarı geçersiz');
    }
    if (cevap.statusCode != 200 || cevap.data is! Map) {
      throw ApiException(_durumMesaji(cevap.statusCode, null));
    }

    return UsageStats.fromMap(cevap.data as Map);
  }

  /// Yönetici: bekleyen ve süren işleri listeler.
  Future<List<ActiveJob>> fetchActiveJobs() async {
    try {
      final cevap = await _dio.get(
        '$baseUrl/admin/jobs',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (cevap.statusCode != 200 || cevap.data is! Map) return [];

      final liste = (cevap.data as Map)['isler'] as List? ?? [];
      return liste.map((j) => ActiveJob.fromMap(j as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Yönetici: bir üretimi iptal eder.
  Future<void> cancelJob(String jobId) async {
    late final Response cevap;

    try {
      cevap = await _dio.post(
        '$baseUrl/admin/jobs/$jobId/cancel',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    if (cevap.statusCode != 200) {
      final mesaj = cevap.data is Map
          ? (cevap.data as Map)['message'] as String?
          : null;
      throw ApiException(mesaj ?? 'İptal edilemedi');
    }
  }

  /// Süren üretimin ilerlemesini sorar.
  /// Hata durumunda null döner — ilerleme bilgisi kritik değil.
  Future<GenerationProgress?> fetchProgress() async {
    try {
      final cevap = await _dio.get(
        '$baseUrl/progress',
        options: Options(
          headers: _headers,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      if (cevap.statusCode != 200 || cevap.data is! Map) return null;

      final veri = cevap.data as Map;
      return GenerationProgress(
        progress: (veri['progress'] as num?)?.toDouble() ?? 0.0,
        etaSeconds: (veri['eta_seconds'] as num?)?.toDouble(),
        queueLength: veri['queue_length'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Ebru tasarımı üretir.
  ///
  /// Üretim 90 saniyeyi aşabildiği ve tüneller ~100 saniyede bağlantıyı
  /// kestiği için tek uzun istek yerine asenkron akış kullanılır:
  /// önce iş oluşturulur, sonra sonuç sorgulanır. [onProgress] her
  /// sorgulamada güncel ilerlemeyi bildirir.
  Future<GenerationResult> generateDesign(
    GenerationRequestModel request, {
    void Function(GenerationProgress)? onProgress,
    void Function(String jobId)? onJobCreated,
    Duration pollInterval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final jobId = await _createJob(request);
    onJobCreated?.call(jobId);

    return waitForJob(
      jobId,
      onProgress: onProgress,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  /// Var olan bir işin sonucunu bekler.
  ///
  /// Uygulama kapatılıp açıldığında yarım kalan işi bu yolla
  /// tamamlıyoruz — sunucu üretimi zaten bitirmiş oluyor.
  Future<GenerationResult> waitForJob(
    String jobId, {
    void Function(GenerationProgress)? onProgress,
    Duration pollInterval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final bitis = DateTime.now().add(timeout);
    var ustUsteHata = 0;

    while (DateTime.now().isBefore(bitis)) {
      await Future<void>.delayed(pollInterval);

      try {
        final sonuc = await _pollJob(jobId, onProgress);
        if (sonuc != null) return sonuc;
        ustUsteHata = 0;
      } on ApiException catch (e) {
        // Sunucudan gelen gerçek hatalar (iş bulunamadı, üretim
        // başarısız, oturum düştü) beklemeyi bitirir.
        if (!e.gecici) rethrow;

        ustUsteHata++;
        if (ustUsteHata >= _geciciHataSiniri) {
          throw const ApiException(
            'Bağlantı koptu. Üretim sunucuda sürüyor; uygulamaya geri '
            'döndüğünde kaldığı yerden devam eder.',
            gecici: true,
          );
        }
      }
    }

    throw const ApiException(
      'Üretim çok uzun sürdü. Lütfen tekrar deneyin.',
    );
  }

  /// Ağ koptuğunda kaç sorgulama üst üste başarısız olursa vazgeçilir.
  /// 3 saniyelik aralıkla yaklaşık 30 saniyelik kesintiyi tolere eder.
  static const int _geciciHataSiniri = 10;

  /// Üretim işini kuyruğa alır, iş numarasını döner.
  Future<String> _createJob(GenerationRequestModel request) async {
    late final Response cevap;

    try {
      cevap = await _dio.post(
        '$baseUrl/jobs',
        data: request.toJson(),
        options: Options(
          headers: _headers,
          // İş oluşturma anında yanıtlanır, uzun beklemeye gerek yok.
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
    } on DioException catch (e) {
      throw ApiException(_dioMesaji(e));
    }

    final veri = cevap.data;
    final sunucuMesaji = veri is Map ? veri['message'] as String? : null;

    if (cevap.statusCode != 202 || veri is! Map) {
      throw ApiException(_durumMesaji(cevap.statusCode, sunucuMesaji));
    }

    final jobId = veri['job_id'] as String?;
    if (jobId == null) {
      throw const ApiException('Sunucu iş numarası döndürmedi');
    }
    return jobId;
  }

  /// İşi sorgular. Bittiyse sonucu, sürüyorsa null döner.
  Future<GenerationResult?> _pollJob(
    String jobId,
    void Function(GenerationProgress)? onProgress,
  ) async {
    late final Response cevap;

    try {
      cevap = await _dio.get(
        '$baseUrl/jobs/$jobId',
        options: Options(
          headers: _headers,
          // İş bittiğinde bu yanıt görseli de taşıyor (~1,5 MB).
          // Yavaş mobil bağlantıda 20 saniye yetmiyordu.
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
    } on DioException catch (e) {
      // Ağ kaynaklı hatalar üretimi iptal etmemeli; iş sunucuda
      // sürüyor. Eskiden yalnızca zaman aşımları tolere ediliyordu,
      // oysa ekran kapandığında soket düştüğü için connectionError
      // geliyor ve döngü orada kırılıyordu.
      if (_agHatasi(e)) {
        throw ApiException(_dioMesaji(e), gecici: true);
      }
      throw ApiException(_dioMesaji(e));
    }

    final veri = cevap.data;
    if (veri is! Map) {
      throw const ApiException('Sunucudan beklenmedik yanıt geldi');
    }

    final jobStatus = veri['job_status'] as String?;
    final sunucuMesaji = veri['message'] as String?;

    // İş kaydı süresi dolup silinmişse tekrar beklemenin anlamı yok.
    if (cevap.statusCode == 404) {
      throw const ApiException(
        'Bu üretimin kaydı sunucuda kalmamış. Lütfen tekrar deneyin.',
      );
    }

    if (cevap.statusCode != 200 || jobStatus == 'error') {
      throw ApiException(_durumMesaji(cevap.statusCode, sunucuMesaji));
    }

    if (jobStatus == 'done') {
      final tamGorsel = veri['image'] as String;
      return GenerationResult(
        imageBase64: tamGorsel.split(',').last,
        seed: veri['seed'] as int? ?? -1,
        width: veri['width'] as int? ?? 0,
        height: veri['height'] as int? ?? 0,
        promptEn: veri['prompt'] as String? ?? '',
      );
    }

    // Hâlâ sırada veya üretiliyor.
    onProgress?.call(
      GenerationProgress(
        progress: (veri['progress'] as num?)?.toDouble() ?? 0.0,
        etaSeconds: (veri['eta_seconds'] as num?)?.toDouble(),
        queueLength: veri['queue_length'] as int? ?? 0,
      ),
    );
    return null;
  }

  /// HTTP durum kodlarını kullanıcının anlayacağı mesaja çevirir.
  String _durumMesaji(int? kod, String? sunucuMesaji) {
    switch (kod) {
      case 401:
        return sunucuMesaji ?? 'Oturumun sona ermiş, tekrar giriş yap';
      case 429:
        // Günlük hak / çok sık istek / kuyruk dolu — sunucu zaten
        // anlaşılır bir mesaj gönderiyor.
        return sunucuMesaji ?? 'Çok fazla istek gönderildi';
      case 503:
        return sunucuMesaji ??
            'Görsel üretim sunucusu şu anda kapalı';
      case 502:
        return 'Üretim sırasında bir sorun oluştu, tekrar dene';
      case 400:
        return sunucuMesaji ?? 'İstek geçersiz';
      default:
        return sunucuMesaji ?? 'Üretim başarısız (kod: $kod)';
    }
  }

  /// Sunucunun verdiği bir yanıt değil, bağlantının kendisi mi bozuldu?
  ///
  /// Ekran kapanınca işletim sistemi soketleri kapattığı için burada
  /// çoğunlukla connectionError görülüyor; uçakmodu ve şebeke değişimi
  /// de aynı gruba giriyor.
  static bool _agHatasi(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.unknown:
        // Soket kapandığında Dio bunu tiplendiremeyip unknown veriyor.
        return e.error is SocketException;
      default:
        return false;
    }
  }

  String _dioMesaji(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return 'Sunucuya bağlanılamadı. Adresi ayarlardan kontrol et.';
      case DioExceptionType.receiveTimeout:
        return 'Sunucu zamanında yanıt vermedi. Yoğunluk olabilir.';
      case DioExceptionType.sendTimeout:
        return 'İstek gönderilemedi, bağlantını kontrol et.';
      default:
        return 'Bağlantı hatası: ${e.message ?? 'bilinmeyen'}';
    }
  }
}
