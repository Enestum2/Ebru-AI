import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ebru_design_model.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'app_shell.dart';
import 'result_view.dart';
import 'widgets/ebru_widgets.dart';

/// Tasarımdaki "Galerim" ekranı — iki sütunlu, farklı yükseklikte
/// kartlardan oluşan bir sergi düzeni.
class GalleryView extends StatelessWidget {
  const GalleryView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();
    final designs = viewModel.visibleHistory;

    return Scaffold(
      backgroundColor: EbruColors.background,
      appBar: EbruAppBar(
        title: 'Galerim',
        actions: [
          IconButton(
            tooltip: viewModel.showFavoritesOnly
                ? 'Tümünü göster'
                : 'Yalnızca favoriler',
            icon: Icon(
              viewModel.showFavoritesOnly
                  ? Icons.favorite
                  : Icons.favorite_border,
              size: 20,
              color: viewModel.showFavoritesOnly
                  ? EbruColors.gold
                  : EbruColors.offWhite,
            ),
            onPressed: viewModel.toggleFavoritesFilter,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Galerim', style: EbruText.displayLarge),
          const SizedBox(height: 4),
          Text('Kendi dijital atölyeniz.', style: EbruText.bodyMedium),
          const SizedBox(height: 24),
          if (designs.isEmpty)
            _BosDurum(favoriFiltresi: viewModel.showFavoritesOnly)
          else
            _SergiDuzeni(designs: designs),
        ],
      ),
    );
  }
}

class _BosDurum extends StatelessWidget {
  final bool favoriFiltresi;

  const _BosDurum({required this.favoriFiltresi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.collections_outlined,
            size: 36,
            color: EbruColors.outline,
          ),
          const SizedBox(height: 16),
          Text(
            favoriFiltresi
                ? 'Henüz favori eseriniz yok'
                : 'Atölyen henüz boş',
            style: EbruText.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            favoriFiltresi
                ? 'Bir eseri açıp kalp ikonuna dokun.'
                : 'İlk ebrunu oluştur, burada sergilensin.',
            style: EbruText.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (!favoriFiltresi) ...[
            const SizedBox(height: 24),
            GoldButton(
              label: 'Ebru oluştur',
              icon: Icons.auto_awesome,
              onPressed: () => AppShell.of(context)?.sekmeyeGit(1),
            ),
          ],
        ],
      ),
    );
  }
}

/// İki sütuna dağıtılmış kart düzeni. Kartların yükseklikleri
/// değişiyor, böylece tasarımdaki organik sergi hissi korunuyor.
class _SergiDuzeni extends StatelessWidget {
  final List<EbruDesignModel> designs;

  const _SergiDuzeni({required this.designs});

  @override
  Widget build(BuildContext context) {
    final sol = <EbruDesignModel>[];
    final sag = <EbruDesignModel>[];

    for (var i = 0; i < designs.length; i++) {
      (i.isEven ? sol : sag).add(designs[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Sutun(designs: sol, uzunBaslangic: true)),
        const SizedBox(width: 14),
        Expanded(child: _Sutun(designs: sag, uzunBaslangic: false)),
      ],
    );
  }
}

class _Sutun extends StatelessWidget {
  final List<EbruDesignModel> designs;
  final bool uzunBaslangic;

  const _Sutun({required this.designs, required this.uzunBaslangic});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < designs.length; i++) ...[
          _GaleriKarti(
            design: designs[i],
            yukseklik: (i.isEven == uzunBaslangic) ? 210 : 170,
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _GaleriKarti extends StatelessWidget {
  final EbruDesignModel design;
  final double yukseklik;

  const _GaleriKarti({required this.design, required this.yukseklik});

  String _tarih(DateTime t) {
    const aylar = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    return '${t.day} ${aylar[t.month - 1]} ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<EbruViewModel>();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ResultView(design: design)),
      ),
      onLongPress: () => _silmeyiOnayla(context, viewModel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(EbruShape.radiusXl),
            child: Stack(
              children: [
                Image.file(
                  File(design.imagePath),
                  height: yukseklik,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  errorBuilder: (_, _, _) => Container(
                    height: yukseklik,
                    color: EbruColors.surfaceVariant,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: EbruColors.outline,
                    ),
                  ),
                ),
                if (design.isFavorite)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.favorite,
                      size: 18,
                      color: EbruColors.gold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${design.style} · ${design.colorTheme}',
            style: EbruText.labelSmall.copyWith(color: EbruColors.offWhite),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _tarih(design.createdAt),
            style: EbruText.labelSmall.copyWith(color: EbruColors.outline),
          ),
        ],
      ),
    );
  }

  void _silmeyiOnayla(BuildContext context, EbruViewModel viewModel) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EbruColors.surfaceHigh,
        title: Text('Eseri sil', style: EbruText.headlineSmall),
        content: Text(
          'Bu eseri galeriden silmek istediğinize emin misiniz?',
          style: EbruText.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              viewModel.deleteDesign(design);
              Navigator.pop(dialogContext);
            },
            child: const Text(
              'Sil',
              style: TextStyle(color: EbruColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
