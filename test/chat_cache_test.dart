// Tests za cache ya chats (offline-first):
//  - serialization ya ChatModel -> JSON na kurudi (round-trip),
//  - fallback logic: live data inashinda; cache inaonekana offline;
//    loader kamili unaonyeshwa TU hakuna data kabisa.

import 'package:flutter_test/flutter_test.dart';

import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';

/// Nakala ya fallback logic ya chat_list_stream builder (logic safi,
/// ili iweze kupimwa bila Supabase).
///
/// Rudisha: `live` kama ipo na si tupu; vinginevyo `cached` kama ipo;
/// vinginevyo null (= onyesha loader/error).
List<ChatModel>? pickVisibleChats({
  required List<ChatModel>? live,
  required List<ChatModel> cached,
}) {
  final List<ChatModel> data = live ?? const [];
  if (data.isNotEmpty) return data;
  if (cached.isNotEmpty) return cached;
  return null;
}

void main() {
  final ChatModel a = ChatModel(
    id: 'u1',
    name: 'Amina',
    avatarUrl: 'http://img/a.png',
    lastMessage: 'Mambo',
    timeSent: '2h',
    isLocked: false,
    unlockCostCoins: 0,
  );
  final ChatModel b = ChatModel(
    id: 'u2',
    name: 'Juma',
    avatarUrl: '',
    lastMessage: 'Poa',
    timeSent: '1d',
    isLocked: true,
    unlockCostCoins: 50,
  );

  group('chat cache serialization', () {
    test('ChatModel inacarry fields zote muhimu (round-trip)', () {
      final Map<String, dynamic> m = {
        'id': a.id,
        'name': a.name,
        'avatarUrl': a.avatarUrl,
        'lastMessage': a.lastMessage,
        'timeSent': a.timeSent,
        'isLocked': a.isLocked,
        'unlockCostCoins': a.unlockCostCoins,
      };
      final back = ChatModel(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? 'User') as String,
        avatarUrl: (m['avatarUrl'] ?? '') as String,
        lastMessage: (m['lastMessage'] ?? '') as String,
        timeSent: (m['timeSent'] ?? '') as String,
        isLocked: m['isLocked'] == true,
        unlockCostCoins: (m['unlockCostCoins'] as num?)?.toInt() ?? 0,
      );
      expect(back.id, a.id);
      expect(back.name, a.name);
      expect(back.avatarUrl, a.avatarUrl);
      expect(back.lastMessage, a.lastMessage);
      expect(back.isLocked, a.isLocked);
      expect(back.unlockCostCoins, a.unlockCostCoins);
    });
  });

  group('pickVisibleChats (offline-first)', () {
    test('live data inashinda cache', () {
      expect(pickVisibleChats(live: [b], cached: [a]), [b]);
    });

    test('offline/hasError -> cache inaonekana kimya', () {
      expect(pickVisibleChats(live: null, cached: [a]), [a]);
      expect(pickVisibleChats(live: const [], cached: [a, b]), [a, b]);
    });

    test('hakuna data kabisa -> null (onyesha loader/error ndogo)', () {
      expect(pickVisibleChats(live: null, cached: const []), isNull);
      expect(pickVisibleChats(live: const [], cached: const []), isNull);
    });
  });
}