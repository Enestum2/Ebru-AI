import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'create_view.dart';
import 'discover_view.dart';
import 'gallery_view.dart';
import 'settings_view.dart';

/// Tasarımdaki dört sekmeli gezinme kabuğu.
/// Önceden galeri ve ayarlar üstteki ikonlardan açılıyordu.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();

  /// Başka bir ekrandan sekme değiştirmek için.
  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _seciliSekme = 1; // varsayılan: Oluştur

  static const List<Widget> _ekranlar = [
    DiscoverView(),
    CreateView(),
    GalleryView(),
    SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<EbruViewModel>();
      // Uygulama kapatılırken yarım kalmış bir üretim varsa devam ettir.
      viewModel.resumePendingJob();
      // Android 13+ bildirim izni: üretim bitince haber verebilmek için.
      viewModel.bildirimIzniIste();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama arka plandan dönünce sunucu durumu değişmiş olabilir;
    // kullanıcı bayat bir "bağlanılamadı" uyarısıyla karşılaşmasın.
    final viewModel = context.read<EbruViewModel>();
    viewModel.setArkaPlanda(state != AppLifecycleState.resumed);

    if (state == AppLifecycleState.resumed) {
      viewModel.refreshServerStatus();
      viewModel.resumePendingJob();
      viewModel.bildirimleriTemizle();
    }
  }

  void sekmeyeGit(int index) {
    setState(() => _seciliSekme = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _seciliSekme,
        children: _ekranlar,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: EbruColors.surfaceLowest,
          border: Border(
            top: BorderSide(color: Colors.white10, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _Sekme(
                  icon: Icons.explore_outlined,
                  aktifIcon: Icons.explore,
                  label: 'Keşfet',
                  secili: _seciliSekme == 0,
                  onTap: () => sekmeyeGit(0),
                ),
                _Sekme(
                  icon: Icons.auto_awesome_outlined,
                  aktifIcon: Icons.auto_awesome,
                  label: 'Oluştur',
                  secili: _seciliSekme == 1,
                  onTap: () => sekmeyeGit(1),
                ),
                _Sekme(
                  icon: Icons.collections_outlined,
                  aktifIcon: Icons.collections,
                  label: 'Galerim',
                  secili: _seciliSekme == 2,
                  onTap: () => sekmeyeGit(2),
                ),
                _Sekme(
                  icon: Icons.settings_outlined,
                  aktifIcon: Icons.settings,
                  label: 'Ayarlar',
                  secili: _seciliSekme == 3,
                  onTap: () => sekmeyeGit(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sekme extends StatelessWidget {
  final IconData icon;
  final IconData aktifIcon;
  final String label;
  final bool secili;
  final VoidCallback onTap;

  const _Sekme({
    required this.icon,
    required this.aktifIcon,
    required this.label,
    required this.secili,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final renk = secili ? EbruColors.gold : EbruColors.outline;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(secili ? aktifIcon : icon, size: 22, color: renk),
            const SizedBox(height: 4),
            Text(
              label,
              style: EbruText.labelSmall.copyWith(
                color: renk,
                fontWeight: secili ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
