import 'dart:convert';

import 'package:dio/dio.dart';

/// Sunucunun güncel adresini uzaktan öğrenir.
///
/// Kiralanan GPU bir bulut sağlayıcıda çalışıyor ve adresi makine
/// yeniden yaratıldığında değişiyor. Adres yalnızca uygulamaya gömülü
/// olsaydı, her değişiklikte yeni bir APK derleyip herkese yeniden
/// dağıtmak gerekirdi — telefonundaki eski kurulum çalışmaz hale
/// gelirdi.
///
/// Bunun yerine uygulama açılışta küçük bir JSON dosyası okuyor.
/// Adres değiştiğinde yalnızca o dosya güncelleniyor, uygulamaya
/// dokunulmuyor.
///
/// Beklenen içerik:
/// ```json
/// {
///   "sunucu": "https://ornek-adres",
///   "mesaj": "GPU şu anda kapalı, akşam açılacak."
/// }
/// ```
/// `mesaj` isteğe bağlı; sunucuya ulaşılamadığında kullanıcıya
/// gösterilecek açıklama için.
class ServerDirectory {
  /// Adresin yazılı olduğu dosya. GitHub'ın ham içerik adresi sabit,
  /// ücretsiz ve uygulamadan bağımsız olarak güncellenebiliyor.
  static const String directoryUrl =
      'https://raw.githubusercontent.com/Enestum2/Ebru-AI/main/sunucu.json';

  final Dio _dio;

  ServerDirectory({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                // Açılışı geciktirmemesi için kısa tutuldu; başarısız
                // olursa uygulama bilinen son adresle devam ediyor.
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                validateStatus: (_) => true,
                // GitHub bazen önbellekten eski içerik döndürüyor.
                headers: {'Cache-Control': 'no-cache'},
                responseType: ResponseType.plain,
              ),
            );

  /// Dosyayı okur. Ulaşılamazsa ya da içerik bozuksa null döner —
  /// bu bir hata değil, çevrimdışı açılışta beklenen durum.
  Future<DirectoryResult?> fetch() async {
    try {
      final cevap = await _dio.get(directoryUrl);
      if (cevap.statusCode != 200 || cevap.data == null) return null;

      return parseBody(cevap.data.toString());
    } catch (_) {
      // Ağ yok, DNS yok, bozuk JSON — hepsinde sessizce vazgeçiyoruz.
      return null;
    }
  }

  /// Dosya içeriğini çözer. Ağdan ayrı tutuldu ki test edilebilsin.
  static DirectoryResult? parseBody(String body) {
    try {
      final veri = jsonDecode(body);
      if (veri is! Map) return null;

      final adres = _temizle(veri['sunucu']);
      if (adres == null) return null;

      final mesaj = veri['mesaj'];
      return DirectoryResult(
        url: adres,
        message: mesaj is String ? mesaj.trim() : '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Yalnızca https adresleri kabul ediliyor. Dosya herkese açık
  /// olduğu için, buradan gelen bir değerin bağlantıyı şifresiz
  /// http'ye düşürebilmesi istenmiyor.
  static String? _temizle(dynamic ham) {
    if (ham is! String) return null;

    var url = ham.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    if (!url.startsWith('https://')) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;

    return url;
  }
}

class DirectoryResult {
  final String url;

  /// Sunucuya ulaşılamadığında gösterilecek açıklama. Boş olabilir.
  final String message;

  const DirectoryResult({required this.url, this.message = ''});
}
