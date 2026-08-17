/// Kullanıcının seçimlerini backend'e gönderilecek isteğe çeviren model.
///
/// Backend renk/stil ayrımı yapmıyor, tek bir Türkçe "prompt" alanı
/// bekliyor. Ekran oranı ve seed opsiyonel; gönderilirse duvar kağıdı
/// telefona tam oturur ve aynı tasarım tekrar üretilebilir.
class GenerationRequestModel {
  final String prompt;
  final double? aspectRatio;
  final int? seed;

  /// Desen yoğunluğu (0-100). Sunucu bunu doğrudan LoRA ağırlığına
  /// çeviriyor: düşükte nesneler ve düz renkler baskın, yüksekte ebru
  /// dokusu her şeyin üstüne biniyor.
  final int? intensity;

  GenerationRequestModel({
    required this.prompt,
    this.aspectRatio,
    this.seed,
    this.intensity,
  });

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      if (seed != null && seed! >= 0) 'seed': seed,
      if (intensity != null) 'intensity': intensity,
    };
  }
}
