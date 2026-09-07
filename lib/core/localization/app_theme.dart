import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mfumo wa THEME (Light / Dark) za Pacific Dating App.
///
///  - Light ndiyo kuu (default).
///  - Chaguo linahifadhiwa ndani ya device (shared_preferences) na
///    kurudishwa kiotomatiki.
///  - AppTheme ni ChangeNotifier: chaguo lake linabadilika theme ya app
///    NZIMA papo hapo (kupitia ListenableBuilder kwenye main.dart).
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme instance = AppTheme._();

  static const String _prefKey = 'app_theme_dark';

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
      // Persistence ikishindikana, theme inabaki mpaka app ifungwe tena.
    }
  }

  Future<void> toggle() => setDark(!_isDark);

  /// ThemeData dinazoguswa kwenye main.dart — sakabili na set colors ya app.
  ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF4B72),
      ),
    );
  }
}