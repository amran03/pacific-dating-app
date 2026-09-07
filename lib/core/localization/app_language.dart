import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mfumo rahisi wa lugha mbili (English + Swahili) kwa Pacific Dating App.
///
///  - ENGLISH ndiyo lugha kuu (default).
///  - Mtumiaji anaweza kubadilisha kuwa Swahili — chaguo lake linahifadhiwa
///    ndani ya device (shared_preferences) na kurudishwa kiotomatiki.
///
/// Matumizi (usage):
///   AppLanguage.instance.t('Create Account', sw: 'Fungua Akaunti')
///
/// Muundo huu wa "English text as key + optional sw translation" unaleta
/// faida mbili: (1) code inasomeka — kila sehemu inaonyesha maandishi
/// halisi, (2) screen mpya inaweza kupata lugha mbili kwa mstari mmoja.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final AppLanguage instance = AppLanguage._();

  static const String _prefKey = 'app_language';

  String _code = 'en';

  /// 'en' au 'sw'
  String get code => _code;

  bool get isSwahili => _code == 'sw';

  /// Jina la lugha inayoonekana kwenye toggle.
  String get label => isSwahili ? 'Swahili' : 'English';

  /// Inasoma lugha iliyohifadhiwa — inaitwa mara moja kwenye main().
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_prefKey);
      if (saved == 'sw' || saved == 'en') {
        _code = saved!;
      }
    } catch (_) {
      // Kama storage imeshindikana, tunabaki na English default.
      _code = 'en';
    }
  }

  /// Kubadilisha lugha — inaahidi (persist) na ku-notify screens zote.
  Future<void> setEnglish() => _set('en');

  Future<void> setSwahili() => _set('sw');

  Future<void> _set(String code) async {
    if (_code == code) return;
    _code = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {
      // Persistence ikishindikana, lugha inabaki mpaka app ifungwe tena.
    }
  }

  /// Tafsiri: English ni default; Swahili inatumika ikiwa imechaguliwa na
  /// tafsiri ipo.
  String t(String english, {String? sw}) {
    if (isSwahili && sw != null && sw.trim().isNotEmpty) {
      return sw;
    }
    return english;
  }
}