import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_radius.dart';

/// ============================================================
/// APP THEME — Pacific Dating App (Light / Dark).
/// ============================================================
///
///  - Light is the default.
///  - The choice is stored on the device (shared_preferences) and restored
///    automatically.
///  - AppTheme is a ChangeNotifier: changing it re-themes the whole app
///    instantly (via ListenableBuilder in main.dart).
///
/// Every Material component is themed HERE with the shared rounded design
/// system (AppRadius) — screens should never fight the theme with their own
/// square/boxy shapes. Build the ThemeData once with [theme()].
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme instance = AppTheme._();

  static const String _prefKey = 'app_theme_dark';
  static const Color seedColor = Color(0xFFFF4B72);

  bool _isDark = false;

  bool get isDark => _isDark;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDark = prefs.getBool(_prefKey) ?? false;
    } catch (_) {
      _isDark = false;
    }
  }

  Future<void> setDark(bool dark) async {
    if (_isDark == dark) return;
    _isDark = dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, dark);
    } catch (_) {
      // Persistence failed — theme stays until the app is reopened.
    }
  }

  Future<void> toggle() => setDark(!_isDark);

  /// The full app ThemeData — used by main.dart for BOTH light and dark
  /// mode (it reads [isDark]). Everything is rounded via AppRadius.
  ThemeData theme() {
    final brightness = _isDark ? Brightness.dark : Brightness.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      splashFactory: InkSparkle.splashFactory,

      // FONT: Poppins — used by ALL screens by default.
      textTheme: GoogleFonts.poppinsTextTheme(
        brightness == Brightness.dark
            ? ThemeData(brightness: Brightness.dark).textTheme
            : ThemeData(brightness: Brightness.light).textTheme,
      ),

      // ---- CARDS ----
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF23252B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        clipBehavior: Clip.antiAlias,
      ),

      // ---- DIALOGS ----
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF23252B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : const Color(0xFF1F2937),
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: isDark ? Colors.white70 : const Color(0xFF374151),
        ),
      ),

      // ---- BOTTOM SHEETS ----
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
      ),

      // ---- INPUT FIELDS ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF23252B) : const Color(0xFFF3F4F6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: colorScheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
      ),

      // ---- BUTTONS ----
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
          side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
        ),
      ),

      // ---- CHIPS ----
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sm),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF374151),
        ),
      ),

      // ---- FLOATING ACTION BUTTON ----
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),

      // ---- POPUP MENUS ----
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xFF23252B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),

      // ---- TAB BAR ----
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
      ),

      // ---- TOOLTIP ----
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? Colors.white : const Color(0xFF1F2937),
          borderRadius: AppRadius.sm,
        ),
        textStyle: TextStyle(
          fontSize: 12,
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
        ),
      ),

      // ---- SNACKBAR fallback (the app normally uses the overlay
      //      notification widget — see AppNotificationOverlay) ----
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sm),
      ),

      // ---- LISTS ----
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),

      // ---- APP BAR ----
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF16171A)
            : const Color(0xFFF9FAFB),
        foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
      ),
    );
  }
}
