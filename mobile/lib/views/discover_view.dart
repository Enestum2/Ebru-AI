import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/design_options.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'app_shell.dart';
import 'result_view.dart';
import 'widgets/ebru_widgets.dart';

/// "Keşfet" sekmesi.
///
/// Tasarımda burada herkese açık bir akış (popüler eserler) vardı.
/// Öyle bir şey için sunucunun üretilen görselleri saklaması ve
/// paylaşması gerekiyor; şu an tasarımlar yalnızca cihazda duruyor.
/// Bu yüzden burası desen ve paletleri gerçek örnekleriyle tanıtan
/// bir başlangıç noktası olarak çalışıyor.
class DiscoverView extends StatelessWidget {
  const DiscoverView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();
    final sonEser =
        viewModel.history.isNotEmpty ? viewModel.history.first : null;

    return Scaffold(
      backgroundColor: EbruColors.background,
      appBar: const EbruAppBar(title: 'Keşfet'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (sonEser != null) ...[
            _SonEserKarti(design: sonEser),
            const SizedBox(height: 32),
          ] else ...[
            _KarsilamaKarti(),
            const SizedBox(height: 32),
          ],

          const SectionLabel('Desenler'),
          const SizedBox(height: 6),
          Text(
            'Her desenin kendi karakteri var.',
            style: EbruText.labelSmall.copyWith(color: EbruColors.outline),
          ),
          const SizedBox(height: 14),
          _TanitimSeridi(
            // Desen örnekleri kullanıcının seçtiği palete göre gösteriliyor.
            ogeler: EbruStyle.all
                .map((s) => (
                      s.previewFor(viewModel.selectedPalette),
                      s.label,
                      s.description,
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),

          const SectionLabel('Paletler'),
          const SizedBox(height: 6),
          Text(
            'Renk seçimi eserin havasını belirliyor.',
            style: EbruText.labelSmall.copyWith(color: EbruColors.outline),
          ),
          const SizedBox(height: 14),
          _TanitimSeridi(
            ogeler: EbruPalette.all
                .map((p) => (p.preview, p.label, p.description))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _KarsilamaKarti extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suyun üstünde\nbir desen bırak',
            style: EbruText.displayLarge.copyWith(fontSize: 34, height: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            'Geleneksel ebru sanatını yapay zekâyla birleştir, '
            'telefonuna özgün bir duvar kağıdı üret.',
            style: EbruText.bodyMedium,
          ),
          const SizedBox(height: 20),
          GoldButton(
            label: 'Yeni ebru oluştur',
            icon: Icons.auto_awesome,
            onPressed: () => AppShell.of(context)?.sekmeyeGit(1),
          ),
        ],
      ),
    );
  }
}

class _SonEserKarti extends StatelessWidget {
  final dynamic design;

  const _SonEserKarti({required this.design});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SON ESERİN',
          style: EbruText.labelMedium.copyWith(color: EbruColors.gold),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ResultView(design: design)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EbruShape.radiusXl),
            child: SizedBox(
              height: 260,
              width: double.infinity,
              child: Image.file(
                File(design.imagePath),
                fit: BoxFit.cover,
                cacheWidth: 800,
                errorBuilder: (_, _, _) => Container(
                  color: EbruColors.surfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GoldButton(
          label: 'Yeni ebru oluştur',
          icon: Icons.auto_awesome,
          onPressed: () => AppShell.of(context)?.sekmeyeGit(1),
        ),
      ],
    );
  }
}

/// Yatay kaydırılan tanıtım kartları: görsel + ad + tek cümle.
class _TanitimSeridi extends StatelessWidget {
  final List<(String, String, String)> ogeler;

  const _TanitimSeridi({required this.ogeler});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ogeler.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final (gorsel, ad, aciklama) = ogeler[index];

          return SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(EbruShape.radiusXl),
                  child: SizedBox(
                    height: 130,
                    width: 148,
                    child: OrnekGorsel(yol: gorsel),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  ad,
                  style: EbruText.labelSmall.copyWith(
                    color: EbruColors.offWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(
                    aciklama,
                    style: EbruText.labelSmall.copyWith(
                      color: EbruColors.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
