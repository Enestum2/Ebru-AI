# R8, okhttp'nin isteğe bağlı bağımlılıklarını bulamayınca release
# derlemesini durduruyor. Bu sınıflar çalışma zamanında gerekmiyor
# (okhttp varsa kullanır, yoksa kendi yoluna devam eder), bu yüzden
# yalnızca uyarıları susturuyoruz.

-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn okhttp3.internal.platform.**

# Flutter'ın "deferred components" desteği Play Core kütüphanesine
# atıfta bulunuyor. Uygulama bu özelliği kullanmıyor ve kütüphane
# bağımlılıklarda yok, bu yüzden uyarılar susturuluyor.
-dontwarn com.google.android.play.core.**

# Flutter eklentilerinin yansıma (reflection) ile eriştiği sınıflar
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
