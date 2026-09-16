import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// English-only language holder (kept for compatibility).
///
/// The app used to support English + Swahili via `t(english, sw: ...)`.
/// It is now ENGLISH ONLY: [t] always returns the English text and the
/// language toggle was removed. This class stays so old imports/listeners
/// keep compiling without touching every screen.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final AppLanguage instance = AppLanguage._();

  static const String _prefKey = 'app_language';

  String _code = 'en';

  /// Always 'en'.
  String get code => _code;

  bool get isSwahili => false;

  /// Visible label (always English now).
  String get label => 'English';

  /// Reads saved language — always normalizes to English.
  Future<void> load() async {
    _code = 'en';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, 'en');
    } catch (_) {}
  }

  /// Kept for compatibility — stays English.
  Future<void> setEnglish() async {
    if (_code != 'en') {
      _code = 'en';
      notifyListeners();
    }
  }

  /// Kept for compatibility — Swahili is disabled, stays English.
  Future<void> setSwahili() async {
    await setEnglish();
  }

  /// English only: always returns [english].
  String t(String english, {String? sw}) => english;
}
