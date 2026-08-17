/// Üretilen tek bir ebru tasarımını temsil eder.
/// Hem geçmiş/galeri listesinde hem de sonuç ekranında kullanılır.
///
/// NOT: Görsel verisi artık modelde base64 olarak tutulmuyor. Büyük
/// base64 metinleri Hive'da hem yeri şişiriyor hem de galeri açılırken
/// hepsi belleğe geliyordu. Görsel diske yazılıyor, burada yalnızca
/// dosya yolu saklanıyor.
class EbruDesignModel {
  final String id;
  final String imagePath;
  final String colorTheme;
  final String style;
  final String promptTr;
  final String promptEn;
  final int seed;
  final int width;
  final int height;
  final DateTime createdAt;
  bool isFavorite;

  EbruDesignModel({
    required this.id,
    required this.imagePath,
    required this.colorTheme,
    required this.style,
    required this.promptTr,
    required this.promptEn,
    required this.createdAt,
    this.seed = -1,
    this.width = 0,
    this.height = 0,
    this.isFavorite = false,
  });

  EbruDesignModel copyWith({
    String? imagePath,
    bool? isFavorite,
  }) {
    return EbruDesignModel(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      colorTheme: colorTheme,
      style: style,
      promptTr: promptTr,
      promptEn: promptEn,
      createdAt: createdAt,
      seed: seed,
      width: width,
      height: height,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  /// Hive'da saklamak için Map'e çevirme
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'colorTheme': colorTheme,
      'style': style,
      'promptTr': promptTr,
      'promptEn': promptEn,
      'seed': seed,
      'width': width,
      'height': height,
      'createdAt': createdAt.toIso8601String(),
      'isFavorite': isFavorite,
    };
  }

  /// Hive'dan okurken Map'ten model oluşturma.
  ///
  /// [imagePath] boş dönerse kayıt eski biçimdedir (görsel base64 olarak
  /// saklanmış); StorageService bunu dosyaya taşır.
  factory EbruDesignModel.fromMap(Map<String, dynamic> map) {
    return EbruDesignModel(
      id: map['id'] as String,
      imagePath: map['imagePath'] as String? ?? '',
      colorTheme: map['colorTheme'] as String? ?? '',
      style: map['style'] as String? ?? '',
      promptTr: map['promptTr'] as String? ?? '',
      promptEn: map['promptEn'] as String? ?? '',
      seed: map['seed'] as int? ?? -1,
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      createdAt: DateTime.parse(map['createdAt'] as String),
      isFavorite: map['isFavorite'] as bool? ?? false,
    );
  }
}
