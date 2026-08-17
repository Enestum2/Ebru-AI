import 'package:flutter/material.dart';

/// Stitch'te hazırlanan "modern Türk" tasarımının renk ve tipografi
/// değerleri. Değerler tasarımın Tailwind yapılandırmasından birebir
/// alındı; elle uydurulmuş renk yok.
class EbruColors {
  EbruColors._();

  /// Sayfa zemini — en koyu yüzey.
  static const Color background = Color(0xFF101418);

  /// Gece mavisi ana yüzey.
  static const Color surface = Color(0xFF00142C);

  // Yüzey katmanları (açıldıkça yükselen hiyerarşi).
  static const Color surfaceLowest = Color(0xFF000E23);
  static const Color surfaceLow = Color(0xFF011C3A);
  static const Color surfaceContainer = Color(0xFF05203E);
  static const Color surfaceHigh = Color(0xFF122B49);
  static const Color surfaceVariant = Color(0xFF1E3654);
  static const Color surfaceBright = Color(0xFF233A59);

  /// Altın vurgu — seçili durumlar ve birincil eylem.
  static const Color gold = Color(0xFFC7A65A);

  /// Fildişi — başlıklar ve yüksek vurgulu metin.
  static const Color offWhite = Color(0xFFF4F0E8);

  /// Nane yeşili — onay ve "duvar kağıdı yap" eylemi.
  static const Color mint = Color(0xFF89D5C1);
  static const Color mintBright = Color(0xFFA5F1DD);

  static const Color onSurface = Color(0xFFD4E3FF);
  static const Color onSurfaceVariant = Color(0xFFC5C6CA);
  static const Color outline = Color(0xFF8F9194);
  static const Color outlineVariant = Color(0xFF44474A);

  static const Color error = Color(0xFFFFB4AB);
  static const Color neutral = Color(0xFFC3C7CC);
  static const Color secondary = Color(0xFFC9C6BF);
}

/// Tasarımdaki yazı stilleri. Playfair Display başlıklarda,
/// Inter gövde ve etiketlerde kullanılıyor.
class EbruText {
  EbruText._();

  static const String display = 'PlayfairDisplay';
  static const String body = 'Inter';

  static const TextStyle displayLarge = TextStyle(
    fontFamily: display,
    fontSize: 40,
    height: 48 / 40,
    fontWeight: FontWeight.w700,
    color: EbruColors.offWhite,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: display,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
    color: EbruColors.onSurface,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: display,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w500,
    color: EbruColors.offWhite,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: body,
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w400,
    color: EbruColors.onSurface,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: body,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: EbruColors.onSurfaceVariant,
  );

  /// Bölüm başlıkları: büyük harf, geniş harf aralığı.
  static const TextStyle labelMedium = TextStyle(
    fontFamily: body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05 * 14,
    color: EbruColors.onSurface,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: body,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: EbruColors.onSurface,
  );
}

/// Tasarımın köşe yarıçapları ve boşluk ölçeği.
class EbruShape {
  EbruShape._();

  static const double radiusSm = 4;
  static const double radiusLg = 8;
  static const double radiusXl = 12;
  static const double radiusFull = 9999;

  static const double spaceXs = 4;
  static const double spaceBase = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 24;
  static const double spaceLg = 48;
}

ThemeData buildEbruTheme() {
  const scheme = ColorScheme.dark(
    primary: EbruColors.gold,
    onPrimary: EbruColors.surface,
    secondary: EbruColors.mint,
    onSecondary: EbruColors.surface,
    surface: EbruColors.background,
    onSurface: EbruColors.onSurface,
    error: EbruColors.error,
    onError: EbruColors.surface,
    outline: EbruColors.outline,
    outlineVariant: EbruColors.outlineVariant,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: EbruColors.background,
    fontFamily: EbruText.body,
    textTheme: const TextTheme(
      displayLarge: EbruText.displayLarge,
      headlineMedium: EbruText.headlineMedium,
      headlineSmall: EbruText.headlineSmall,
      bodyLarge: EbruText.bodyLarge,
      bodyMedium: EbruText.bodyMedium,
      labelMedium: EbruText.labelMedium,
      labelSmall: EbruText.labelSmall,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: EbruColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: EbruText.headlineSmall,
      iconTheme: IconThemeData(color: EbruColors.offWhite),
    ),
    dividerTheme: const DividerThemeData(
      color: EbruColors.outlineVariant,
      thickness: 0.5,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: EbruColors.gold,
      inactiveTrackColor: EbruColors.surfaceVariant,
      thumbColor: EbruColors.gold,
      overlayColor: Color(0x33C7A65A),
      trackHeight: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EbruColors.surfaceLow,
      hintStyle: const TextStyle(
        fontFamily: EbruText.body,
        fontSize: 14,
        color: EbruColors.outline,
      ),
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EbruShape.radiusXl),
        borderSide: const BorderSide(color: EbruColors.gold),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: EbruColors.surfaceHigh,
      contentTextStyle: TextStyle(
        fontFamily: EbruText.body,
        color: EbruColors.onSurface,
      ),
    ),
  );
}
