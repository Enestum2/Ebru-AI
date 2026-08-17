import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../viewmodels/ebru_viewmodel.dart';

/// Tasarımdaki üst çubuk: solda başlık, sağda yuvarlak profil rozeti.
class EbruAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final List<Widget> actions;

  /// Başlığa dokunulduğunda çalışır. Gizli yönetici girişi için.
  final VoidCallback? onTitleTap;

  const EbruAppBar({
    super.key,
    required this.title,
    this.showBack = false,
    this.actions = const [],
    this.onTitleTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: GestureDetector(
        onTap: onTitleTap,
        behavior: HitTestBehavior.opaque,
        child: Text(title, style: EbruText.headlineSmall),
      ),
      actions: [
        ...actions,
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: EbruColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              size: 20,
              color: EbruColors.offWhite,
            ),
          ),
        ),
      ],
    );
  }
}

/// Seçeneklerin yanındaki önizleme görseli.
///
/// Görsel yoksa (henüz üretilmemişse) çuvallamak yerine sade bir
/// yer tutucu gösterir — uygulama yine çalışır.
class OrnekGorsel extends StatelessWidget {
  final String yol;
  final bool soluk;

  const OrnekGorsel({super.key, required this.yol, this.soluk = false});

  @override
  Widget build(BuildContext context) {
    final gorsel = Image.asset(
      yol,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: EbruColors.surfaceVariant,
        child: const Icon(
          Icons.image_outlined,
          size: 18,
          color: EbruColors.outline,
        ),
      ),
    );

    if (!soluk) return gorsel;

    return Opacity(opacity: 0.55, child: gorsel);
  }
}

/// Bölüm başlığı: büyük harf, geniş harf aralıklı etiket,
/// sağında isteğe bağlı altın renkli değer.
class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text.toUpperCase(), style: EbruText.labelMedium),
        if (trailing != null)
          Text(
            trailing!,
            style: EbruText.labelSmall.copyWith(color: EbruColors.gold),
          ),
      ],
    );
  }
}

/// Altın dolgulu birincil eylem düğmesi.
class GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const GoldButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: EbruColors.gold,
          foregroundColor: EbruColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EbruShape.radiusFull),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: EbruText.body,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nane yeşili ikincil eylem (duvar kağıdı yapma gibi onay eylemleri).
class MintButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const MintButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: EbruColors.mint,
          foregroundColor: EbruColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EbruShape.radiusFull),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: EbruText.body,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çerçeveli ikincil düğme.
class OutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const OutlineButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: EbruColors.onSurface,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EbruShape.radiusFull),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: EbruText.body,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sunucu kapalıyken ana ekranın üstünde çıkan uyarı şeridi.
class ServerStatusBanner extends StatelessWidget {
  const ServerStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();
    final durum = viewModel.serverStatus;

    if (durum == null && viewModel.isCheckingServer) {
      return const LinearProgressIndicator(
        minHeight: 2,
        color: EbruColors.gold,
        backgroundColor: EbruColors.surfaceLow,
      );
    }
    if (durum == null || durum.ready) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: EbruColors.surfaceLow,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: EbruColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              durum.message.isEmpty
                  ? 'Sunucuya bağlanılamadı'
                  : durum.message,
              style: EbruText.labelSmall.copyWith(color: EbruColors.error),
            ),
          ),
          TextButton(
            onPressed: viewModel.isCheckingServer
                ? null
                : viewModel.refreshServerStatus,
            child: Text(
              'Yeniden dene',
              style: EbruText.labelSmall.copyWith(color: EbruColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String message;

  const ErrorBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        border: Border.all(color: EbruColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: EbruColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: EbruText.labelSmall.copyWith(color: EbruColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Üretim sürerken gösterilen ilerleme kartı.
class GenerationProgressCard extends StatelessWidget {
  final EbruViewModel viewModel;

  const GenerationProgressCard({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final yuzde = (viewModel.progress * 100).round();
    final kalan = viewModel.etaSeconds;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(EbruShape.radiusFull),
            child: LinearProgressIndicator(
              value: viewModel.progress > 0 ? viewModel.progress : null,
              minHeight: 6,
              color: EbruColors.gold,
              backgroundColor: EbruColors.surfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            viewModel.queueLength > 1
                ? 'Sırada bekleniyor (${viewModel.queueLength} istek)'
                : viewModel.progress > 0
                    ? 'Ebrun hazırlanıyor · %$yuzde'
                    : 'Ebrun hazırlanıyor…',
            style: EbruText.labelSmall,
          ),
          if (kalan != null && kalan > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Yaklaşık ${kalan.round()} saniye',
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
