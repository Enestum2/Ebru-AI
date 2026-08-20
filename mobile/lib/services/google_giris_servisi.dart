import 'package:google_sign_in/google_sign_in.dart';

/// Google ile girişin uygulama tarafı.
///
/// Tek işi Google'dan bir **kimlik belirteci** almak. Belirtecin
/// doğrulanması sunucuda yapılıyor; burada hiçbir güvenlik kararı
/// verilmiyor.
///
/// NEDEN serverClientId
/// --------------------
/// Android'de uygulamanın kendi OAuth istemcisi var (paket adı + imza
/// parmak izi ile tanınıyor), ama sunucuya gidecek belirtecin alıcısı
/// (`aud`) WEB istemci kimliği olmalı. `serverClientId` tam olarak bunu
/// söylüyor. Bu sayede sunucudaki doğrulama hem site hem uygulama için
/// aynı kalıyor; sunucuda uygulamaya özel bir dal yok.
///
/// İstemci kimliği koda gömülmüyor, sunucudan okunuyor
/// (`/auth/google/durum`). Değişmesi gerekirse yeni APK çıkarmak
/// yerine sunucudaki ayarı değiştirmek yetiyor.
class GoogleGirisServisi {
  bool _hazir = false;
  String? _sunucuIstemciKimligi;

  /// Google'ı verilen web istemci kimliğiyle hazırlar.
  ///
  /// Aynı kimlikle ikinci kez çağrılırsa hiçbir şey yapmıyor;
  /// `initialize` yalnızca bir kez çağrılmalı.
  Future<void> hazirla(String sunucuIstemciKimligi) async {
    if (_hazir && _sunucuIstemciKimligi == sunucuIstemciKimligi) return;

    await GoogleSignIn.instance.initialize(
      serverClientId: sunucuIstemciKimligi,
    );
    _sunucuIstemciKimligi = sunucuIstemciKimligi;
    _hazir = true;
  }

  /// Google hesabı seçtirir ve kimlik belirtecini döner.
  ///
  /// Kullanıcı vazgeçerse null dönüyor — bu bir hata değil, bilerek
  /// yapılan bir seçim; çağıran taraf hata kutusu göstermemeli.
  Future<String?> belirtecAl() async {
    if (!_hazir) {
      throw StateError('Google girişi hazırlanmadan çağrıldı');
    }

    final GoogleSignInAccount hesap;
    try {
      hesap = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // Kullanıcı pencereyi kapattıysa sessizce dönülüyor.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    return hesap.authentication.idToken;
  }

  /// Uygulamadan çıkışta Google oturumunu da bırakıyoruz; yoksa
  /// bir sonraki girişte hesap seçme ekranı hiç çıkmıyor ve başka
  /// hesapla giriş yapmak imkânsız oluyor.
  Future<void> cikis() async {
    if (!_hazir) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google tarafındaki hata uygulamadan çıkışı engellememeli.
    }
  }
}
