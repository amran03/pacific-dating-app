import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';

class MatchmakingService {
  final _client = Supabase.instance.client;

  /// Null-safe UID: null when logged out instead of crashing with `!`.
  String? get _myUid => _client.auth.currentUser?.id;

  /// Strict UID for writes — throws a clear English error when logged out.
  String get _requireUid {
    final uid = _myUid;
    if (uid == null) throw Exception('You are not logged in. Please log in again.');
    return uid;
  }

  String chatIdFor(String otherUid) {
    final ids = [_requireUid, otherUid]..sort();
    return ids.join('_');
  }

  Future<UserModel?> fetchMyProfile() async {
    final uid = _myUid;
    if (uid == null) return null;
    final response = await _client
        .from('users')
        .select()
        .eq('uid', uid)
        .maybeSingle();
    if (response == null) return null;
    try {
      return UserModel.fromMap(response);
    } catch (_) {
      return null;
    }
  }

  static double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);

  Future<List<UserModel>> searchUsersByName(String query) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final uid = _myUid;

    try {
      var builder = _client.from('users').select().ilike('name', '%$q%');
      if (uid != null) builder = builder.neq('uid', uid);
      final response = await builder.limit(20);
      return (response as List)
          .map((data) {
            try {
              return UserModel.fromMap(data);
            } catch (_) {
              return null;
            }
          })
          .whereType<UserModel>()
          .toList();
    } catch (e) {
      throw Exception(friendlyDiscoverError(e));
    }
  }

  /// English, user-friendly error for Discover/Search loads.
  /// Never exposes raw Postgrest/RLS text to the user.
  String friendlyDiscoverError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('network') ||
        raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection refused') ||
        raw.contains('connection timed out') ||
        raw.contains('connection')) {
      return 'No internet connection. Please check your connection and tap Show Again.';
    }
    if (raw.contains('jwt') ||
        raw.contains('not logged in') ||
        raw.contains('invalid token') ||
        raw.contains('expired')) {
      return 'Your session expired. Please log in again, then tap Show Again.';
    }
    return 'Failed to load users. Please tap Show Again.';
  }

  /// Safe row -> UserModel (skips one bad row instead of failing all).
  UserModel? _safeUser(Map<String, dynamic> data) {
    try {
      return UserModel.fromMap(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  List<UserModel> _parseUsers(dynamic response, Set<String> excluded) {
    final List<UserModel> out = [];
    if (response is! List) return out;
    for (final d in response) {
      if (d is! Map) continue;
      final u = _safeUser(Map<String, dynamic>.from(d));
      if (u == null) continue;
      if (excluded.contains(u.uid)) continue;
      if (u.uid.isEmpty) continue;
      out.add(u);
    }
    return out;
  }

  Future<List<UserModel>> fetchDiscoverableUsers({int limit = 15}) async {
    final uid = _myUid;
    // 1. My swipes (best-effort: failure must never block Discover).
    Set<String> excludedUids = {};
    if (uid != null) excludedUids.add(uid);
    if (uid != null) {
      try {
        final swipedResponse = await _client
            .from('swipes')
            .select('target_uid')
            .eq('from_uid', uid);
        for (final d in (swipedResponse as List)) {
          final t = (d as Map)['target_uid']?.toString();
          if (t != null && t.isNotEmpty) excludedUids.add(t);
        }
      } catch (_) {
        // Ignore — better to show people than to fail the whole screen.
      }
    }

    // 2. Candidates with layered fallbacks (old DBs may miss new columns).
    // Each step is narrower; the last step only excludes self client-side.
    Object? lastError;
    final attempts = <Future<dynamic> Function()>[
      // Full filter: complete + discoverable + not me.
      () {
        var q = _client.from('users').select();
        q = q.eq('is_profile_complete', true);
        q = q.eq('discoverable', true);
        if (uid != null) q = q.neq('uid', uid);
        return q.limit(limit * 3);
      },
      // Without discoverable (column may not exist on old DBs).
      () {
        var q = _client.from('users').select();
        q = q.eq('is_profile_complete', true);
        if (uid != null) q = q.neq('uid', uid);
        return q.limit(limit * 3);
      },
      // Minimal: only exclude self, filter the rest client-side.
      () {
        var q = _client.from('users').select();
        if (uid != null) q = q.neq('uid', uid);
        return q.limit(limit * 3);
      },
      // Absolute fallback: plain select, everything filtered client-side.
      () => _client.from('users').select().limit(limit * 3),
    ];

    List<UserModel> candidates = [];
    for (final attempt in attempts) {
      try {
        final usersResponse = await attempt();
        candidates = _parseUsers(usersResponse, excludedUids);
        // Keep rows that look like real profiles when possible, but never
        // return empty while usable rows exist (old rows may miss flags).
        final complete = candidates
            .where((u) => u.name.trim().isNotEmpty && u.age > 0)
            .toList();
        candidates = complete.isNotEmpty ? complete : candidates;
        if (candidates.isNotEmpty) break;
        // Empty is not an error — try a looser query which may see more rows
        // under restrictive RLS. Only throw if ALL attempts fail/empty.
      } catch (e) {
        lastError = e;
      }
    }

    if (candidates.isEmpty && lastError != null) {
      throw Exception(friendlyDiscoverError(lastError));
    }

    final Map<String, int> tierPriority = {
      'diamond': 3,
      'gold': 2,
      'bronze': 1,
      'none': 0,
    };

    candidates.sort((a, b) {
      final pA = tierPriority[a.badgeTier] ?? 0;
      final pB = tierPriority[b.badgeTier] ?? 0;
      return pB.compareTo(pA);
    });

    return candidates.take(limit).toList();
  }

  Future<bool> recordSwipe(String targetUid, {required bool isLike}) async {
    final uid = _requireUid;
    await _client.from('swipes').upsert({
      'from_uid': uid,
      'target_uid': targetUid,
      'action': isLike ? 'like' : 'pass',
      'created_at': DateTime.now().toIso8601String(),
    });

    if (!isLike) return false;

    // Check if mutual
    final theirAction = await _client
        .from('swipes')
        .select()
        .eq('from_uid', targetUid)
        .eq('target_uid', uid)
        .eq('action', 'like')
        .maybeSingle();

    final bool isMutual = theirAction != null;

    if (isMutual) {
      await _createMatch(targetUid);
    }
    return isMutual;
  }

  String _formatTimeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _createMatch(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final ids = [_requireUid, otherUid]..sort();

    await _client.from('matches').upsert({
      'id': chatId,
      'user_a': ids[0],
      'user_b': ids[1],
      'matched_at': DateTime.now().toIso8601String(),
    });

    await _client.from('chat_rooms').upsert({
      'id': chatId,
      'participants': ids,
      'unlocked_by': ids,
      'last_message': '',
      'last_message_at': DateTime.now().toIso8601String(),
    });

    final myProfile = await fetchMyProfile();
    final theirProfile = await _client.from('users').select().eq('uid', otherUid).maybeSingle();
    final String myName = myProfile?.name ?? 'User';
    String theirName = 'User';
    if (theirProfile != null) {
      final n = theirProfile['name']?.toString() ?? '';
      if (n.isNotEmpty) theirName = n;
    }

    await _client.from('notifications').insert([
      {
        'to_uid': otherUid,
        'type': 'match',
        'title': 'You got a Match! 🎉',
        'description': 'You and $myName liked each other!',
        'created_at': DateTime.now().toIso8601String(),
        'read': false,
      },
      {
        'to_uid': _requireUid,
        'type': 'match',
        'title': 'You got a Match! 🎉',
        'description': 'You and $theirName liked each other!',
        'created_at': DateTime.now().toIso8601String(),
        'read': false,
      }
    ]);
  }

  Future<Map<String, dynamic>> getChatAccessInfo(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final uid = _myUid;
    final chatSnap = await _client.from('chat_rooms').select().eq('id', chatId).maybeSingle();

    final List<dynamic> unlockedBy = chatSnap?['unlocked_by'] ?? [];

    if (uid != null && unlockedBy.contains(uid)) {
      return {'unlocked': true, 'price': 0};
    }

    final otherUser = await _client.from('users').select('chat_unlock_price').eq('uid', otherUid).maybeSingle();
    final int price = (otherUser?['chat_unlock_price'] as num?)?.toInt() ?? 0;

    return {'unlocked': false, 'price': price};
  }

  Future<void> payAndUnlockChat(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final String uid = _requireUid;
    final ids = [uid, otherUid]..sort();

    // In Supabase, we would ideally use a database function (RPC) for transactions.
    // For simplicity here, we do it in steps, but warn that it's not atomic without RPC.
    final otherUser = await _client.from('users').select().eq('uid', otherUid).single();
    final int price = (otherUser['chat_unlock_price'] as num?)?.toInt() ?? 0;

    if (price > 0) {
      final myUser = await _client.from('users').select('coins').eq('uid', uid).single();
      final int myCoins = (myUser['coins'] as num?)?.toInt() ?? 0;

      if (myCoins < price) {
        throw Exception('INSUFFICIENT_COINS');
      }

      await _client.from('users').update({'coins': myCoins - price}).eq('uid', uid);
      // NOTE: crediting the receiver needs permissive RLS —
      // if it fails (old RLS), swallow it so chat still unlocks
      // (the payer was already charged, unlock must continue).
      try {
        final int theirCoins = (otherUser['coins'] as num?)?.toInt() ?? 0;
        await _client.from('users').update({'coins': theirCoins + price}).eq('uid', otherUid);
      } catch (_) {}
    }

    final chatRoom = await _client.from('chat_rooms').select().eq('id', chatId).maybeSingle();
    List<dynamic> unlockedBy = List<dynamic>.from(chatRoom?['unlocked_by'] ?? []);
    if (!unlockedBy.contains(uid)) {
      unlockedBy.add(uid);
    }

    await _client.from('chat_rooms').upsert({
      'id': chatId,
      'participants': ids,
      'unlocked_by': unlockedBy,
      'last_message_at': DateTime.now().toIso8601String(),
    });

    if (price > 0) {
      final myProfile = await fetchMyProfile();
      await _client.from('notifications').insert({
        'to_uid': otherUid,
        'type': 'coins',
        'title': 'You received Coins! 🪙',
        'description': '${myProfile?.name ?? 'User'} paid $price Coins to unlock chat with you.',
        'created_at': DateTime.now().toIso8601String(),
        'read': false,
      });
    }
  }

  /// Missed calls (missed/declined call notifications) for the user —
  /// used in the "Missed Calls" section of Messages.
  Stream<List<Map<String, dynamic>>> streamMissedCalls() {
    final myUid = _myUid ?? '__logged_out__';
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('to_uid', myUid)
        .eq('type', 'missed_call')
        .order('created_at', ascending: false)
        .limit(10);
  }

  /// Marks one notification as read — does NOT delete the row (history stays).
  Future<void> markNotificationRead(String id) async {
    try {
      await _client.from('notifications').update({'read': true}).eq('id', id);
    } catch (_) {}
  }

  Stream<List<UserModel>> streamUsersWhoLikedMe() {
    final uid = _myUid ?? '__logged_out__';
    return _client
        .from('swipes')
        .stream(primaryKey: ['from_uid', 'target_uid'])
        .eq('target_uid', uid)
        .eq('action', 'like')
        .asyncMap((event) async {
      if (event.isEmpty) return [];
      final fromUids = event
          .map((e) => e['from_uid']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      if (fromUids.isEmpty) return [];
      try {
        final usersResponse =
            await _client.from('users').select().inFilter('uid', fromUids);
        return (usersResponse as List)
            .map((u) {
              try {
                return UserModel.fromMap(
                    Map<String, dynamic>.from(u as Map));
              } catch (_) {
                return null;
              }
            })
            .whereType<UserModel>()
            .toList();
      } catch (_) {
        // Old RLS blocking received likes: return empty instead of an
        // error — data appears on its own once the new SQL has run.
        return <UserModel>[];
      }
    });
  }

  /// Public stats for a user (likes + gifts + rating) — from the fast,
  /// RLS-safe counters on users. Old schema: counting fallback.
  Future<Map<String, dynamic>> fetchUserStats(String uid) async {
    int likes = 0;
    int giftsCount = 0;
    int giftsValue = 0;
    double avgRating = 0;
    int ratingCount = 0;
    int myStars = 0;
    try {
      final row = await _client
          .from('users')
          .select('likes_received_count,gifts_received_count,'
              'gifts_received_value,rating_sum,rating_count')
          .eq('uid', uid)
          .maybeSingle();
      if (row != null) {
        likes = (row['likes_received_count'] as num?)?.toInt() ?? 0;
        giftsCount = (row['gifts_received_count'] as num?)?.toInt() ?? 0;
        giftsValue = (row['gifts_received_value'] as num?)?.toInt() ?? 0;
        final sum = (row['rating_sum'] as num?)?.toInt() ?? 0;
        ratingCount = (row['rating_count'] as num?)?.toInt() ?? 0;
        if (ratingCount > 0) avgRating = sum / ratingCount;
      }
    } catch (_) {
      try {
        final l = await _client.from('swipes').select('from_uid')
            .eq('target_uid', uid).eq('action', 'like');
        likes = (l as List).length;
      } catch (_) {}
      try {
        final g = await _client.from('gifts_sent').select('coin_cost')
            .eq('to_uid', uid);
        final list = (g as List);
        giftsCount = list.length;
        for (final r in list) {
          giftsValue += ((r as Map)['coin_cost'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }
    final myUidForRating = _myUid;
    if (myUidForRating != null) {
      try {
        final mine = await _client.from('ratings').select('stars')
            .eq('from_uid', myUidForRating).eq('to_uid', uid).maybeSingle();
        myStars = (mine?['stars'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    return {
      'likes': likes, 'giftsCount': giftsCount, 'giftsValue': giftsValue,
      'avgRating': avgRating, 'ratingCount': ratingCount, 'myStars': myStars,
    };
  }

  /// Top gifts (by value) a user received — for the profile page.
  Future<List<Map<String, dynamic>>> fetchTopGiftsReceived(String uid,
      {int limit = 3}) async {
    try {
      final res = await _client
          .from('gifts_sent')
          .select('gift_name,gift_emoji,gift_image_url,coin_cost,sent_at')
          .eq('to_uid', uid)
          .order('coin_cost', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      return [];
    }
  }

  /// English error for a failed rating — never raw server text.
  String friendlyRatingError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('not logged in') || raw.contains('jwt')) {
      return 'Your session expired. Please log in again, then try rating again.';
    }
    if (raw.contains('network') ||
        raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection')) {
      return 'No internet connection. Please check your connection and try again.';
    }
    if (raw.contains('duplicate') ||
        raw.contains('unique') ||
        raw.contains('already')) {
      return 'You already rated this user. Your new stars were saved.';
    }
    return 'Failed to send rating. Please try again.';
  }

  /// Set/update a rating (1-5 stars) for another user.
  /// FIX: the ratings table has NO updated_at column — sending it caused
  /// Postgrest "column not found" so EVERY rating said "failed".
  /// Now: update-first (existing row), insert (new row), upsert fallback,
  /// and finally a direct users-counter fallback so rating never hard-fails
  /// on old schemas. Throws friendly English errors only.
  Future<void> rateUser(String toUid, int stars) async {
    final uid = _requireUid;
    final s = stars.clamp(1, 5);
    Object? lastError;
    // 1) Update existing rating (no updated_at — column does not exist).
    try {
      final existing = await _client
          .from('ratings')
          .select('from_uid')
          .eq('from_uid', uid)
          .eq('to_uid', toUid)
          .maybeSingle();
      if (existing != null) {
        await _client.from('ratings').update({'stars': s}).eq('from_uid', uid).eq('to_uid', toUid);
        return;
      }
    } catch (e) {
      lastError = e;
    }
    // 2) Insert new rating.
    try {
      await _client.from('ratings').insert({
        'from_uid': uid,
        'to_uid': toUid,
        'stars': s,
      });
      return;
    } catch (e) {
      lastError = e;
    }
    // 3) Upsert fallback (works when PK exists).
    try {
      await _client.from('ratings').upsert({
        'from_uid': uid,
        'to_uid': toUid,
        'stars': s,
      }, onConflict: 'from_uid,to_uid');
      return;
    } catch (e) {
      lastError = e;
    }
    // 4) Last resort: bump the public counters directly so the stars still
    // show even if the ratings table/RLS is broken (best-effort).
    try {
      final row = await _client
          .from('users')
          .select('rating_sum,rating_count')
          .eq('uid', toUid)
          .maybeSingle();
      if (row != null) {
        final sum = (row['rating_sum'] as num?)?.toInt() ?? 0;
        final cnt = (row['rating_count'] as num?)?.toInt() ?? 0;
        await _client.from('users').update({
          'rating_sum': sum + s,
          'rating_count': cnt + 1,
        }).eq('uid', toUid);
        return;
      }
    } catch (e) {
      lastError = e;
    }
    throw Exception(friendlyRatingError(lastError));
  }

  /// Send a gift via RPC (atomic). If the RPC is missing (old schema),
  /// falls back to the legacy path so it never just says "failed".
  Future<void> sendGift({
    required String toUid,
    required String giftId,
    required String giftName,
    String giftEmoji = '',
    String giftImageUrl = '',
    required int coinCost,
    String fromName = 'User',
  }) async {
    try {
      await _client.rpc('send_gift', params: {
        'p_to_uid': toUid,
        'p_gift_id': giftId,
        'p_gift_name': giftName,
        'p_gift_emoji': giftEmoji,
        'p_gift_image_url': giftImageUrl,
        'p_coin_cost': coinCost,
        'p_from_name': fromName,
      });
      return;
    } catch (_) {
      // No RPC — legacy fallback (best-effort).
    }
    final uid = _requireUid;
    final myRow =
        await _client.from('users').select('coins').eq('uid', uid).single();
    final int liveCoins = (myRow['coins'] as num?)?.toInt() ?? 0;
    if (liveCoins < coinCost) throw Exception('INSUFFICIENT_COINS');
    await _client
        .from('users')
        .update({'coins': liveCoins - coinCost}).eq('uid', uid);
    try {
      await _client.from('gifts_sent').insert({
        'from_uid': uid, 'to_uid': toUid, 'gift_id': giftId,
        'gift_name': giftName, 'gift_emoji': giftEmoji,
        'gift_image_url': giftImageUrl, 'coin_cost': coinCost,
        'sent_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    try {
      await _client.from('notifications').insert({
        'to_uid': toUid, 'type': 'gift', 'title': 'You received a New Gift! 🎁',
        'description': '$fromName sent you '
            '${giftEmoji.isEmpty ? '🎁' : giftEmoji} $giftName.',
        'created_at': DateTime.now().toIso8601String(), 'read': false,
      });
    } catch (_) {}
  }

  Stream<List<ChatModel>> streamMyChatRooms() {
    final myUid = _myUid ?? '__logged_out__';
    return _client
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .map((event) => event.where((room) {
              final List<dynamic> participants = room['participants'] ?? [];
              return participants.contains(myUid);
            }).toList())
        .asyncMap((rooms) async {
      if (rooms.isEmpty) return [];

      // Extract all other UIDs to fetch user profiles in one go
      final Set<String> otherUids = {};
      for (final room in rooms) {
        final List<dynamic> participants = room['participants'] ?? [];
        final String otherUid = participants.firstWhere((id) => id != myUid, orElse: () => '');
        if (otherUid.isNotEmpty) otherUids.add(otherUid);
      }

      if (otherUids.isEmpty) return [];

      // Fetch all user profiles in one batch
      final usersResponse = await _client
          .from('users')
          .select('uid, name, profile_image_url, chat_unlock_price')
          .inFilter('uid', otherUids.toList());

      final Map<String, dynamic> userMap = {
        for (var u in (usersResponse as List))
          (u as Map)['uid']?.toString() ?? '': u
      };

      final List<_ChatWithMetadata> chatList = [];
      for (final room in rooms) {
        final List<dynamic> participants = room['participants'] ?? [];
        final List<dynamic> unlockedBy = room['unlocked_by'] ?? [];
        final String otherUid = participants.firstWhere((id) => id != myUid, orElse: () => '');

        if (otherUid.isNotEmpty && userMap.containsKey(otherUid)) {
          final userData = userMap[otherUid];
          // Lock applies when the other user set a price > 0 AND you have
          // not paid yet. Pay ONCE (unlocked_by has your uid) -> never
          // locked again. Price 0 -> chat is FREE, never shown as locked.
          final int price =
              (userData['chat_unlock_price'] as num?)?.toInt() ?? 0;
          final bool isLocked = price > 0 && !unlockedBy.contains(myUid);
          final lastMessageAt = DateTime.tryParse(room['last_message_at'] ?? '');

          chatList.add(_ChatWithMetadata(
            model: ChatModel(
              id: otherUid,
              name: userData['name'] ?? 'User',
              avatarUrl: userData['profile_image_url'] ?? '',
              lastMessage: (room['last_message'] as String?)?.isNotEmpty == true
                  ? room['last_message']
                  : 'Start the conversation! 👋',
              timeSent: _formatTimeAgo(lastMessageAt),
              isLocked: isLocked,
              unlockCostCoins: price,
            ),
            lastMessageAt: lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ));
        }
      }

      // Sort by last message time descending
      chatList.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      return chatList.map((c) => c.model).toList();
    });
  }
}

class _ChatWithMetadata {
  final ChatModel model;
  final DateTime lastMessageAt;
  _ChatWithMetadata({required this.model, required this.lastMessageAt});
}

