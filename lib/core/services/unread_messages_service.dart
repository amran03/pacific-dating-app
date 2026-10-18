import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Huduma MOJA ya "ujumbe usiosomwa" (unread) kwa app yote.
///
/// Kabla ya huduma hii, hesabu zilirudiwa mara 1+1+1:
///   - ChatListScreen ilifungua stream yake yenye filter (receiver_id +
///     seen=false) na kuhesabu kwa chat_id,
///   - _ChatTabIcon kwenye dashboard ilifungua stream NyingINE ile ile
///     kila build (subscription mpya kila sekunde — leak + flicker),
///   - IndividualChatScreen ilikuwa na njia MBILI za kuandika seen.
/// Service hii (2+3=5) hushirikisha VITU VYOTE:
///   - UN subscription realtime MOJA (app lifetime) kwa chat list na
///     badge ya icon ya Chat,
///   - `openChat()` inafuta count YA CHAT HIYO PPO HAPO (optimistic)
///     kabla ya kuandika DB — badge inatoweka papo hapo mtumiaji
///     anapofungua ujumbe, hata kama realtime itachelewa au itapotea,
///   - `refresh()` (one-shot DB read) kama fallback ya kudakia ukweli.
class UnreadMessagesService {
  UnreadMessagesService._();
  static final UnreadMessagesService instance = UnreadMessagesService._();

  final SupabaseClient _client = Supabase.instance.client;

  final StreamController<Map<String, int>> _countsController =
      StreamController<Map<String, int>>.broadcast();

  /// Stream ya hesabu kwa chat_id — ina emit mara idadi inapobadilika.
  Stream<Map<String, int>> get countsStream => _countsController.stream;

  Map<String, int> _counts = const <String, int>{};
  Map<String, int> get counts => _counts;

  /// Jumla ya ujumbe usiosomwa (kwa badge ya icon ya Chat dashboard).
  int get totalUnread => _counts.values.fold(0, (sum, n) => sum + n);

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<AuthState>? _authSub;
  String? _subscribedUid;
  bool _started = false;

  /// chat_id kati ya mimi na [otherUid] — lazima iendane na inayotengenezwa
  /// IndividualChatScreen (uids zimepangwa kisha zimeunganishwa '_').
  static String chatIdWith(String otherUid) {
    final myUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    return ([myUid, otherUid]..sort()).join('_');
  }

  /// Idadi ya ujumbe usiosomwa wa chat na [otherUid].
  int unreadFor(String otherUid) => _counts[chatIdWith(otherUid)] ?? 0;

  /// Anza kusikiliza (salama kuitwa mara nyingi). Inasajili listener ya
  /// auth ili subscription irejee na mtumiaji mpya baada ya login/logout.
  void start() {
    if (_started) return;
    _started = true;

    _authSub = _client.auth.onAuthStateChange.listen((state) {
      final String? uid = _client.auth.currentUser?.id;
      if (state.event == AuthChangeEvent.signedOut) {
        _unsubscribe();
        _setCounts(const <String, int>{});
      } else if (uid != null && uid.isNotEmpty && uid != _subscribedUid) {
        _subscribe(uid);
      }
    });

    final String? uid = _client.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) _subscribe(uid);
  }

  void _subscribe(String uid) {
    _unsubscribe();
    _subscribedUid = uid;
    _sub = _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', uid)
        .eq('seen', false)
        .listen((rows) {
      final Map<String, int> counts = <String, int>{};
      for (final row in rows) {
        final String chatId = row['chat_id']?.toString() ?? '';
        if (chatId.isEmpty) continue;
        counts[chatId] = (counts[chatId] ?? 0) + 1;
      }
      _setCounts(counts);
    }, onError: (Object e) {
      debugPrint('Unread stream error: $e');
    });
  }

  void _unsubscribe() {
    _sub?.cancel();
    _sub = null;
    _subscribedUid = null;
  }

  void _setCounts(Map<String, int> next) {
    _counts = next;
    if (!_countsController.isClosed) _countsController.add(next);
  }


  /// Mtumiaji amefungua chat na [otherUid]:
  ///  1. count ya chat hii inafutwa PPO HAPO (badge = 0 bila kusubiri
  ///     DB/realtime — ndio hitaji la "badge ijifute mtumiaji akifungua
  ///     ujumbe"),
  ///  2. seen=true + seen_at huandikwa DB (fallback kwa DB za zamani),
  ///  3. refresh() inathibitisha hesabu na ukweli wa DB (fire-and-forget).
  Future<void> openChat(String otherUid) async {
    final String chatId = chatIdWith(otherUid);
    if (_counts.containsKey(chatId)) {
      final updated = Map<String, int>.from(_counts)..remove(chatId);
      _setCounts(updated);
    }
    await markChatSeen(otherUid);
    unawaited(refresh());
  }

  /// Andika seen=true kwa messages zote zisizosomwa za chat na [otherUid].
  /// (Haitoi count local — UI ya kufungua chat inaita [openChat].)
  Future<void> markChatSeen(String otherUid) async {
    final String? myUid = _client.auth.currentUser?.id;
    final String chatId = chatIdWith(otherUid);
    if (myUid == null || myUid.isEmpty) return;

    try {
      await _client
          .from('messages')
          .update({
        'seen': true,
        // Tarehe kamili ya kusoma — kwa historia + read receipts.
        'seen_at': DateTime.now().toIso8601String(),
      })
          .eq('chat_id', chatId)
          .eq('receiver_id', myUid)
          .eq('seen', false);
    } catch (e) {
      // FALLBACK (DB za zamani bila column ya seen_at): seen bado
      // LAZIMA iandikwe — vinginevyo badge ya unread haiondoki kamwe.
      debugPrint('markChatSeen (with seen_at) failed, retrying: $e');
      try {
        await _client
            .from('messages')
            .update({'seen': true})
            .eq('chat_id', chatId)
            .eq('receiver_id', myUid)
            .eq('seen', false);
      } catch (e2) {
        debugPrint('markChatSeen failed: $e2');
      }
    }
  }

  /// Weka seen=true kwa messages kwa id (read-receipt flush kutoka chat
  /// screen — ujumbe wa mwenzake unaokutana screen tayari).
  Future<void> markMessagesSeenByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _client
          .from('messages')
          .update({
        'seen': true,
        'seen_at': DateTime.now().toIso8601String(),
      })
          .inFilter('id', ids);
    } catch (_) {
      // FALLBACK (DB za zamani bila seen_at).
      try {
        await _client
            .from('messages')
            .update({'seen': true})
            .inFilter('id', ids);
      } catch (e2) {
        debugPrint('markMessagesSeenByIds failed: $e2');
      }
    }
  }

  /// Sasisha hesabu kutoka DB (one-shot). Fallback pale realtime inapokosea
  /// — pia inaitwa mara moja baada ya [openChat] kuhakikisha ukweli wa DB
  /// unaakisiwa.
  Future<void> refresh() async {
    final String? myUid = _client.auth.currentUser?.id;
    if (myUid == null || myUid.isEmpty) return;
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('messages')
          .select('chat_id')
          .eq('receiver_id', myUid)
          .eq('seen', false)
          .limit(500);
      final Map<String, int> counts = <String, int>{};
      for (final row in rows) {
        final String chatId = row['chat_id']?.toString() ?? '';
        if (chatId.isEmpty) continue;
        counts[chatId] = (counts[chatId] ?? 0) + 1;
      }
      _setCounts(counts);
    } catch (e) {
      debugPrint('Unread refresh failed: $e');
    }
  }

  void dispose() {
    _unsubscribe();
    _authSub?.cancel();
    _countsController.close();
    _started = false;
  }
}
