import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ebru_ai_wallpaper/services/server_directory.dart';
import 'package:ebru_ai_wallpaper/services/settings_service.dart';

/// Kiralanan GPU'nun adresi değişebildiği için uygulama adresi uzaktaki
/// bir dosyadan öğreniyor. Bu testler iki şeyi güvenceye alıyor:
/// bozuk/kötü niyetli içeriğin kabul edilmemesi ve kullanıcının kendi
/// yazdığı adresin uzaktan gelen değerle ezilmemesi.
void main() {
  group('Adres dosyasının çözümlenmesi', () {
    test('geçerli içerikten adresi ve mesajı okur', () {
      final sonuc = ServerDirectory.parseBody(
        '{"sunucu": "https://ornek.proxy.runpod.net", "mesaj": "kapali"}',
      );

      expect(sonuc, isNotNull);
      expect(sonuc!.url, 'https://ornek.proxy.runpod.net');
      expect(sonuc.message, 'kapali');
    });

    test('sondaki eğik çizgiyi temizler', () {
      final sonuc = ServerDirectory.parseBody('{"sunucu": "https://a.b///"}');
      expect(sonuc!.url, 'https://a.b');
    });

    test('mesaj yoksa boş döner', () {
      final sonuc = ServerDirectory.parseBody('{"sunucu": "https://a.b"}');
      expect(sonuc!.message, '');
    });

    test('http adresi kabul edilmez', () {
      // Dosya herkese açık; buradan gelen bir değer bağlantıyı
      // şifresiz http'ye düşürememeli.
      expect(ServerDirectory.parseBody('{"sunucu": "http://a.b"}'), isNull);
    });

    test('bozuk JSON, eksik alan ve yanlış tip null döner', () {
      expect(ServerDirectory.parseBody('bu json degil'), isNull);
      expect(ServerDirectory.parseBody('{}'), isNull);
      expect(ServerDirectory.parseBody('{"sunucu": 42}'), isNull);
      expect(ServerDirectory.parseBody('[]'), isNull);
      expect(ServerDirectory.parseBody('{"sunucu": "https://"}'), isNull);
    });
  });

  group('Adres önceliği', () {
    late SettingsService ayarlar;

    Future<void> kur(Map<String, Object> baslangic) async {
      SharedPreferences.setMockInitialValues(baslangic);
      ayarlar = SettingsService();
      await ayarlar.init();
    }

    test('hiçbiri yoksa gömülü adres kullanılır', () async {
      await kur({});

      expect(ayarlar.serverUrl, SettingsService.defaultServerUrl);
      expect(ayarlar.serverUrlSource, ServerUrlSource.varsayilan);
    });

    test('uzaktan öğrenilen adres gömülü adresi geçer', () async {
      await kur({});
      await ayarlar.saveDiscoveredServerUrl('https://yeni.pod', 'kapali');

      expect(ayarlar.serverUrl, 'https://yeni.pod');
      expect(ayarlar.serverUrlSource, ServerUrlSource.bulunan);
      expect(ayarlar.directoryMessage, 'kapali');
    });

    test('kullanıcının yazdığı adres uzaktan geleni ezmez', () async {
      await kur({});
      await ayarlar.setServerUrl('https://benim.sunucum');
      await ayarlar.saveDiscoveredServerUrl('https://yeni.pod', '');

      expect(ayarlar.serverUrl, 'https://benim.sunucum');
      expect(ayarlar.serverUrlSource, ServerUrlSource.manuel);
    });

    test('elle yazılan silinince uzaktan öğrenilene dönülür', () async {
      await kur({});
      await ayarlar.saveDiscoveredServerUrl('https://yeni.pod', '');
      await ayarlar.setServerUrl('https://benim.sunucum');

      await ayarlar.resetServerUrl();

      expect(ayarlar.serverUrl, 'https://yeni.pod');
      expect(ayarlar.serverUrlSource, ServerUrlSource.bulunan);
    });
  });
}
