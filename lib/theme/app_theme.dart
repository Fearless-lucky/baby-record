import 'package:flutter/material.dart';

/// 应用调色板：温暖、克制、高级的纸感配色。
class AppPalette extends ThemeExtension<AppPalette> {
  final Color scaffold;
  final Color card;
  final Color ink;
  final Color subInk;
  final Color accent;
  final Color accentSoft;
  final Color line;
  final Color favorite;

  const AppPalette({
    required this.scaffold,
    required this.card,
    required this.ink,
    required this.subInk,
    required this.accent,
    required this.accentSoft,
    required this.line,
    required this.favorite,
  });

  static const light = AppPalette(
    scaffold: Color(0xFFF7F4EF),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF211D18),
    subInk: Color(0xFF8A8177),
    accent: Color(0xFFA96B45),
    accentSoft: Color(0xFFF1E4D8),
    line: Color(0xFFE9E2D8),
    favorite: Color(0xFFC15B4E),
  );

  static const dark = AppPalette(
    scaffold: Color(0xFF14110E),
    card: Color(0xFF1F1B17),
    ink: Color(0xFFEFEAE2),
    subInk: Color(0xFF9B9188),
    accent: Color(0xFFD2906A),
    accentSoft: Color(0xFF342720),
    line: Color(0xFF2E2823),
    favorite: Color(0xFFD4756A),
  );

  @override
  AppPalette copyWith({
    Color? scaffold,
    Color? card,
    Color? ink,
    Color? subInk,
    Color? accent,
    Color? accentSoft,
    Color? line,
    Color? favorite,
  }) =>
      AppPalette(
        scaffold: scaffold ?? this.scaffold,
        card: card ?? this.card,
        ink: ink ?? this.ink,
        subInk: subInk ?? this.subInk,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        line: line ?? this.line,
        favorite: favorite ?? this.favorite,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      subInk: Color.lerp(subInk, other.subInk, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      line: Color.lerp(line, other.line, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
    );
  }
}

extension PaletteOf on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// 低饱和强调色方案：中性色不变，只替换强调色。
class AccentDef {
  final String name;
  final Color light;
  final Color lightSoft;
  final Color dark;
  final Color darkSoft;

  const AccentDef(this.name, this.light, this.lightSoft, this.dark,
      this.darkSoft);
}

const kAccents = [
  AccentDef('暖橘', Color(0xFFA96B45), Color(0xFFF1E4D8), Color(0xFFD2906A),
      Color(0xFF342720)),
  AccentDef('焦糖棕', Color(0xFF9C6B3D), Color(0xFFF0E4CF), Color(0xFFC8925A),
      Color(0xFF332A1D)),
  AccentDef('鼠尾草绿', Color(0xFF7D8B6C), Color(0xFFE6EADC),
      Color(0xFF9CAE88), Color(0xFF252B21)),
  AccentDef('雾霾蓝', Color(0xFF6F839B), Color(0xFFE1E7EF), Color(0xFF90A5BE),
      Color(0xFF222932)),
];

class AppTheme {
  AppTheme._();

  /// 展示用衬线字体族，营造杂志感；中文自动回退系统字体。
  static const displayFont = 'serif';

  static AppPalette _palette(Brightness brightness, int accentIndex) {
    final i = accentIndex.clamp(0, kAccents.length - 1);
    final a = kAccents[i];
    if (brightness == Brightness.light) {
      return AppPalette.light.copyWith(accent: a.light, accentSoft: a.lightSoft);
    }
    return AppPalette.dark.copyWith(accent: a.dark, accentSoft: a.darkSoft);
  }

  static TextTheme _textTheme(Color ink, Color subInk) => TextTheme(
        displayLarge: TextStyle(
            fontFamily: displayFont,
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: ink,
            height: 1.2),
        displaySmall: TextStyle(
            fontFamily: displayFont,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: ink,
            height: 1.25),
        headlineMedium: TextStyle(
            fontFamily: displayFont,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: ink,
            height: 1.3),
        titleLarge: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, color: ink, height: 1.35),
        titleMedium: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: ink, height: 1.35),
        bodyLarge: TextStyle(fontSize: 15.5, color: ink, height: 1.65),
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.55),
        bodySmall: TextStyle(fontSize: 12.5, color: subInk, height: 1.45),
        labelLarge: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: ink),
        labelSmall: TextStyle(fontSize: 11.5, color: subInk, letterSpacing: 0.4),
      );

  static ThemeData light([int accentIndex = 0]) {
    final p = _palette(Brightness.light, accentIndex);
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: p.accent,
      onPrimary: Colors.white,
      secondary: p.accent,
      onSecondary: Colors.white,
      error: const Color(0xFFB6473C),
      onError: Colors.white,
      surface: p.card,
      onSurface: p.ink,
      onSurfaceVariant: p.subInk,
      outline: p.line,
      outlineVariant: const Color(0xFFF0EAE1),
      surfaceContainerHighest: const Color(0xFFF1EDE6),
      shadow: Colors.transparent,
    );
    return _base(scheme, p);
  }

  static ThemeData dark([int accentIndex = 0]) {
    final p = _palette(Brightness.dark, accentIndex);
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: p.accent,
      onPrimary: const Color(0xFF261811),
      secondary: p.accent,
      onSecondary: const Color(0xFF261811),
      error: const Color(0xFFD4756A),
      onError: const Color(0xFF2A1210),
      surface: p.card,
      onSurface: p.ink,
      onSurfaceVariant: p.subInk,
      outline: p.line,
      outlineVariant: const Color(0xFF292420),
      surfaceContainerHighest: const Color(0xFF2A2520),
      shadow: Colors.transparent,
    );
    return _base(scheme, p);
  }

  static ThemeData _base(ColorScheme scheme, AppPalette p) {
    final text = _textTheme(p.ink, p.subInk);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.scaffold,
      textTheme: text,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle:
            text.headlineMedium?.copyWith(fontSize: 20),
        iconTheme: IconThemeData(color: p.ink),
      ),
      cardTheme: CardTheme(
        color: p.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.line),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.card,
        selectedItemColor: p.accent,
        unselectedItemColor: p.subInk,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        selectedColor: p.accentSoft,
        disabledColor: p.card,
        side: BorderSide(color: p.line),
        labelStyle: text.bodySmall!.copyWith(color: p.ink),
        secondaryLabelStyle: text.bodySmall!.copyWith(color: p.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: text.bodyMedium!.copyWith(color: p.subInk),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.scaffold),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
