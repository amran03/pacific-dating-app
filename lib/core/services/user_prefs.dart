import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cache ya mapendeleo ya mtumiaji (Profile > Settings).
///
/// Kwa nini cache? Kila keystroke kwenye chat inaangalia
/// `typing_indicator_enabled`, na kila heartbeat ya presence inaangalia
/// `show_online_status_enabled` — kusoma DB kila mara kungeleta lag.
/// Hivyo: tunasoma MARA MOJA mtumiaji akiingia, kisha tunasasisha
/// mara moja tu switch inapobadilishwa.
class UserPrefs {
  UserPrefs._internal();
  static final UserPrefs instance = UserPrefs._internal();

  static SupabaseClient get _client => Supabase.instance.client;

  String? _uid;

  // Defaults: kila kitu kimewashwa (privacy-friendly).
  bool _readReceipts = true;
  bool _typingIndicator = true;
  bool _showOnlineStatus = true;
  bool _discoverable = true;
  bool _locationEnabled = false;
  bool _notificationsEnabled = true;
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;
  bool _loaded = false;

  bool get readReceiptsEnabled => _readReceipts;
  bool get typingIndicatorEnabled => _typingIndicator;
  bool get showOnlineStatusEnabled => _showOnlineStatus;
  bool get discoverable => _discoverable;
  bool get locationEnabled => _locationEnabled;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get isLoaded => _loaded;

  /// Inasoma mapendeleo kutoka DB. Inaitwa mara moja tu to kila uid.
  Future<void> load(String uid, {bool force = false}) async {
    if (!force && _uid == uid && _loaded) return;
    _uid = uid;
    try {
      final row = await _client
          .from('users')
          .select(
            'read_receipts_enabled, typing_indicator_enabled, '
            'show_online_status_enabled, discoverable, '
            'location_enabled, notifications_enabled, '
            'vibration_enabled, sound_enabled',
          )
          .eq('uid', uid)
          .maybeSingle();

      if (row != null) {
        _readReceipts = row['read_receipts_enabled'] != false;
        _typingIndicator = row['typing_indicator_enabled'] != false;
        _showOnlineStatus = row['show_online_status_enabled'] != false;
        _discoverable = row['discoverable'] != false;
        _locationEnabled = row['location_enabled'] == true;
        _notificationsEnabled = row['notifications_enabled'] != false;
        _vibrationEnabled = row['vibration_enabled'] != false;
        _soundEnabled = row['sound_enabled'] != false;
      }
      _loaded = true;
    } catch (e) {
      debugPrint('UserPrefs load failed: $e');
    }
  }

  /// Inasasisha preference moja papo hapo (cache) + kuandika DB nyuma.
  /// `column` ni jina la column halisi kwenye `users` table.
  Future<void> set(String column, bool value) async {
    // 1) Cache ya papo hapo — UI inabadilika BILA kusubiri network.
    switch (column) {
      case 'read_receipts_enabled':
        _readReceipts = value;
        break;
      case 'typing_indicator_enabled':
        _typingIndicator = value;
        break;
      case 'show_online_status_enabled':
        _showOnlineStatus = value;
        break;
      case 'discoverable':
        _discoverable = value;
        break;
      case 'location_enabled':
        _locationEnabled = value;
        break;
      case 'notifications_enabled':
        _notificationsEnabled = value;
        break;
      case 'vibration_enabled':
        _vibrationEnabled = value;
        break;
      case 'sound_enabled':
        _soundEnabled = value;
        break;
    }

    // 2) Andika DB.
    final uid = _uid ?? _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client.from('users').update({
      column: value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('uid', uid);
  }

  void clear() {
    _uid = null;
    _loaded = false;
    _readReceipts = true;
    _typingIndicator = true;
    _showOnlineStatus = true;
    _discoverable = true;
    _locationEnabled = false;
    _notificationsEnabled = true;
  }
}