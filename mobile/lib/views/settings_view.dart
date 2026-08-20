import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'monitor_view.dart';
import 'widgets/ebru_widgets.dart';

/// Ayarlar ekranı.
///
/// Yönetim bölümü yalnızca yönetici hesabıyla giriş yapıldığında
/// görünüyor; sunucu bunu bildiriyor. Önceden başlığa yedi kez
/// dokunup anahtar girmek gerekiyordu.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _controller;

  String? _hataMetni;
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<EbruViewModel>();
    _controller = TextEditingController(text: viewModel.serverUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (!SettingsService.isValidUrl(_controller.text)) {
      setState(() => _hataMetni = 'Geçerli bir adres gir');
      return;
    }

    setState(() {
      _hataMetni = null;
      _kaydediliyor = true;
    });

    final viewModel = context.read<EbruViewModel>();
    await viewModel.setServerUrl(_controller.text);

    if (!mounted) return;
    setState(() {
      _kaydediliyor = false;
      _controller.text = viewModel.serverUrl;
    });

    final basarili = viewModel.serverStatus?.ready ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          basarili
              ? 'Sunucuya bağlanıldı'
              : 'Adres kaydedildi, bağlanılamadı',
        ),
      ),
    );
  }

  void _cikisOnayi(BuildContext context, EbruViewModel viewModel) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EbruColors.surfaceHigh,
        title: Text('Çıkış yap', style: EbruText.headlineSmall),
        content: Text(
          'Eserlerin telefonunda kalmaya devam eder. '
          'Tekrar giriş yaptığında üretime kaldığın yerden devam edersin.',
          style: EbruText.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              viewModel.logout();
            },
            child: const Text(
              'Çıkış yap',
              style: TextStyle(color: EbruColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Hesap menüsü: kullanıcı adı, hesabı sil, çıkış.
  ///
  /// Sitedeki profil simgesinin açtığı menüyle aynı seçenekleri
  /// veriyor; iki yüzün aynı yerde aynı şeyi sunması bekleniyor.
  void _hesapMenusu(BuildContext context, EbruViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EbruColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EbruShape.radiusXl),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: EbruColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: EbruColors.gold,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Giriş yapıldı',
                          style: EbruText.labelSmall.copyWith(
                            color: EbruColors.outline,
                          ),
                        ),
                        Text(
                          viewModel.username.isEmpty
                              ? 'Oturum açık'
                              : viewModel.username,
                          style: EbruText.bodyLarge.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: EbruColors.error,
              ),
              title: Text(
                'Hesabımı sil',
                style: EbruText.bodyLarge.copyWith(
                  fontSize: 15,
                  color: EbruColors.error,
                ),
              ),
              subtitle: Text(
                'Hesap ve bütün veriler kalıcı olarak silinir',
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.outline,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _hesapSilOnayi(context, viewModel);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: EbruColors.onSurfaceVariant,
              ),
              title: Text(
                'Çıkış yap',
                style: EbruText.bodyLarge.copyWith(fontSize: 15),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _cikisOnayi(context, viewModel);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Hesap silme onayı.
  ///
  /// Silinen hesap geri gelmiyor, o yüzden onay penceresi kullanıcıdan
  /// şifresini (Google hesaplarında kullanıcı adını) yazmasını istiyor.
  void _hesapSilOnayi(BuildContext context, EbruViewModel viewModel) {
    showDialog(
      context: context,
      builder: (_) => _HesapSilPenceresi(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();
    final durum = viewModel.serverStatus;
    final hazir = durum?.ready ?? false;

    return Scaffold(
      backgroundColor: EbruColors.background,
      appBar: const EbruAppBar(title: 'Ayarlar'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _DurumKarti(
            hazir: hazir,
            mesaj: durum?.message ?? '',
            yenileniyor: viewModel.isCheckingServer,
            onYenile: viewModel.refreshServerStatus,
          ),
          const SizedBox(height: 32),

          const SectionLabel('Hesap'),
          const SizedBox(height: 14),
          // Karta dokununca hesap menusu aciliyor; sitedeki profil
          // simgesiyle ayni: kullanici adi, hesabi sil, cikis.
          Material(
            color: EbruColors.surfaceLow,
            borderRadius: BorderRadius.circular(EbruShape.radiusXl),
            child: InkWell(
              onTap: () => _hesapMenusu(context, viewModel),
              borderRadius: BorderRadius.circular(EbruShape.radiusXl),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: EbruColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        size: 22,
                        color: EbruColors.gold,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            viewModel.username.isEmpty
                                ? 'Oturum açık'
                                : viewModel.username,
                            style: EbruText.bodyLarge.copyWith(fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hesap işlemleri için dokunun',
                            style: EbruText.labelSmall.copyWith(
                              color: EbruColors.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.expand_more,
                      size: 22,
                      color: EbruColors.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _hesapSilOnayi(context, viewModel),
              icon: const Icon(
                Icons.delete_forever_outlined,
                size: 18,
                color: EbruColors.error,
              ),
              label: Text(
                'Hesabımı sil',
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.error,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 32),

          const SectionLabel('Atölyen'),
          const SizedBox(height: 14),
          Row(
            children: [
              _Sayac(deger: '${viewModel.history.length}', etiket: 'Eser'),
              const SizedBox(width: 12),
              _Sayac(deger: '${viewModel.favoriteCount}', etiket: 'Favori'),
            ],
          ),
          const SizedBox(height: 32),

          const SectionLabel('Hakkında'),
          const SizedBox(height: 12),
          Text(
            'Ebru AI, geleneksel Türk ebru sanatını yapay zekâyla '
            'birleştirerek telefonun için özgün duvar kağıtları üretir. '
            'Her eser tek seferlik ve size özeldir.',
            style: EbruText.bodyMedium,
          ),

          if (viewModel.isAdmin) ...[
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 24),

            const SectionLabel('Yönetim'),
            const SizedBox(height: 6),
            Text(
              'Bu bölüm yalnızca yönetici hesabında görünür.',
              style: EbruText.labelSmall.copyWith(
                color: EbruColors.outline,
              ),
            ),
            const SizedBox(height: 14),
            OutlineButton(
              label: 'İzleme ekranı',
              icon: Icons.monitor_heart_outlined,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonitorView()),
              ),
            ),
            const SizedBox(height: 28),

            const SectionLabel('Eserler'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: EbruColors.surfaceLow,
                borderRadius: BorderRadius.circular(EbruShape.radiusXl),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Telefon galerisine kaydet',
                          style: EbruText.bodyLarge.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Üretilen her eser telefonun galerisine de '
                          'kopyalanır. Uygulamayı kaldırsan bile kalır.',
                          style: EbruText.labelSmall.copyWith(
                            color: EbruColors.outline,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: viewModel.autoSaveToGallery,
                    onChanged: viewModel.setAutoSaveToGallery,
                  ),
                ],
              ),
            ),
            if (viewModel.galleryWarning != null) ...[
              const SizedBox(height: 8),
              Text(
                viewModel.galleryWarning!,
                style: EbruText.labelSmall.copyWith(
                  color: EbruColors.error,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 28),

            const SectionLabel('Sunucu adresi'),
            const SizedBox(height: 6),
            Text(
              switch (viewModel.serverUrlSource) {
                ServerUrlSource.manuel =>
                  'Kendi yazdığın adres kullanılıyor. '
                      'Otomatik adrese dönmek için aşağıdaki düğmeye bas.',
                ServerUrlSource.bulunan =>
                  'Adres otomatik güncelleniyor; elle bir şey yapman '
                      'gerekmiyor.',
                ServerUrlSource.varsayilan =>
                  'Uygulamaya gömülü adres kullanılıyor. Güncel adres '
                      'henüz alınamadı.',
              },
              style: const TextStyle(
                fontFamily: EbruText.body,
                fontSize: 12,
                height: 1.4,
                color: EbruColors.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: const TextStyle(
                fontFamily: EbruText.body,
                fontSize: 14,
                color: EbruColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: SettingsService.defaultServerUrl,
                errorText: _hataMetni,
              ),
            ),
            const SizedBox(height: 12),
            GoldButton(
              label: _kaydediliyor ? 'Bağlanıyor…' : 'Kaydet ve bağlan',
              icon: Icons.link,
              onPressed: _kaydediliyor ? null : _kaydet,
            ),
            const SizedBox(height: 10),
            OutlineButton(
              label: 'Otomatik adrese dön',
              onPressed: _kaydediliyor
                  ? null
                  : () async {
                      await viewModel.resetServerUrl();
                      if (context.mounted) {
                        setState(
                          () => _controller.text = viewModel.serverUrl,
                        );
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}

/// Hesap silme onay penceresi.
///
/// Şifreyle açılmış hesap şifresini, Google ile açılmış hesap kullanıcı
/// adını yazıyor: Google hesaplarının kullanılabilir bir şifresi yok.
/// Hangisi olduğunu sunucu `/auth/me` ile bildiriyor.
class _HesapSilPenceresi extends StatefulWidget {
  final EbruViewModel viewModel;

  const _HesapSilPenceresi({required this.viewModel});

  @override
  State<_HesapSilPenceresi> createState() => _HesapSilPenceresiState();
}

class _HesapSilPenceresiState extends State<_HesapSilPenceresi> {
  final TextEditingController _onay = TextEditingController();
  String? _hata;
  bool _siliniyor = false;

  bool get _sifreli => widget.viewModel.sifresiVar;

  @override
  void dispose() {
    _onay.dispose();
    super.dispose();
  }

  /// Son onay: "Hesabınız silinecektir, onaylıyor musunuz?"
  ///
  /// Kimlik alanı doldurulduktan SONRA soruluyor. Geri dönüşü olmayan
  /// bir işlemde tek dokunuş yeterli olmamalı.
  Future<bool> _sonOnay() async {
    final ad = widget.viewModel.username;
    final cevap = await showDialog<bool>(
      context: context,
      builder: (onayContext) => AlertDialog(
        backgroundColor: EbruColors.surfaceHigh,
        icon: const Icon(Icons.warning_amber_rounded,
            color: EbruColors.error, size: 32),
        title: Text('Emin misiniz?', style: EbruText.headlineSmall),
        content: Text(
          ad.isEmpty
              ? 'Hesabınız ve size ait bütün veriler kalıcı olarak '
                  'silinecektir. Bu işlem geri alınamaz. Onaylıyor musunuz?'
              : '$ad hesabınız ve size ait bütün veriler kalıcı olarak '
                  'silinecektir. Bu işlem geri alınamaz. Onaylıyor musunuz?',
          style: EbruText.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(onayContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(onayContext, true),
            child: const Text(
              'Evet, sil',
              style: TextStyle(color: EbruColors.error),
            ),
          ),
        ],
      ),
    );
    return cevap ?? false;
  }

  Future<void> _sil() async {
    if (_onay.text.trim().isEmpty) {
      setState(() {
        _hata = _sifreli ? 'Şifrenizi yazın.' : 'Kullanıcı adınızı yazın.';
      });
      return;
    }

    if (!await _sonOnay()) return;
    if (!mounted) return;

    setState(() {
      _hata = null;
      _siliniyor = true;
    });

    try {
      await widget.viewModel.hesabimiSil(
        sifre: _sifreli ? _onay.text : null,
        onay: _sifreli ? null : _onay.text.trim(),
      );
      if (!mounted) return;
      // Oturum kapandı; AuthGate giriş ekranına dönüyor. Pencere de
      // onunla birlikte kapanmalı, yoksa boş ekranın üstünde kalır.
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = e.toString().replaceFirst('ApiException: ', '');
        _siliniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: EbruColors.surfaceHigh,
      title: Text('Hesabımı sil', style: EbruText.headlineSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hesabınız, adınız, e-posta adresiniz ve üretim sayaçlarınız '
            'sunucudan kalıcı olarak silinir. Bu işlem geri alınamaz.\n\n'
            'Telefonunuza kaydedilen eserler sizde kalır.',
            style: EbruText.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _onay,
            obscureText: _sifreli,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_siliniyor,
            style: const TextStyle(
              fontFamily: EbruText.body,
              fontSize: 14,
              color: EbruColors.onSurface,
            ),
            decoration: InputDecoration(
              labelText: _sifreli ? 'Şifreniz' : 'Kullanıcı adınız',
              hintText: _sifreli ? null : widget.viewModel.username,
              errorText: _hata,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _sifreli
                ? 'Hesabın sahibi olduğunuzu doğrulamak için şifrenizi yazın.'
                : 'Google ile açılmış hesapların şifresi yok. Onaylamak '
                    'için kullanıcı adınızı yazın.',
            style: EbruText.labelSmall.copyWith(
              color: EbruColors.outline,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _siliniyor ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: _siliniyor ? null : _sil,
          child: _siliniyor
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EbruColors.error,
                  ),
                )
              : const Text(
                  'Kalıcı olarak sil',
                  style: TextStyle(color: EbruColors.error),
                ),
        ),
      ],
    );
  }
}

class _DurumKarti extends StatelessWidget {
  final bool hazir;
  final String mesaj;
  final bool yenileniyor;
  final VoidCallback onYenile;

  const _DurumKarti({
    required this.hazir,
    required this.mesaj,
    required this.yenileniyor,
    required this.onYenile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EbruColors.surfaceLow,
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        border: Border.all(
          color: hazir
              ? EbruColors.mint.withValues(alpha: 0.4)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hazir ? Icons.check_circle : Icons.cloud_off,
            color: hazir ? EbruColors.mint : EbruColors.error,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hazir ? 'Üretim için hazır' : 'Şu anda üretim yapılamıyor',
                  style: EbruText.bodyLarge.copyWith(fontSize: 15),
                ),
                if (mesaj.isNotEmpty)
                  Text(
                    mesaj,
                    style: EbruText.labelSmall.copyWith(
                      color: EbruColors.outline,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: yenileniyor
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: EbruColors.gold,
                    ),
                  )
                : const Icon(Icons.refresh, size: 20),
            onPressed: yenileniyor ? null : onYenile,
          ),
        ],
      ),
    );
  }
}

class _Sayac extends StatelessWidget {
  final String deger;
  final String etiket;

  const _Sayac({required this.deger, required this.etiket});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: EbruColors.surfaceLow,
          borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        ),
        child: Column(
          children: [
            Text(
              deger,
              style: EbruText.displayLarge.copyWith(
                fontSize: 28,
                color: EbruColors.gold,
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
