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
            itemCount: EbruPalette.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final palet = EbruPalette.all[index];
              final secili = viewModel.selectedPalette == palet.id;

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
          secilen.description,
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
