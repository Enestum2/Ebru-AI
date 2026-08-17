import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'widgets/ebru_widgets.dart';

/// Giriş ve kayıt ekranı.
///
/// Tek ekranda iki kip: kullanıcı "Hesabın yok mu?" bağlantısıyla
/// aralarında geçiş yapıyor. Ayrı bir kayıt ekranı, aynı üç alanı
/// tekrar etmekten başka bir şey yapmayacaktı.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _kullaniciAdi = TextEditingController();
  final _sifre = TextEditingController();

  bool _kayitKipi = false;
  bool _calisiyor = false;
  bool _sifreGizli = true;
  String? _hata;

  @override
  void dispose() {
    _kullaniciAdi.dispose();
    _sifre.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    final ad = _kullaniciAdi.text.trim();
    final sifre = _sifre.text;

    if (ad.isEmpty || sifre.isEmpty) {
      setState(() => _hata = 'Kullanıcı adı ve şifre gerekli');
      return;
    }

    setState(() {
      _calisiyor = true;
      _hata = null;
    });

    final viewModel = context.read<EbruViewModel>();

    try {
      if (_kayitKipi) {
        await viewModel.register(ad, sifre);
      } else {
        await viewModel.login(ad, sifre);
      }
      // Giriş başarılıysa AuthGate kendiliğinden uygulamaya geçiyor.
    } on ApiException catch (e) {
      if (mounted) setState(() => _hata = e.message);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbruColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'Ebru',
                  textAlign: TextAlign.center,
                  style: EbruText.displayLarge.copyWith(
                    fontSize: 46,
                    color: EbruColors.gold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Geleneksel Türk ebru sanatı,\nyapay zekâ ile',
                  textAlign: TextAlign.center,
                  style: EbruText.bodyMedium,
                ),
                const SizedBox(height: 44),

                Text(
                  _kayitKipi ? 'Hesap oluştur' : 'Giriş yap',
                  style: EbruText.headlineSmall,
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: _kullaniciAdi,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontFamily: EbruText.body,
                    fontSize: 15,
                    color: EbruColors.onSurface,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Kullanıcı adı',
                    prefixIcon: Icon(
                      Icons.person_outline,
                      size: 20,
                      color: EbruColors.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _sifre,
                  obscureText: _sifreGizli,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _calisiyor ? null : _gonder(),
                  style: const TextStyle(
                    fontFamily: EbruText.body,
                    fontSize: 15,
                    color: EbruColors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Şifre',
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: EbruColors.outline,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _sifreGizli
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: EbruColors.outline,
                      ),
                      onPressed: () =>
                          setState(() => _sifreGizli = !_sifreGizli),
                    ),
                  ),
                ),

                if (_kayitKipi) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Kullanıcı adı 3-24 karakter, şifre en az 6 karakter.',
                    style: EbruText.labelSmall.copyWith(
                      color: EbruColors.outline,
                    ),
                  ),
                ],

                if (_hata != null) ...[
                  const SizedBox(height: 16),
                  ErrorBox(message: _hata!),
                ],

                const SizedBox(height: 24),
                if (_calisiyor)
                  const Center(
                    child: CircularProgressIndicator(
                      color: EbruColors.gold,
                    ),
                  )
                else
                  GoldButton(
                    label: _kayitKipi ? 'Hesap oluştur' : 'Giriş yap',
                    icon: _kayitKipi ? Icons.person_add : Icons.login,
                    onPressed: _gonder,
                  ),

                const SizedBox(height: 18),
                TextButton(
                  onPressed: _calisiyor
                      ? null
                      : () => setState(() {
                            _kayitKipi = !_kayitKipi;
                            _hata = null;
                          }),
                  child: Text(
                    _kayitKipi
                        ? 'Zaten hesabın var mı? Giriş yap'
                        : 'Hesabın yok mu? Kayıt ol',
                    style: EbruText.labelSmall.copyWith(
                      color: EbruColors.gold,
                    ),
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
