import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'app_shell.dart';
import 'dogrulama_view.dart';
import 'login_view.dart';

/// Oturum durumuna göre giriş ekranını ya da uygulamayı gösterir.
///
/// Açılışta kayıtlı oturumun sunucuda hâlâ geçerli olduğunu bir kez
/// doğruluyor; ağ hatasında kullanıcıyı dışarı atmıyor.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _kontrolEdildi = false;

  @override
  void initState() {
    super.initState();
    _oturumuKontrolEt();
  }

  Future<void> _oturumuKontrolEt() async {
    final viewModel = context.read<EbruViewModel>();
    if (viewModel.isLoggedIn) {
      await viewModel.validateSession();
    }
    if (mounted) setState(() => _kontrolEdildi = true);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();

    if (!_kontrolEdildi) {
      return const Scaffold(
        backgroundColor: EbruColors.background,
        body: Center(
          child: CircularProgressIndicator(color: EbruColors.gold),
        ),
      );
    }

    if (!viewModel.isLoggedIn) return const LoginView();

    // Oturum var ama e-posta onaylanmamış: üretim uçları bu hesabı
    // reddediyor. Uygulamaya alıp sonunda hata göstermek yerine ne
    // yapması gerektiğini anlatan ekrana götürüyoruz.
    if (!viewModel.epostaOnayli) return const DogrulamaView();

    return const AppShell();
  }
}
