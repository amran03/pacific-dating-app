import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';

class MatchmakingService {
  final _client = Supabase.instance.client;

  String get _myUid => _client.auth.currentUser!.id;

  String chatIdFor(String otherUid) {
    final ids = [_myUid, otherUid]..sort();
    return ids.join('_');
  }

  Future<UserModel?> fetchMyProfile() async {
    final response = await _client
        .from('users')
        .select()
        .eq('uid', _myUid)
        .maybeSingle();
    if (response == null) return null;
    return UserModel.fromMap(response);
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

    final response = await _client
        .from('users')
        .select()
        .ilike('name', '%$q%')
        .neq('uid', _myUid)
        .limit(20);

    return (response as List).map((data) => UserModel.fromMap(data)).toList();
  }

  Future<List<UserModel>> fetchDiscoverableUsers({int limit = 15}) async {
    // 1. Get all my swipes
    final swipedResponse = await _client
        .from('swipes')
        .select('target_uid')
        .eq('from_uid', _myUid);
    
    final List<String> excludedUids = (swipedResponse as List)
        .map((d) => d['target_uid'] as String)
        .toList();
    excludedUids.add(_myUid);

    // 2. Fetch users not in excluded list
    final usersResponse = await _client
        .from('users')
        .select()
        .eq('is_profile_complete', true)
        .not('uid', 'in', excludedUids)
        .limit(limit * 3);

    final List<UserModel> candidates = (usersResponse as List)
        .map((data) => UserModel.fromMap(data))
        .toList();

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
    await _client.from('swipes').upsert({
      'from_uid': _myUid,
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
        .eq('target_uid', _myUid)
        .eq('action', 'like')
        .maybeSingle();

    final bool isMutual = theirAction != null;

    if (isMutual) {
      await _createMatch(targetUid);
    }
    return isMutual;
  }

  Future<void> _createMatch(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final ids = [_myUid, otherUid]..sort();

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
    final String myName = myProfile?.name ?? 'Mtumiaji';
    final String theirName = theirProfile?['name'] ?? 'Mtumiaji';

    await _client.from('notifications').insert([
      {
        'to_uid': otherUid,
        'type': 'match',
        'title': 'Umepata Match! 🎉',
        'description': 'Wewe na $myName mmependana!',
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'to_uid': _myUid,
        'type': 'match',
        'title': 'Umepata Match! 🎉',
        'description': 'Wewe na $theirName mmependana!',
        'created_at': DateTime.now().toIso8601String(),
      }
    ]);
  }

  Future<Map<String, dynamic>> getChatAccessInfo(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final chatSnap = await _client.from('chat_rooms').select().eq('id', chatId).maybeSingle();

    final List<dynamic> unlockedBy = chatSnap?['unlocked_by'] ?? [];

    if (unlockedBy.contains(_myUid)) {
      return {'unlocked': true, 'price': 0};
    }

    final otherUser = await _client.from('users').select('chat_unlock_price').eq('uid', otherUid).maybeSingle();
    final int price = (otherUser?['chat_unlock_price'] ?? 0) as int;

    return {'unlocked': false, 'price': price};
  }

  Future<void> payAndUnlockChat(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final ids = [_myUid, otherUid]..sort();

    // In Supabase, we would ideally use a database function (RPC) for transactions.
    // For simplicity here, we do it in steps, but warn that it's not atomic without RPC.
    final otherUser = await _client.from('users').select().eq('uid', otherUid).single();
    final int price = (otherUser['chat_unlock_price'] ?? 0) as int;

    if (price > 0) {
      final myUser = await _client.from('users').select('coins').eq('uid', _myUid).single();
      final int myCoins = (myUser['coins'] ?? 0) as int;

      if (myCoins < price) {
        throw Exception('INSUFFICIENT_COINS');
      }

      await _client.from('users').update({'coins': myCoins - price}).eq('uid', _myUid);
      await _client.from('users').update({'coins': (otherUser['coins'] ?? 0) + price}).eq('uid', otherUid);
    }

    final chatRoom = await _client.from('chat_rooms').select().eq('id', chatId).maybeSingle();
    List<dynamic> unlockedBy = chatRoom?['unlocked_by'] ?? [];
    if (!unlockedBy.contains(_myUid)) {
      unlockedBy.add(_myUid);
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
        'title': 'Umepokea Coins! 🪙',
        'description': '${myProfile?.name ?? 'Mtumiaji'} amelipa $price Coins kufungua chat na wewe.',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Stream<List<UserModel>> streamUsersWhoLikedMe() {
    return _client
        .from('swipes')
        .stream(primaryKey: ['from_uid', 'target_uid'])
        .eq('target_uid', _myUid)
        .eq('action', 'like')
        .asyncMap((event) async {
      if (event.isEmpty) return [];
      final fromUids = event.map((e) => e['from_uid'] as String).toList();
      final usersResponse = await _client.from('users').select().in_('uid', fromUids);
      return (usersResponse as List).map((u) => UserModel.fromMap(u)).toList();
    });
  }

  Stream<List<ChatModel>> streamMyChatRooms() {
    final myUid = _myUid;
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
          .in_('uid', otherUids.toList());

      final Map<String, dynamic> userMap = {
        for (var u in (usersResponse as List)) u['uid'] as String: u
      };

      final List<ChatModel> chatList = [];
      for (final room in rooms) {
        final List<dynamic> participants = room['participants'] ?? [];
        final List<dynamic> unlockedBy = room['unlocked_by'] ?? [];
        final String otherUid = participants.firstWhere((id) => id != myUid, orElse: () => '');

        if (otherUid.isNotEmpty && userMap.containsKey(otherUid)) {
          final userData = userMap[otherUid];
          final bool isLocked = !unlockedBy.contains(myUid);
          final lastMessageAt = DateTime.tryParse(room['last_message_at'] ?? '');
          
          chatList.add(_ChatWithMetadata(
            model: ChatModel(
              id: otherUid,
              name: userData['name'] ?? 'Mtumiaji',
              avatarUrl: userData['profile_image_url'] ?? '',
              lastMessage: room['last_message'] ?? 'Anzeni mazungumzo! 👋',
              timeSent: _formatTimeAgo(lastMessageAt),
              isLocked: isLocked,
              unlockCostCoins: userData['chat_unlock_price'] ?? 50,
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

  String _formatTimeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Sasa hivi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m zilizopita';
    if (diff.inHours < 24) return '${diff.inHours}h zilizopita';
    return '${diff.inDays}d zilizopita';
  }
}
