import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Üretim bittiğinde bildirim gösterir.
///
/// Üretim ~90 saniye sürdüğü için kullanıcı bu sürede uygulamadan
/// çıkıyor. Sonucun hazır olduğunu haber vermek gerekiyor.
class NotificationService {
  static const int _uretimBildirimId = 1;

  final FlutterLocalNotificationsPlugin _eklenti =
      FlutterLocalNotificationsPlugin();

  bool _hazir = false;

  Future<void> init() async {
    if (_hazir) return;

    const ayarlar = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    try {
      await _eklenti.initialize(ayarlar);
      _hazir = true;
    } catch (e) {
      // Bildirim kurulamazsa uygulama çalışmaya devam etmeli.
      debugPrint('Bildirim kurulumu başarısız: $e');
    }
  }

  /// Android 13 ve üstünde bildirim izni kullanıcıdan isteniyor.
  Future<void> izinIste() async {
    try {
      await _eklenti
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Bildirim izni istenemedi: $e');
    }
  }

  Future<void> uretimBitti({bool basarili = true}) async {
    if (!_hazir) return;

    const detay = NotificationDetails(
      android: AndroidNotificationDetails(
        'uretim',
        'Üretim bildirimleri',
        channelDescription: 'Ebru tasarımın hazır olduğunda haber verir',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    try {
      await _eklenti.show(
        _uretimBildirimId,
        basarili ? 'Ebrun hazır' : 'Üretim tamamlanamadı',
        basarili
            ? 'Tasarımını görmek için uygulamayı aç'
            : 'Uygulamayı açıp tekrar deneyebilirsin',
        detay,
      );
    } catch (e) {
      debugPrint('Bildirim gösterilemedi: $e');
    }
  }

  Future<void> temizle() async {
    if (!_hazir) return;
    try {
      await _eklenti.cancel(_uretimBildirimId);
    } catch (_) {}
  }
}
