// lib/core/theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Theme mode provider — persisted via SharedPreferences
// ---------------------------------------------------------------------------
const _kThemeKey = 'theme_mode';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Kick off async load; state starts as system default
    _loadSaved();
    return ThemeMode.system;
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeKey);
    if (saved != null) {
      state = _fromString(saved);
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, _toString(mode));
  }

  static ThemeMode _fromString(String s) => switch (s) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String _toString(ThemeMode m) => switch (m) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    _ => 'system',
  };
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class AppTheme {
  AppTheme._();

  static const Color _primary = Color(0xFF5C4BF5);
  static const Color _primaryDark = Color(0xFF7B6CF8);
  static const Color _surfaceLight = Color(0xFFF6F5FF);
  static const Color _surfaceDark = Color(0xFF0F0E17);
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _cardDark = Color(0xFF1C1B2E);

  static ThemeData get light {
    final cs =
        ColorScheme.fromSeed(
          seedColor: _primary,
          brightness: Brightness.light,
          surface: _surfaceLight,
        ).copyWith(
          primary: _primary,
          onPrimary: Colors.white,
          surfaceContainerLow: _cardLight,
          surfaceContainerHighest: const Color(0xFFECEAFF),
        );
    return _build(cs);
  }

  static ThemeData get dark {
    final cs =
        ColorScheme.fromSeed(
          seedColor: _primaryDark,
          brightness: Brightness.dark,
          surface: _surfaceDark,
        ).copyWith(
          primary: _primaryDark,
          onPrimary: Colors.white,
          surfaceContainerLow: _cardDark,
          surfaceContainerHighest: const Color(0xFF252338),
        );
    return _build(cs);
  }

  static ThemeData _build(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final base = ThemeData(brightness: cs.brightness);
    final bodyTheme = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = bodyTheme.copyWith(
      displayLarge: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.displayLarge,
        fontWeight: FontWeight.w800,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.displayMedium,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.displaySmall,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.headlineLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.titleLarge,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.plusJakartaSans(
        textStyle: bodyTheme.titleSmall,
        fontWeight: FontWeight.w600,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: textTheme,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: cs.onSurface),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 2 : 3,
        surfaceTintColor: cs.primary,
        shadowColor: _primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 8,
        shape: const StadiumBorder(),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        backgroundColor: cs.surfaceContainerLow,
        dragHandleColor: cs.onSurface.withValues(alpha: 0.2),
        dragHandleSize: const Size(40, 4),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: cs.primary.withValues(alpha: 0.15),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: cs.surfaceContainerLow,
        elevation: 24,
      ),
      dividerTheme: DividerThemeData(
        color: cs.onSurface.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
