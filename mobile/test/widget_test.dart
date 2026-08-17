import 'package:flutter_test/flutter_test.dart';

import 'package:ebru_ai_wallpaper/models/ebru_design_model.dart';
import 'package:ebru_ai_wallpaper/models/generation_request_model.dart';
import 'package:ebru_ai_wallpaper/services/settings_service.dart';

void main() {
  group('SettingsService.normalizeUrl', () {
    test('şema yoksa http:// ekler', () {
      expect(
        SettingsService.normalizeUrl('192.168.1.5:5000'),
        'http://192.168.1.5:5000',
      );
    });

    test('sondaki eğik çizgileri ve boşlukları temizler', () {
      expect(
        SettingsService.normalizeUrl('  http://sunucu:5000///  '),
        'http://sunucu:5000',
      );
    });

    test('https adresini olduğu gibi bırakır', () {
      expect(
        SettingsService.normalizeUrl('https://ebru.ornek.com'),
        'https://ebru.ornek.com',
      );
    });
  });

  group('SettingsService.isValidUrl', () {
    test('boş metin geçersiz', () {
      expect(SettingsService.isValidUrl('   '), isFalse);
    });

    test('host içeren adres geçerli', () {
      expect(SettingsService.isValidUrl('192.168.1.5:5000'), isTrue);
      expect(SettingsService.isValidUrl('https://ebru.ornek.com'), isTrue);
    });
  });

  group('GenerationRequestModel', () {
    test('opsiyonel alanlar yoksa JSON\'a eklenmez', () {
      final json = GenerationRequestModel(prompt: 'battal').toJson();
      expect(json, {'prompt': 'battal'});
    });

    test('ekran oranı ve seed gönderilir', () {
      final json = GenerationRequestModel(
        prompt: 'battal',
        aspectRatio: 0.45,
        seed: 42,
      ).toJson();

      expect(json['aspect_ratio'], 0.45);
      expect(json['seed'], 42);
    });

    test('negatif seed gönderilmez (rastgele üretilsin diye)', () {
      final json = GenerationRequestModel(prompt: 'battal', seed: -1).toJson();
      expect(json.containsKey('seed'), isFalse);
    });
  });

  group('EbruDesignModel', () {
    test('toMap ve fromMap birbirini karşılar', () {
      final design = EbruDesignModel(
        id: '1',
        imagePath: '/tmp/ebru_1.png',
        colorTheme: 'mavi-beyaz',
        style: 'battal',
        promptTr: 'dalgalı',
        promptEn: 'wavy',
        seed: 99,
        width: 832,
        height: 1216,
        createdAt: DateTime(2026, 8, 10, 12, 30),
        isFavorite: true,
      );

      final geri = EbruDesignModel.fromMap(design.toMap());

      expect(geri.id, design.id);
      expect(geri.imagePath, design.imagePath);
      expect(geri.seed, 99);
      expect(geri.width, 832);
      expect(geri.height, 1216);
      expect(geri.isFavorite, isTrue);
      expect(geri.createdAt, design.createdAt);
    });

    test('eski biçimdeki kayıt (base64) boş imagePath ile okunur', () {
      // Eski sürüm görseli base64 olarak saklıyordu; StorageService bu
      // kayıtları boş imagePath'ten tanıyıp dosyaya taşıyor.
      final eskiKayit = {
        'id': '2',
        'imageBase64': 'AAAA',
        'colorTheme': 'pastel',
        'style': 'hatip',
        'promptTr': '',
        'promptEn': '',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'isFavorite': false,
      };

      final design = EbruDesignModel.fromMap(eskiKayit);

      expect(design.imagePath, isEmpty);
      expect(design.seed, -1);
      expect(design.colorTheme, 'pastel');
    });
  });
}
