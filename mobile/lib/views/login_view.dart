import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/ebru_viewmodel.dart';
import 'widgets/ebru_widgets.dart';

/// Ekranın hangi işi yaptığı.
///
/// Üç durum tek ekranda: ayrı ekranlar aynı alanları ve aynı hata
/// kutusunu tekrar etmekten başka bir şey yapmayacaktı.
enum _Kip {
  giris,
  kayit,

  /// Google ile ilk kez gelen kişi kullanıcı adı seçiyor.
  googleKullaniciAdi,
}

/// Giriş, kayıt ve Google ile giriş ekranı.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _kullaniciAdi = TextEditingController();
  final _sifre = TextEditingController();
  final _ad = TextEditingController();
  final _soyad = TextEditingController();
  final _eposta = TextEditingController();

  _Kip _kip = _Kip.giris;
  bool _calisiyor = false;
  bool _sifreGizli = true;
  String? _hata;

  /// Google'dan alınan kimlik belirteci. Kullanıcı adı seçildikten
  /// sonra ikinci istekte tekrar gönderiliyor ve sunucuda yeniden
  /// doğrulanıyor; böylece sunucuda "bekleyen kayıt" tutulmuyor.
  String? _googleBelirteci;
  String? _googleEposta;

  @override
  void initState() {
    super.initState();
    // Google düğmesi yalnızca sunucu "açık" derse gösteriliyor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EbruViewModel>().googleHazirla();
    });
  }

  @override
  void dispose() {
    _kullaniciAdi.dispose();
    _sifre.dispose();
    _ad.dispose();
    _soyad.dispose();
    _eposta.dispose();
    super.dispose();
  }

  bool get _kayitKipi => _kip == _Kip.kayit;

  void _kipDegistir(_Kip yeni) {
    setState(() {
      _kip = yeni;
      _hata = null;
    });
  }

  // ---------------------------------------------------------------
  // Şifreyle giriş / kayıt
  // ---------------------------------------------------------------
  Future<void> _gonder() async {
    final ad = _kullaniciAdi.text.trim();
    final sifre = _sifre.text;

    if (ad.isEmpty || sifre.isEmpty) {
      setState(() => _hata = 'Kullanıcı adı ve şifre gerekli');
      return;
    }

    if (_kayitKipi) {
      if (_ad.text.trim().isEmpty ||
          _soyad.text.trim().isEmpty ||
          _eposta.text.trim().isEmpty) {
        setState(() => _hata = 'Ad, soyad ve e-posta gerekli');
        return;
      }
    }

    await _calistir(() async {
      final viewModel = context.read<EbruViewModel>();
      if (_kayitKipi) {
        await viewModel.register(
          ad,
          sifre,
          ad: _ad.text.trim(),
          soyad: _soyad.text.trim(),
          epostaAdresi: _eposta.text.trim(),
        );
      } else {
        await viewModel.login(ad, sifre);
      }
      // Sonrasını AuthGate devralıyor: onaylanmamış hesap doğrulama
      // ekranına, onaylı hesap uygulamaya gidiyor.
    });
  }

  // ---------------------------------------------------------------
  // Google
  // ---------------------------------------------------------------
  Future<void> _googleIleGir() async {
    await _calistir(() async {
      final viewModel = context.read<EbruViewModel>();

      final belirtec = await viewModel.googleBelirtecAl();
      // Kullanıcı hesap seçme penceresini kapattı; bu bir hata değil.
      if (belirtec == null) return;

      final sonuc = await viewModel.googleGiris(belirtec);
      if (!sonuc.kullaniciAdiGerekiyor) return;

      if (!mounted) return;
      setState(() {
        _googleBelirteci = belirtec;
        _googleEposta = sonuc.eposta;
        _kullaniciAdi.text = sonuc.onerilenKullaniciAdi ?? '';
        _kip = _Kip.googleKullaniciAdi;
        _hata = null;
      });
    });
  }

  Future<void> _googleHesabiOlustur() async {
    final ad = _kullaniciAdi.text.trim();
    if (ad.isEmpty) {
      setState(() => _hata = 'Kullanıcı adı gerekli');
      return;
    }
    final belirtec = _googleBelirteci;
    if (belirtec == null) {
      setState(() {
        _hata = 'Google oturumu düştü, lütfen tekrar deneyin.';
        _kip = _Kip.giris;
      });
      return;
    }

    await _calistir(() async {
      await context.read<EbruViewModel>().googleKullaniciAdi(belirtec, ad);
    });
  }

  /// Ortak çalıştırma sarmalayıcısı: yükleniyor durumu ve hata kutusu.
  Future<void> _calistir(Future<void> Function() is_) async {
    setState(() {
      _calisiyor = true;
      _hata = null;
    });
    try {
      await is_();
    } on ApiException catch (e) {
      if (mounted) setState(() => _hata = e.message);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _calisiyor = false);
    }
  }

  /// Şifre sıfırlama sitede yapılıyor.
  ///
  /// Aynı akışı uygulama içinde tekrar yazmak yerine siteye
  /// yönlendiriliyor: sıfırlama zaten e-postadaki bağlantıyla, yani
  /// tarayıcıda tamamlanıyor.
  Future<void> _sifremiUnuttum() async {
    final adres = Uri.parse(
      '${context.read<EbruViewModel>().serverUrl}/giris',
    );
    if (!await launchUrl(adres, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        setState(() => _hata = 'Tarayıcı açılamadı: $adres');
      }
    }
  }

  // ---------------------------------------------------------------
  Widget _alan(
    TextEditingController denetleyici,
    String ipucu,
    IconData simge, {
    bool sonrakiAlan = true,
    TextInputType? tur,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: denetleyici,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: tur,
        textInputAction:
            sonrakiAlan ? TextInputAction.next : TextInputAction.done,
        style: const TextStyle(
          fontFamily: EbruText.body,
          fontSize: 15,
          color: EbruColors.onSurface,
        ),
        decoration: InputDecoration(
          hintText: ipucu,
          prefixIcon: Icon(simge, size: 20, color: EbruColors.outline),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EbruViewModel>();
    final googleAcik = viewModel.googleKullanilabilir;
    final adSecmeKipi = _kip == _Kip.googleKullaniciAdi;

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
                  switch (_kip) {
                    _Kip.giris => 'Giriş yap',
                    _Kip.kayit => 'Hesap oluştur',
                    _Kip.googleKullaniciAdi => 'Kullanıcı adı seç',
                  },
                  style: EbruText.headlineSmall,
                ),
                const SizedBox(height: 20),

                if (adSecmeKipi) ...[
                  Text(
                    '${_googleEposta ?? 'Google hesabınız'} ile giriş '
                    'yapıyorsunuz. Son bir adım kaldı.',
                    style: EbruText.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _alan(
                    _kullaniciAdi,
                    'Kullanıcı adı',
                    Icons.badge_outlined,
                    sonrakiAlan: false,
                  ),
                  Text(
                    '3-24 karakter; harf, rakam, nokta ve alt çizgi.',
                    style: EbruText.labelSmall
                        .copyWith(color: EbruColors.outline),
                  ),
                ] else ...[
                  if (_kayitKipi) ...[
                    _alan(_ad, 'Ad', Icons.person_outline),
                    _alan(_soyad, 'Soyad', Icons.person_outline),
                    _alan(
                      _eposta,
                      'E-posta',
                      Icons.mail_outline,
                      tur: TextInputType.emailAddress,
                    ),
                  ],
                  _alan(
                    _kullaniciAdi,
                    'Kullanıcı adı',
                    Icons.account_circle_outlined,
                  ),
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
                      'Kullanıcı adı 3-24, şifre en az 6 karakter. '
                      'Üretim için e-postanızı onaylamanız gerekiyor.',
                      style: EbruText.labelSmall
                          .copyWith(color: EbruColors.outline),
                    ),
                  ],
                ],

                if (_hata != null) ...[
                  const SizedBox(height: 16),
                  ErrorBox(message: _hata!),
                ],

                const SizedBox(height: 24),
                if (_calisiyor)
                  const Center(
                    child: CircularProgressIndicator(color: EbruColors.gold),
                  )
                else ...[
                  GoldButton(
                    label: switch (_kip) {
                      _Kip.giris => 'Giriş yap',
                      _Kip.kayit => 'Hesap oluştur',
                      _Kip.googleKullaniciAdi => 'Hesabı oluştur',
                    },
                    icon: switch (_kip) {
                      _Kip.giris => Icons.login,
                      _ => Icons.person_add,
                    },
                    onPressed:
                        adSecmeKipi ? _googleHesabiOlustur : _gonder,
                  ),

                  // Google düğmesi ad seçme ekranında gösterilmiyor:
                  // kişi zaten Google ile gelmiş durumda.
                  if (googleAcik && !adSecmeKipi) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: EbruColors.outline),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ya da',
                            style: EbruText.labelSmall
                                .copyWith(color: EbruColors.outline),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: EbruColors.outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlineButton(
                      label: 'Google ile devam et',
                      icon: Icons.g_mobiledata,
                      onPressed: _googleIleGir,
                    ),
                  ],
                ],

                const SizedBox(height: 18),
                if (adSecmeKipi)
                  TextButton(
                    onPressed: _calisiyor
                        ? null
                        : () => _kipDegistir(_Kip.giris),
                    child: Text(
                      'Vazgeç',
                      style: EbruText.labelSmall
                          .copyWith(color: EbruColors.gold),
                    ),
                  )
                else ...[
                  TextButton(
                    onPressed: _calisiyor
                        ? null
                        : () => _kipDegistir(
                              _kayitKipi ? _Kip.giris : _Kip.kayit,
                            ),
                    child: Text(
                      _kayitKipi
                          ? 'Zaten hesabınız var mı? Giriş yapın'
                          : 'Hesabınız yok mu? Kayıt olun',
                      style: EbruText.labelSmall
                          .copyWith(color: EbruColors.gold),
                    ),
                  ),
                  if (!_kayitKipi)
                    TextButton(
                      onPressed: _calisiyor ? null : _sifremiUnuttum,
                      child: Text(
                        'Şifremi unuttum',
                        style: EbruText.labelSmall
                            .copyWith(color: EbruColors.outline),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
