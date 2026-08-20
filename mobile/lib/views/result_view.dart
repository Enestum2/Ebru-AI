import 'dart:io';

import 'package:async_wallpaper/async_wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ebru_design_model.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'widgets/ebru_widgets.dart';

/// Tasarımdaki "Önizleme" ekranı: eser bir telefon çerçevesi içinde
/// gösteriliyor, altında duvar kağıdı hedefi seçiliyor.
class ResultView extends StatefulWidget {
  final EbruDesignModel design;

  const ResultView({super.key, required this.design});

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  bool _isProcessing = false;
  String? _statusMessage;
  int _hedef = 0; // 0: kilit, 1: ana ekran, 2: her ikisi

  EbruViewModel get _viewModel => context.read<EbruViewModel>();

  void _durumGoster(String mesaj) {
    if (mounted) setState(() => _statusMessage = mesaj);
  }

  Future<void> _saveToGallery() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });
    try {
      final bytes = await _viewModel.readImageBytes(widget.design);
      await Gal.putImageBytes(bytes, name: 'ebru_${widget.design.id}');
      _durumGoster('Galeriye kaydedildi');
    } catch (e) {
      _durumGoster('Kaydetme hatası: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _share() async {
    try {
      final bytes = await _viewModel.readImageBytes(widget.design);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ebru_${widget.design.id}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _durumGoster('Paylaşma hatası: $e');
    }
  }

  Future<void> _setAsWallpaper() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });
    try {
      final hedef = switch (_hedef) {
        0 => WallpaperTarget.lock,
        1 => WallpaperTarget.home,
        _ => WallpaperTarget.both,
      };

      await AsyncWallpaper.setWallpaper(
        WallpaperRequest(
          target: hedef,
          sourceType: WallpaperSourceType.file,
          source: widget.design.imagePath,
        ),
      );
      _durumGoster('Duvar kağıdı olarak ayarlandı');
    } catch (e) {
      _durumGoster('Wallpaper hatası: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _regenerate({int? seed}) async {
    final viewModel = _viewModel;
    final ekran = MediaQuery.sizeOf(context);

    setState(() {
      _isProcessing = true;
      _statusMessage = seed != null
          ? 'Benzer bir eser hazırlanıyor…'
          : 'Yeni bir eser hazırlanıyor…';
    });

    // Ekrandaki eserin kendi ayarlarıyla üretiliyor, o anki
    // seçimlerle değil: kullanıcı baktığı eserin bir benzerini
    // bekliyor, en son seçtiği paletten bir şey değil.
    await viewModel.generateDesign(
      aspectRatio: ekran.width / ekran.height,
      seed: seed,
      palet: widget.design.colorTheme,
      desen: widget.design.style,
      ekIstek: widget.design.promptTr,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (viewModel.errorMessage != null) {
      _durumGoster(viewModel.errorMessage!);
      return;
    }
    if (viewModel.currentDesign != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultView(design: viewModel.currentDesign!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();
    final design = widget.design;

    return Scaffold(
      backgroundColor: EbruColors.background,
      appBar: EbruAppBar(
        title: 'Önizleme',
        showBack: true,
        actions: [
          IconButton(
            tooltip: design.isFavorite
                ? 'Favoriden çıkar'
                : 'Favorilere ekle',
            icon: Icon(
              design.isFavorite ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: design.isFavorite
                  ? EbruColors.gold
                  : EbruColors.offWhite,
            ),
            onPressed: () => viewModel.toggleFavorite(design),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Column(
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 30,
                color: EbruColors.mint,
              ),
              const SizedBox(height: 10),
              Text('Tebrikler', style: EbruText.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Benzersiz eseriniz hazır.',
                style: EbruText.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _TelefonCercevesi(design: design),
          const SizedBox(height: 24),
          _HedefSecici(
            secili: _hedef,
            onChanged: (i) => setState(() => _hedef = i),
          ),
          const SizedBox(height: 20),
          if (_statusMessage != null) ...[
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: EbruText.labelSmall,
            ),
            const SizedBox(height: 12),
          ],
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: EbruColors.gold),
            )
          else ...[
            MintButton(
              label: 'Duvar kağıdı yap',
              icon: Icons.wallpaper,
              onPressed: _setAsWallpaper,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(
                    label: 'Galeriye kaydet',
                    icon: Icons.download,
                    onPressed: _saveToGallery,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Colors.white24),
                      shape: const CircleBorder(),
                    ),
                    onPressed: _share,
                    child: const Icon(
                      Icons.share,
                      size: 18,
                      color: EbruColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(
                    label: 'Yeni eser',
                    icon: Icons.refresh,
                    onPressed: _regenerate,
                  ),
                ),
                if (design.seed >= 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlineButton(
                      label: 'Benzerini üret',
                      icon: Icons.auto_fix_high,
                      onPressed: () => _regenerate(seed: design.seed),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (design.width > 0) ...[
            const SizedBox(height: 20),
            Text(
              '${design.width}×${design.height}'
              '${design.seed >= 0 ? "  ·  seed ${design.seed}" : ""}',
              textAlign: TextAlign.center,
              style: EbruText.labelSmall.copyWith(
                color: EbruColors.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Eseri telefon çerçevesi içinde gösterir. Dokununca tam ekran açılır.
class _TelefonCercevesi extends StatelessWidget {
  final EbruDesignModel design;

  const _TelefonCercevesi({required this.design});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _TamEkran(design: design),
          ),
        ),
        child: Container(
          width: 210,
          height: 420,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: EbruColors.surfaceVariant,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(design.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: EbruColors.surfaceHigh,
                    child: const Center(
                      child: Text(
                        'Görsel bulunamadı',
                        style: TextStyle(color: EbruColors.outline),
                      ),
                    ),
                  ),
                ),
                // Kilit ekranı hissi için saat.
                Positioned(
                  top: 42,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        '09:41',
                        style: EbruText.displayLarge.copyWith(
                          fontSize: 38,
                          color: Colors.white,
                          shadows: const [
                            Shadow(blurRadius: 12, color: Colors.black54),
                          ],
                        ),
                      ),
                      Text(
                        'Salı, 24 Ekim',
                        style: EbruText.labelSmall.copyWith(
                          color: Colors.white70,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TamEkran extends StatelessWidget {
  final EbruDesignModel design;

  const _TamEkran({required this.design});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PhotoView(
        imageProvider: FileImage(File(design.imagePath)),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}

class _HedefSecici extends StatelessWidget {
  final int secili;
  final ValueChanged<int> onChanged;

  const _HedefSecici({required this.secili, required this.onChanged});

  static const List<String> _etiketler = [
    'Kilit ekranı',
    'Ana ekran',
    'Her ikisi',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusFull),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: List.generate(_etiketler.length, (i) {
          final aktif = secili == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: aktif
                      ? EbruColors.surfaceVariant
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(EbruShape.radiusFull),
                ),
                child: Text(
                  _etiketler[i],
                  style: EbruText.labelSmall.copyWith(
                    color: aktif
                        ? EbruColors.offWhite
                        : EbruColors.onSurfaceVariant,
                    fontWeight: aktif ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
