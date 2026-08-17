/// Uygulamadaki seçim seçenekleri.
///
/// Her seçeneğin bir önizleme görseli var: kullanıcı seçtiği şeyin ne
/// üreteceğini önceden görüyor. Görseller gerçek üretimlerden alındı,
/// temsili çizim değil.
class EbruPalette {
  final String id;
  final String label;
  final String description;
  final String preview;

  const EbruPalette({
    required this.id,
    required this.label,
    required this.description,
    required this.preview,
  });

  static const List<EbruPalette> all = [
    EbruPalette(
      id: 'osmanli',
      label: 'Osmanlı',
      description: 'Kızıl, altın ve fildişi',
      preview: 'assets/previews/palet_osmanli.jpg',
    ),
    EbruPalette(
      id: 'zumrut',
      label: 'Zümrüt',
      description: 'Derin yeşil, altın damarlı',
      preview: 'assets/previews/palet_zumrut.jpg',
    ),
    EbruPalette(
      id: 'okyanus',
      label: 'Okyanus',
      description: 'Mavi tonları ve beyaz köpük',
      preview: 'assets/previews/palet_okyanus.jpg',
    ),
    EbruPalette(
      id: 'gece',
      label: 'Gece',
      description: 'Lacivert, gümüş ve mor',
      preview: 'assets/previews/palet_gece.jpg',
    ),
    EbruPalette(
      id: 'lale',
      label: 'Lale',
      description: 'Gül pembesi ve kızıl',
      preview: 'assets/previews/palet_lale.jpg',
    ),
    EbruPalette(
      id: 'pastel',
      label: 'Pastel',
      description: 'Yumuşak, soluk tonlar',
      preview: 'assets/previews/palet_pastel.jpg',
    ),

    // İkili renk kombinasyonları.
    //
    // id doğrudan sunucuya gönderiliyor ("<id> renklerinde") ve aynı
    // zamanda önizleme dosya adında kullanılıyor. Bu yüzden Türkçe
    // karakter içermiyor ve sunucudaki COLOR_PROMPTS anahtarlarıyla
    // birebir aynı olmak zorunda.
    EbruPalette(
      id: 'sari-kirmizi',
      label: 'Sarı-Kırmızı',
      description: 'Altın sarısı ve derin kırmızı',
      preview: 'assets/previews/palet_sari-kirmizi.jpg',
    ),
    EbruPalette(
      id: 'sari-lacivert',
      label: 'Sarı-Lacivert',
      description: 'Altın sarısı ve lacivert',
      preview: 'assets/previews/palet_sari-lacivert.jpg',
    ),
    EbruPalette(
      id: 'siyah-beyaz',
      label: 'Siyah-Beyaz',
      description: 'Yüksek kontrast, tek renk',
      preview: 'assets/previews/palet_siyah-beyaz.jpg',
    ),
  ];
}

/// Geleneksel ebru desenleri.
///
/// Her desenin önizlemesi seçili palete göre değişiyor: Zümrüt
/// seçiliyken desen kartları da yeşil örnekler gösteriyor. Tek palette
/// üretilmiş örnekler kullanıcıyı yanıltıyordu — hangi paleti seçerse
/// seçsin kartlar aynı renkte kalıyordu.
class EbruStyle {
  final String id;
  final String label;
  final String description;

  /// Dosya adında kullanılan, Türkçe karakter içermeyen karşılık.
  final String slug;

  const EbruStyle({
    required this.id,
    required this.label,
    required this.description,
    required this.slug,
  });

  /// Seçili palete ait önizleme görselinin yolu.
  String previewFor(String paletteId) =>
      'assets/previews/desen_${paletteId}_$slug.jpg';

  static const List<EbruStyle> all = [
    EbruStyle(
      id: 'battal',
      label: 'Battal',
      description: 'Serbest damlatılmış organik lekeler',
      slug: 'battal',
    ),
    EbruStyle(
      id: 'hatip',
      label: 'Hatip',
      description: 'Merkezî çiçek ve rozet motifi',
      slug: 'hatip',
    ),
    EbruStyle(
      id: 'taraklı',
      label: 'Taraklı',
      description: 'Tarakla çekilmiş düzenli dalgalar',
      slug: 'tarakli',
    ),
    EbruStyle(
      id: 'bülbül yuvası',
      label: 'Bülbül yuvası',
      description: 'İç içe sarmal girdaplar',
      slug: 'bulbul_yuvasi',
    ),
    EbruStyle(
      id: 'gelgit',
      label: 'Gelgit',
      description: 'İleri geri çekilmiş S kıvrımları',
      slug: 'gelgit',
    ),
    EbruStyle(
      id: 'şal',
      label: 'Şal',
      description: 'İç içe geçen tüy benzeri doku',
      slug: 'sal',
    ),
  ];
}
