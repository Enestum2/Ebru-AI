import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'widgets/ebru_widgets.dart';

/// Sunucuyu telefondan takip etmek için izleme ekranı.
///
/// Tarayıcıdaki `/admin` sayfasının uygulama içi karşılığı: kim,
/// ne zaman, ne üretmiş; kuyrukta ne var; hata çıkmış mı.
/// Beş saniyede bir kendini yeniliyor.
class MonitorView extends StatefulWidget {
  const MonitorView({super.key});

  @override
  State<MonitorView> createState() => _MonitorViewState();
}

class _MonitorViewState extends State<MonitorView> {
  Timer? _zamanlayici;
  UsageStats? _veri;
  List<ActiveJob> _aktifIsler = [];
  String? _hata;
  bool _ilkYukleme = true;
  String? _iptalEdilen;

  @override
  void initState() {
    super.initState();
    _yenile();
    _zamanlayici = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _yenile(),
    );
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _yenile() async {
    final viewModel = context.read<EbruViewModel>();
    try {
      final veri = await viewModel.fetchStats();
      final isler = await viewModel.fetchActiveJobs();
      if (!mounted) return;
      setState(() {
        _veri = veri;
        _aktifIsler = isler;
        _hata = null;
        _ilkYukleme = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = e.message;
        _ilkYukleme = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = 'Beklenmeyen hata: $e';
        _ilkYukleme = false;
      });
    }
  }

  Future<void> _iptalEt(ActiveJob is_) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EbruColors.surfaceHigh,
        title: Text('Üretimi iptal et', style: EbruText.headlineSmall),
        content: Text(
          is_.isRunning
              ? '${is_.owner} adlı kullanıcının süren üretimi durdurulacak '
                  've GPU boşalacak.'
              : '${is_.owner} adlı kullanıcının sıradaki üretimi iptal '
                  'edilecek.',
          style: EbruText.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'İptal et',
              style: TextStyle(color: EbruColors.error),
            ),
          ),
        ],
      ),
    );

    if (onay != true || !mounted) return;

    setState(() => _iptalEdilen = is_.id);
    try {
      await context.read<EbruViewModel>().cancelJob(is_.id);
      await _yenile();
    } on ApiException catch (e) {
      if (mounted) setState(() => _hata = e.message);
    } finally {
      if (mounted) setState(() => _iptalEdilen = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbruColors.background,
      appBar: EbruAppBar(
        title: 'İzleme',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _yenile,
          ),
        ],
      ),
      body: _govde(),
    );
  }

  Widget _govde() {
    if (_ilkYukleme) {
      return const Center(
        child: CircularProgressIndicator(color: EbruColors.gold),
      );
    }

    if (_veri == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBox(message: _hata ?? 'Veri alınamadı'),
      );
    }

    final veri = _veri!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (_hata != null) ...[
          ErrorBox(message: _hata!),
          const SizedBox(height: 16),
        ],

        Row(
          children: [
            _Kutu(
              deger: '${veri.total}',
              etiket: 'Toplam',
              renk: EbruColors.offWhite,
            ),
            const SizedBox(width: 10),
            _Kutu(
              deger: '${veri.success}',
              etiket: 'Başarılı',
              renk: EbruColors.mint,
            ),
            const SizedBox(width: 10),
            _Kutu(
              deger: '${veri.failed}',
              etiket: 'Hatalı',
              renk: veri.failed > 0 ? EbruColors.error : EbruColors.outline,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Kutu(
              deger: '${veri.queue}',
              etiket: 'Kuyrukta',
              renk: EbruColors.gold,
            ),
            const SizedBox(width: 10),
            _Kutu(
              deger: '${veri.activeJobs}',
              etiket: 'Aktif iş',
              renk: EbruColors.gold,
            ),
            const SizedBox(width: 10),
            _Kutu(
              deger: '${veri.dailyLimit}',
              etiket: 'Günlük hak',
              renk: EbruColors.outline,
            ),
          ],
        ),
        const SizedBox(height: 32),

        const SectionLabel('Süren üretimler'),
        const SizedBox(height: 12),
        if (_aktifIsler.isEmpty)
          _BosSatir('Şu anda bekleyen ya da süren üretim yok.')
        else
          ..._aktifIsler.map(
            (is_) => _AktifIsSatiri(
              is_: is_,
              iptalEdiliyor: _iptalEdilen == is_.id,
              onIptal: () => _iptalEt(is_),
            ),
          ),
        const SizedBox(height: 32),

        const SectionLabel('Bugün üretenler'),
        const SizedBox(height: 12),
        if (veri.devices.isEmpty)
          _BosSatir('Bugün henüz üretim yok.')
        else
          ...veri.devices.map(
            (c) => _CihazSatiri(
              kimlik: c.id,
              sayi: c.count,
              limit: veri.dailyLimit,
            ),
          ),
        const SizedBox(height: 32),

        const SectionLabel('Son istekler'),
        const SizedBox(height: 12),
        if (veri.records.isEmpty)
          _BosSatir('Henüz istek yok.')
        else
          ...veri.records.take(40).map((k) => _IstekSatiri(kayit: k)),
      ],
    );
  }
}

class _Kutu extends StatelessWidget {
  final String deger;
  final String etiket;
  final Color renk;

  const _Kutu({
    required this.deger,
    required this.etiket,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: EbruColors.surfaceLow,
          borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        ),
        child: Column(
          children: [
            Text(
              deger,
              style: EbruText.displayLarge.copyWith(
                fontSize: 24,
                color: renk,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              etiket,
              style: EbruText.labelSmall.copyWith(
                color: EbruColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BosSatir extends StatelessWidget {
  final String metin;

  const _BosSatir(this.metin);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        metin,
        style: EbruText.labelSmall.copyWith(color: EbruColors.outline),
      ),
    );
  }
}

/// Bekleyen ya da süren tek bir üretim, iptal düğmesiyle.
class _AktifIsSatiri extends StatelessWidget {
  final ActiveJob is_;
  final bool iptalEdiliyor;
  final VoidCallback onIptal;

  const _AktifIsSatiri({
    required this.is_,
    required this.iptalEdiliyor,
    required this.onIptal,
  });

  @override
  Widget build(BuildContext context) {
    final surenRenk = is_.isRunning ? EbruColors.gold : EbruColors.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusLg),
        border: Border(left: BorderSide(color: surenRenk, width: 2)),
      ),
      child: Row(
        children: [
          Icon(
            is_.isRunning ? Icons.bolt : Icons.hourglass_empty,
            size: 16,
            color: surenRenk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  is_.owner,
                  style: EbruText.labelSmall.copyWith(
                    color: EbruColors.offWhite,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${is_.isRunning ? "üretiliyor" : "sırada"} · '
                  '${is_.elapsed.round()} sn',
                  style: EbruText.labelSmall.copyWith(
                    color: EbruColors.outline,
                  ),
                ),
              ],
            ),
          ),
          if (is_.cancelled)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                'iptal edildi',
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.error,
                ),
              ),
            )
          else if (iptalEdiliyor)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EbruColors.error,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'İptal et',
              icon: const Icon(
                Icons.cancel_outlined,
                size: 20,
                color: EbruColors.error,
              ),
              onPressed: onIptal,
            ),
        ],
      ),
    );
  }
}

class _CihazSatiri extends StatelessWidget {
  final String kimlik;
  final int sayi;
  final int limit;

  const _CihazSatiri({
    required this.kimlik,
    required this.sayi,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final oran = limit > 0 ? (sayi / limit).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  kimlik,
                  style: EbruText.labelSmall.copyWith(
                    color: EbruColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$sayi / $limit',
                style: EbruText.labelSmall.copyWith(
                  color: oran >= 1 ? EbruColors.error : EbruColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(EbruShape.radiusFull),
            child: LinearProgressIndicator(
              value: oran,
              minHeight: 4,
              color: oran >= 1 ? EbruColors.error : EbruColors.gold,
              backgroundColor: EbruColors.surfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IstekSatiri extends StatelessWidget {
  final UsageRecord kayit;

  const _IstekSatiri({required this.kayit});

  String _saat(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusLg),
        border: Border(
          left: BorderSide(
            color: kayit.success ? EbruColors.mint : EbruColors.error,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _saat(kayit.time),
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.offWhite,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${kayit.duration.round()} sn',
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.outline,
                ),
              ),
              const Spacer(),
              Text(
                kayit.deviceId.length > 14
                    ? '${kayit.deviceId.substring(0, 14)}…'
                    : kayit.deviceId,
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            kayit.message ?? kayit.prompt,
            style: EbruText.labelSmall.copyWith(
              color: kayit.success
                  ? EbruColors.onSurfaceVariant
                  : EbruColors.error,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
