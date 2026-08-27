import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/design_options.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'result_view.dart';
import 'widgets/ebru_widgets.dart';

/// Ana oluşturma ekranı.
///
/// Her seçenek gerçek bir üretimden alınmış önizleme görseliyle
/// gösteriliyor — kullanıcı "pastel" seçtiğinde ne çıkacağını tahmin
/// etmek zorunda kalmıyor, görüyor.
class CreateView extends StatelessWidget {
  const CreateView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();

    return Scaffold(
      backgroundColor: EbruColors.background,
      appBar: const EbruAppBar(title: 'Oluştur'),
      body: Column(
        children: [
          const ServerStatusBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  'Bugün nasıl bir ebru istersiniz?',
                  textAlign: TextAlign.center,
                  style: EbruText.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Renk ve deseni seçin, örnekler nasıl bir sonuç '
                  'çıkacağını gösteriyor.',
                  textAlign: TextAlign.center,
                  style: EbruText.bodyMedium,
                ),
                const SizedBox(height: 32),

                const SectionLabel('Renk paleti'),
                const SizedBox(height: 14),
                _PaletteRow(viewModel: viewModel),
                const SizedBox(height: 32),

                const SectionLabel('Desen'),
                const SizedBox(height: 14),
                _StyleList(viewModel: viewModel),
                const SizedBox(height: 28),

                _IntensitySlider(viewModel: viewModel),
                const SizedBox(height: 32),

                const SectionLabel('Ek istek', trailing: 'isteğe bağlı'),
                const SizedBox(height: 12),
                TextField(
                  maxLines: 3,
                  style: const TextStyle(
                    fontFamily: EbruText.body,
                    fontSize: 14,
                    color: EbruColors.onSurface,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Örn: dalgalı, koyu tonlarda — '
                        'ya da bir nesne: araba, kuş, cami',
                  ),
                  onChanged: viewModel.setPrompt,
                ),
                const SizedBox(height: 10),
                const _NesneIpucu(),
                const SizedBox(height: 28),

                if (viewModel.errorMessage != null) ...[
                  ErrorBox(message: viewModel.errorMessage!),
                  const SizedBox(height: 16),
                ],

                _GenerateSection(viewModel: viewModel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Desen yoğunluğu kaydırıcısı.
///
/// Sunucuda doğrudan LoRA ağırlığına dönüşüyor (0.30–0.90). Ölçümde
/// düşük değerde nesneler ve düz renkler baskın, yüksekte ebru dokusu
/// her şeyin üstüne biniyor.
class _IntensitySlider extends StatelessWidget {
  final EbruViewModel viewModel;

  const _IntensitySlider({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Desen yoğunluğu',
          trailing: viewModel.intensityLabel,
        ),
        const SizedBox(height: 4),
        Slider(
          value: viewModel.intensity.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          onChanged: (deger) => viewModel.setIntensity(deger.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Nesneler net',
              style: EbruText.labelSmall.copyWith(
                color: EbruColors.outline,
              ),
            ),
            Text(
              'Ebru dokusu baskın',
              style: EbruText.labelSmall.copyWith(
                color: EbruColors.outline,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Somut nesne yazıldığında ne olacağını anlatan not.
///
/// Ölçümle doğrulandı: nesne istendiğinde sunucu ebru dokusunu geri
/// çekiyor, yoksa doku nesneyi tamamen örtüyor. Kullanıcının bunu
/// önceden bilmesi gerekiyor, yoksa "araba yazdım ama çıkmadı" ya da
/// tersi bir beklenti oluşuyor.
class _NesneIpucu extends StatelessWidget {
  const _NesneIpucu();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusLg),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: EbruColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Somut bir nesne yazarsan (araba, kuş, cami) o nesne '
              'görselde yer alır; rengi seçtiğin palete uyar. Yoğunluğu '
              'yükseltirsen nesnenin üstünde de ebru dokusu belirir.',
              style: EbruText.labelSmall.copyWith(
                color: EbruColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yatay kaydırılan palet seçicileri. Her daire, o paletle üretilmiş
/// gerçek bir ebru görselinin kırpılmış hâli.
class _PaletteRow extends StatelessWidget {
  final EbruViewModel viewModel;

  const _PaletteRow({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final secilen = EbruPalette.all
        .firstWhere((p) => p.id == viewModel.selectedPalette);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Son sıra "Kendi rengim": hazır paletlerin yanında,
            // sitedeki düzenin aynısı.
            itemCount: EbruPalette.all.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              if (index == EbruPalette.all.length) {
                return _OzelRenkDairesi(viewModel: viewModel);
              }
              final palet = EbruPalette.all[index];
              // Özel renk açıkken hazır paletlerin hiçbiri seçili
              // görünmemeli; yoksa hangisinin geçerli olduğu belirsiz.
              final secili = !viewModel.ozelRenkAcik &&
                  viewModel.selectedPalette == palet.id;

              return GestureDetector(
                onTap: () => viewModel.setPalette(palet.id),
                child: Column(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: secili
                              ? EbruColors.gold
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: OrnekGorsel(
                          yol: palet.preview,
                          soluk: !secili,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      palet.label,
                      style: EbruText.labelSmall.copyWith(
                        color: secili
                            ? EbruColors.gold
                            : EbruColors.onSurfaceVariant,
                        fontWeight:
                            secili ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          viewModel.ozelRenkAcik
              ? 'Kendi renkleriniz kullanılacak'
              : secilen.description,
          style: EbruText.labelSmall.copyWith(color: EbruColors.outline),
        ),
        if (viewModel.ozelRenkAcik) ...[
          const SizedBox(height: 12),
          _OzelRenkPaneli(viewModel: viewModel),
        ],
      ],
    );
  }
}

/// Palet satırının sonundaki "Kendi rengim" dairesi.
class _OzelRenkDairesi extends StatelessWidget {
  final EbruViewModel viewModel;

  const _OzelRenkDairesi({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final acik = viewModel.ozelRenkAcik;

    return GestureDetector(
      onTap: () => acik
          ? viewModel.ozelRenkleriKapat()
          : viewModel.setOzelRenkler(_OzelRenkPaneli.varsayilan),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: acik ? EbruColors.gold : Colors.transparent,
                width: 2,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EbruColors.surfaceVariant,
                gradient: acik
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: viewModel.ozelRenkler
                            .map(_OzelRenkPaneli.renkCoz)
                            .toList(),
                      )
                    : null,
              ),
              child: acik
                  ? null
                  : const Icon(
                      Icons.tune,
                      size: 24,
                      color: EbruColors.onSurfaceVariant,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kendi rengim',
            style: EbruText.labelSmall.copyWith(
              color: acik ? EbruColors.gold : EbruColors.onSurfaceVariant,
              fontWeight: acik ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Özel renk paneli: iki (isteğe bağlı üç) renk kutusu.
///
/// Hazır bir renk seçici paketi eklenmedi. Küratörlü bir ızgara hem
/// bağımlılık getirmiyor hem de dokunmatik ekranda tam serbest bir
/// renk çarkından daha kullanışlı; ebruda zaten sınırlı bir palet
/// geleneği var.
class _OzelRenkPaneli extends StatelessWidget {
  final EbruViewModel viewModel;

  const _OzelRenkPaneli({required this.viewModel});

  /// "Kendi rengim" ilk açıldığında gelen ikili: ebruda en sık
  /// kullanılan kızıl-altın. Boş kutuyla açmak kullanıcıyı boş
  /// ekranda bırakıyordu.
  static const List<String> varsayilan = ['#C1272D', '#D4AF37'];

  /// Izgaradaki renkler. Geleneksel ebru boyalarına yakın tonlar.
  static const List<String> secenekler = [
    '#C1272D', '#8E1B1B', '#E85D2A', '#D4AF37', '#F2C94C', '#FFFDD0',
    '#1E8449', '#0E5A3C', '#0F7B8A', '#00838F', '#1B4F9C', '#0F2A5F',
    '#5B2C87', '#7D3C98', '#B03A75', '#E38AAE', '#8B4513', '#5D4037',
    '#F5F5DC', '#E0DCC8', '#9E9E9E', '#4A4A4A', '#1A1A1A', '#FFFFFF',
  ];

  /// '#rrggbb' -> Color. Bozuk değer gelirse gri döner; ekran
  /// çökmemeli.
  static Color renkCoz(String hex) {
    final temiz = hex.replaceAll('#', '').trim();
    if (temiz.length != 6) return EbruColors.surfaceVariant;
    final deger = int.tryParse(temiz, radix: 16);
    if (deger == null) return EbruColors.surfaceVariant;
    return Color(0xFF000000 | deger);
  }

  void _renkSec(BuildContext context, int sira) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EbruColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EbruShape.radiusXl),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sira == 0
                    ? 'Ana renk'
                    : (sira == 1 ? 'İkinci renk' : 'Üçüncü renk'),
                style: EbruText.headlineSmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: secenekler.map((hex) {
                  final secili = sira < viewModel.ozelRenkler.length &&
                      viewModel.ozelRenkler[sira].toLowerCase() ==
                          hex.toLowerCase();
                  return GestureDetector(
                    onTap: () {
                      final yeni = List<String>.from(viewModel.ozelRenkler);
                      while (yeni.length <= sira) {
                        yeni.add(varsayilan.first);
                      }
                      yeni[sira] = hex;
                      viewModel.setOzelRenkler(yeni);
                      Navigator.pop(sheetContext);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: renkCoz(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: secili
                              ? EbruColors.gold
                              : Colors.white24,
                          width: secili ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final renkler = viewModel.ozelRenkler;
    final ucuncuVar = renkler.length > 2;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _kutu(context, 0, 'Ana renk'),
              const SizedBox(width: 12),
              _kutu(context, 1, 'İkinci'),
              if (ucuncuVar) ...[
                const SizedBox(width: 12),
                _kutu(context, 2, 'Üçüncü'),
              ],
              const Spacer(),
              TextButton(
                onPressed: () {
                  final yeni = List<String>.from(renkler);
                  if (ucuncuVar) {
                    yeni.removeAt(2);
                  } else {
                    yeni.add('#F5F5DC');
                  }
                  viewModel.setOzelRenkler(yeni);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  ucuncuVar ? 'Üçüncüyü kaldır' : 'Üçüncü renk ekle',
                  style: EbruText.labelSmall.copyWith(
                    color: EbruColors.gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Seçtiğiniz renkler hazır paletin yerine geçer. '
            'İki renk çoğu ebru için yeterlidir.',
            style: EbruText.labelSmall.copyWith(
              color: EbruColors.outline,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kutu(BuildContext context, int sira, String etiket) {
    final hex = sira < viewModel.ozelRenkler.length
        ? viewModel.ozelRenkler[sira]
        : varsayilan.first;

    return Column(
      children: [
        GestureDetector(
          onTap: () => _renkSec(context, sira),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: renkCoz(hex),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          etiket,
          style: EbruText.labelSmall.copyWith(color: EbruColors.outline),
        ),
      ],
    );
  }
}

/// Desen kartları: solda o desenin gerçek çıktısı, sağda adı ve
/// desenin ne olduğunu anlatan bir cümle.
class _StyleList extends StatelessWidget {
  final EbruViewModel viewModel;

  const _StyleList({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: EbruStyle.all.map((stil) {
        final secili = viewModel.selectedStyle == stil.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(EbruShape.radiusXl),
            onTap: () => viewModel.setStyle(stil.id),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: secili
                    ? EbruColors.surfaceContainer
                    : EbruColors.surfaceLow,
                borderRadius: BorderRadius.circular(EbruShape.radiusXl),
                border: Border.all(
                  color: secili ? EbruColors.gold : Colors.white10,
                  width: secili ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(EbruShape.radiusLg),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: OrnekGorsel(
                        // Örnek, seçili palete göre değişiyor.
                        yol: stil.previewFor(viewModel.selectedPalette),
                        soluk: !secili,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stil.label,
                          style: EbruText.bodyLarge.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: secili
                                ? EbruColors.offWhite
                                : EbruColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stil.description,
                          style: EbruText.labelSmall.copyWith(
                            color: EbruColors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (secili)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.check_circle,
                        size: 20,
                        color: EbruColors.gold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GenerateSection extends StatelessWidget {
  final EbruViewModel viewModel;

  const _GenerateSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading) {
      return GenerationProgressCard(viewModel: viewModel);
    }

    return GoldButton(
      label: 'Ebruyu oluştur',
      icon: Icons.auto_awesome,
      onPressed: () async {
        final ekran = MediaQuery.sizeOf(context);
        await viewModel.generateDesign(
          aspectRatio: ekran.width / ekran.height,
        );

        if (viewModel.currentDesign != null && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResultView(design: viewModel.currentDesign!),
            ),
          );
        }
      },
    );
  }
}
