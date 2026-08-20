import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'widgets/ebru_widgets.dart';

/// E-posta onayı bekleyen hesaba gösterilen ekran.
///
/// Onaylanmamış hesap üretim yapamıyor. Kullanıcıyı doğrudan üretim
/// ekranına almak, bütün seçimleri yaptırıp en sonda reddetmek
/// olurdu; bunun yerine ne yapması gerektiği burada söyleniyor.
class DogrulamaView extends StatefulWidget {
  const DogrulamaView({super.key});

  @override
  State<DogrulamaView> createState() => _DogrulamaViewState();
}

class _DogrulamaViewState extends State<DogrulamaView> {
  bool _calisiyor = false;
  String? _bilgi;
  String? _hata;

  Future<void> _tekrarGonder() async {
    setState(() {
      _calisiyor = true;
      _bilgi = null;
      _hata = null;
    });
    try {
      final mesaj = await context.read<EbruViewModel>().dogrulamaGonder();
      if (mounted) setState(() => _bilgi = mesaj);
    } on ApiException catch (e) {
      if (mounted) setState(() => _hata = e.message);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  /// Kullanıcı bağlantıya tıkladıktan sonra buraya dönüp "onayladım"
  /// diyor; sunucuya tekrar sorup durumu tazeliyoruz.
  Future<void> _durumuYenile() async {
    setState(() {
      _calisiyor = true;
      _hata = null;
    });
    final viewModel = context.read<EbruViewModel>();
    await viewModel.validateSession();
    if (!mounted) return;
    setState(() {
      _calisiyor = false;
      if (!viewModel.epostaOnayli) {
        _hata = 'Onay henüz görünmüyor. Bağlantıya tıkladığınızdan emin olun.';
      }
    });
    // Onaylandıysa AuthGate kendiliğinden uygulamaya geçiyor.
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();

    return Scaffold(
      backgroundColor: EbruColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 64,
                  color: EbruColors.gold,
                ),
                const SizedBox(height: 20),
                Text(
                  'E-postanızı onaylayın',
                  textAlign: TextAlign.center,
                  style: EbruText.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  viewModel.eposta == null
                      ? 'Hesabınıza bağlı e-posta adresine bir bağlantı '
                          'gönderdik. Üretime başlamak için o bağlantıya tıklayın.'
                      : '${viewModel.eposta} adresine bir bağlantı gönderdik. '
                          'Üretime başlamak için o bağlantıya tıklayın.',
                  textAlign: TextAlign.center,
                  style: EbruText.bodyMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Posta birkaç dakika içinde gelmezse gereksiz (spam) '
                  'klasörünüze bakın.',
                  textAlign: TextAlign.center,
                  style:
                      EbruText.labelSmall.copyWith(color: EbruColors.outline),
                ),

                if (_bilgi != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: EbruColors.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: EbruColors.gold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(_bilgi!, style: EbruText.labelSmall),
                  ),
                ],

                if (_hata != null) ...[
                  const SizedBox(height: 16),
                  ErrorBox(message: _hata!),
                ],

                const SizedBox(height: 28),
                if (_calisiyor)
                  const Center(
                    child: CircularProgressIndicator(color: EbruColors.gold),
                  )
                else ...[
                  GoldButton(
                    label: 'Onayladım, devam et',
                    icon: Icons.refresh,
                    onPressed: _durumuYenile,
                  ),
                  const SizedBox(height: 12),
                  OutlineButton(
                    label: 'Bağlantıyı yeniden gönder',
                    icon: Icons.send_outlined,
                    onPressed: _tekrarGonder,
                  ),
                ],

                const SizedBox(height: 18),
                TextButton(
                  onPressed: _calisiyor
                      ? null
                      : () => context.read<EbruViewModel>().logout(),
                  child: Text(
                    'Çıkış yap',
                    style: EbruText.labelSmall
                        .copyWith(color: EbruColors.outline),
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
