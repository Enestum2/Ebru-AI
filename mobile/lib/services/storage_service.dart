import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ebru_design_model.dart';

/// Üretilen ebru tasarımlarını cihazda kalıcı olarak saklar.
///
/// Görsel dosyaları uygulama klasöründe tutulur, Hive'da yalnızca
/// üstveri (yol, prompt, seed, tarih) saklanır.
class StorageService {
  static const String boxName = 'ebru_designs';
  static const String _imageFolder = 'ebru_images';

  Box get _box => Hive.box(boxName);
  late final Directory _imageDir;

  Future<void> init() async {
    final belgeler = await getApplicationDocumentsDirectory();
    _imageDir = Directory('${belgeler.path}/$_imageFolder');
    if (!await _imageDir.exists()) {
      await _imageDir.create(recursive: true);
    }
  }

  String _pathFor(String id) => '${_imageDir.path}/ebru_$id.png';

  /// Yeni üretilen görseli diske yazıp kaydı oluşturur.
  Future<EbruDesignModel> saveNewDesign({
    required String id,
    required String imageBase64,
    required String colorTheme,
    required String style,
    required String promptTr,
    required String promptEn,
    required int seed,
    required int width,
    required int height,
  }) async {
    final yol = _pathFor(id);
    await File(yol).writeAsBytes(base64Decode(imageBase64));

    final design = EbruDesignModel(
      id: id,
      imagePath: yol,
      colorTheme: colorTheme,
      style: style,
      promptTr: promptTr,
      promptEn: promptEn,
      seed: seed,
      width: width,
      height: height,
      createdAt: DateTime.now(),
    );

    await _box.put(design.id, design.toMap());
    return design;
  }

  /// Tüm kayıtlı tasarımları, en yeniden en eskiye sıralı döner.
  ///
  /// Eski sürümden kalan base64 kayıtları ilk okumada dosyaya taşınır.
  Future<List<EbruDesignModel>> getAllDesigns() async {
    final designs = <EbruDesignModel>[];

    for (final anahtar in _box.keys) {
      final ham = _box.get(anahtar);
      if (ham == null) continue;

      final harita = Map<String, dynamic>.from(ham as Map);
      var design = EbruDesignModel.fromMap(harita);

      if (design.imagePath.isEmpty) {
        final tasinan = await _migrateFromBase64(harita, design);
        if (tasinan == null) continue;  // taşınamadıysa kaydı atla
        design = tasinan;
      }

      designs.add(design);
    }

    designs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return designs;
  }

  /// Eski biçimdeki (base64) kaydı dosyaya taşır.
  Future<EbruDesignModel?> _migrateFromBase64(
    Map<String, dynamic> harita,
    EbruDesignModel design,
  ) async {
    final base64Veri = harita['imageBase64'] as String?;
    if (base64Veri == null || base64Veri.isEmpty) {
      // Ne dosya yolu ne base64 var; kayıt kullanılamaz.
      await _box.delete(design.id);
      return null;
    }

    try {
      final yol = _pathFor(design.id);
      await File(yol).writeAsBytes(base64Decode(base64Veri));

      final yeni = design.copyWith(imagePath: yol);
      await _box.put(yeni.id, yeni.toMap());
      return yeni;
    } catch (_) {
      await _box.delete(design.id);
      return null;
    }
  }

  /// Görselin ham baytlarını okur (paylaşma, wallpaper, galeriye kaydetme).
  Future<Uint8List> readImageBytes(EbruDesignModel design) {
    return File(design.imagePath).readAsBytes();
  }

  /// Favori durumunu değiştirir.
  Future<void> toggleFavorite(EbruDesignModel design) async {
    design.isFavorite = !design.isFavorite;
    await _box.put(design.id, design.toMap());
  }

  /// Bir tasarımı hem kayıttan hem diskten siler.
  Future<void> deleteDesign(EbruDesignModel design) async {
    await _box.delete(design.id);

    final dosya = File(design.imagePath);
    if (await dosya.exists()) {
      await dosya.delete();
    }
  }
}
