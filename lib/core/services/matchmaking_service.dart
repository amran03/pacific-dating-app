import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';

/// Huduma kuu ya "matchmaking": Discover (kuonyesha watumiaji wapya),
/// like/pass halisi, kutambua Match (kupendana), na kuunda chat_room
/// kiotomatiki mtu wawili wanapopendana.
///
/// Muundo wa Firestore unaotumika:
/// - swipes/{myUid}/actions/{targetUid} -> {targetUid, action: 'like'|'pass', createdAt}
/// - matches/{chatId} -> {users: [uidA, uidB], matchedAt, chatRoomId}
/// - chat_rooms/{chatId} -> {participants: [uidA, uidB], lastMessage, lastMessageAt}
///
/// MUHIMU: streamUsersWhoLikedMe() inahitaji Composite Index kwenye
/// Firestore Console (Collection Group: actions | Fields: targetUid Asc,
/// action Asc). Mara ya kwanza utakapoendesha app, kama index haipo,
/// error ya Firestore itakupa LINK ya moja kwa moja ya kuunda index hiyo
/// - bonyeza tu link hiyo (inachukua dakika 1-2 kujengwa upande wa Google).
class MatchmakingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  /// Chumba/ID ya kipekee kati ya watumiaji wawili - sawa kabisa na jinsi
  /// IndividualChatScreen inavyotengeneza chatId yake.
  String chatIdFor(String otherUid) {
    final ids = [_myUid, otherUid]..sort();
    return ids.join('_');
  }

  /// Pata profile yangu mwenyewe (jina, coordinates, coins n.k.) - inatumika
  /// kwa mfano kuhesabu umbali kati yangu na watumiaji wengine.
  Future<UserModel?> fetchMyProfile() async {
    final doc = await _db.collection('users').doc(_myUid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.data()!);
  }

  /// Hesabu umbali (km) kati ya coordinates mbili kwa kutumia Haversine
  /// formula - sahihi vya kutosha kwa "watu walio karibu nawe" feature,
  /// bila haja ya huduma za nje (Google Distance Matrix n.k.).
  static double calculateDistanceKm(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const double earthRadiusKm = 6371;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);

  /// Tafuta watumiaji kwa jina (haijalishi herufi kubwa/ndogo). Inatumia
  /// 'nameLower' field (imewekwa kiotomatiki wakati wa kuhifadhi profile).
  /// MUHIMU: Hii ni "prefix search" (inalingana na MWANZO wa jina) - njia
  /// rahisi na ya haraka ya Firestore bila kuhitaji huduma za nje kama
  /// Algolia. "ami" itapata "Amina" lakini si "Salamini".
  Future<List<UserModel>> searchUsersByName(String query) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final snap = await _db
        .collection('users')
        .where('nameLower', isGreaterThanOrEqualTo: q)
        .where('nameLower', isLessThanOrEqualTo: '$q\uf8ff')
        .limit(20)
        .get();

    return snap.docs
        .where((doc) => doc.id != _myUid)
        .map((doc) => UserModel.fromMap(doc.data()))
        .toList();
  }

  /// Pata watumiaji wapya wa kuonyesha kwenye Discover: si mimi mwenyewe,
  /// na sijawahi kumu-swipe (like wala pass) hapo awali.
  Future<List<UserModel>> fetchDiscoverableUsers({int limit = 15}) async {
    final swipedSnap = await _db
        .collection('swipes')
        .doc(_myUid)
        .collection('actions')
        .get();

    final excludedUids = swipedSnap.docs.map((d) => d.id).toSet()..add(_myUid);

    final usersSnap = await _db
        .collection('users')
        .where('isProfileComplete', isEqualTo: true)
        .limit(limit + excludedUids.length)
        .get();

    return usersSnap.docs
        .where((doc) => !excludedUids.contains(doc.id))
        .map((doc) => UserModel.fromMap(doc.data()))
        .take(limit)
        .toList();
  }

  /// Rekodi like au pass kwa mtumiaji fulani. Inarudisha `true` kama
  /// pande zote mbili zimependana (Match!), vinginevyo `false`.
  Future<bool> recordSwipe(String targetUid, {required bool isLike}) async {
    await _db
        .collection('swipes')
        .doc(_myUid)
        .collection('actions')
        .doc(targetUid)
        .set({
      'targetUid': targetUid,
      'action': isLike ? 'like' : 'pass',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!isLike) return false;

    // Je, huyu naye ameshanipenda mimi tayari? (Mutual Match)
    final theirAction = await _db
        .collection('swipes')
        .doc(targetUid)
        .collection('actions')
        .doc(_myUid)
        .get();

    final bool isMutual =
        theirAction.exists && theirAction.data()?['action'] == 'like';

    if (isMutual) {
      await _createMatch(targetUid);
    }
    return isMutual;
  }

  Future<void> _createMatch(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final ids = [_myUid, otherUid]..sort();

    await _db.collection('matches').doc(chatId).set({
      'users': ids,
      'matchedAt': FieldValue.serverTimestamp(),
      'chatRoomId': chatId,
    });

    // Tengeneza chat_room mara moja, ikiwa TAYARI IMEFUNGULIWA kwa wote
    // wawili (wamependana = huru kuongea, hakuna malipo kati ya matches).
    await _db.collection('chat_rooms').doc(chatId).set({
      'participants': ids,
      'unlockedBy': ids,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Arifa kwa pande zote mbili - NotificationScreen inaisoma hii
    final myProfile = await fetchMyProfile();
    final theirDoc = await _db.collection('users').doc(otherUid).get();
    final String myName = myProfile?.name ?? 'Mtumiaji';
    final String theirName = (theirDoc.data()?['name'] ?? 'Mtumiaji') as String;

    final batch = _db.batch();
    batch.set(_db.collection('notifications').doc(), {
      'toUid': otherUid,
      'type': 'match',
      'title': 'Umepata Match! 🎉',
      'description': 'Wewe na $myName mmependana!',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    batch.set(_db.collection('notifications').doc(), {
      'toUid': _myUid,
      'type': 'match',
      'title': 'Umepata Match! 🎉',
      'description': 'Wewe na $theirName mmependana!',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    await batch.commit();
  }

  /// Kagua kama tayari nimefungua chat na mtu huyu, na bei yake (Coins)
  /// kama bado sijafungua. Tumia hii KABLA ya kuonyesha dialog ya malipo,
  /// ili mtumiaji aone bei kwanza kabla ya kulipa.
  Future<Map<String, dynamic>> getChatAccessInfo(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final chatSnap = await _db.collection('chat_rooms').doc(chatId).get();

    final List<String> unlockedBy = chatSnap.exists
        ? List<String>.from(chatSnap.data()?['unlockedBy'] ?? [])
        : [];

    if (unlockedBy.contains(_myUid)) {
      return {'unlocked': true, 'price': 0};
    }

    final otherDoc = await _db.collection('users').doc(otherUid).get();
    final int price = (otherDoc.data()?['chatUnlockPrice'] ?? 0) as int;

    return {'unlocked': false, 'price': price};
  }

  /// Lipa (kama kuna bei) na ufungue chat na mtu huyu. Coins zinatoka
  /// kwangu na kwenda moja kwa moja kwa mmiliki wa profile (yeye ndiye
  /// aliweka bei hiyo). Chat ikiwa bure (price 0), inafungua bila malipo.
  /// Inatupa Exception('INSUFFICIENT_COINS') kama huna coins za kutosha.
  Future<void> payAndUnlockChat(String otherUid) async {
    final String chatId = chatIdFor(otherUid);
    final chatRef = _db.collection('chat_rooms').doc(chatId);
    final List<String> ids = [_myUid, otherUid]..sort();

    final otherRef = _db.collection('users').doc(otherUid);
    final myRef = _db.collection('users').doc(_myUid);

    await _db.runTransaction((transaction) async {
      // KWANZA soma zote (sharti la Firestore transactions)
      final chatSnap = await transaction.get(chatRef);
      final otherSnap = await transaction.get(otherRef);

      final int price = (otherSnap.data()?['chatUnlockPrice'] ?? 0) as int;
      final String existingLastMessage = chatSnap.data()?['lastMessage'] ?? '';

      Map<String, dynamic> chatUpdate = {
        'participants': ids,
        'unlockedBy': FieldValue.arrayUnion([_myUid]),
        'lastMessage': existingLastMessage,
      };
      if (!chatSnap.exists) {
        chatUpdate['lastMessageAt'] = FieldValue.serverTimestamp();
      }

      if (price <= 0) {
        transaction.set(chatRef, chatUpdate, SetOptions(merge: true));
        return;
      }

      final mySnap = await transaction.get(myRef);
      final int myCoins = (mySnap.data()?['coins'] ?? 0) as int;
      if (myCoins < price) {
        throw Exception('INSUFFICIENT_COINS');
      }
      final int theirCoins = (otherSnap.data()?['coins'] ?? 0) as int;

      transaction.update(myRef, {'coins': myCoins - price});
      transaction.update(otherRef, {'coins': theirCoins + price});
      transaction.set(chatRef, chatUpdate, SetOptions(merge: true));
    });

    // Arifa kwa mmiliki wa profile kama kulikuwa na malipo
    final priceCheck = await otherRef.get();
    final int paidPrice = (priceCheck.data()?['chatUnlockPrice'] ?? 0) as int;
    if (paidPrice > 0) {
      final myDoc = await myRef.get();
      final String myName = (myDoc.data()?['name'] ?? 'Mtumiaji') as String;
      await _db.collection('notifications').add({
        'toUid': otherUid,
        'type': 'coins',
        'title': 'Umepokea Coins! 🪙',
        'description': '$myName amelipa $paidPrice Coins kufungua chat na wewe.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    }
  }

  /// Watu WOTE waliompenda huyu mtumiaji (kwa LikesScreen) - real-time.
  Stream<List<UserModel>> streamUsersWhoLikedMe() {
    return _db
        .collectionGroup('actions')
        .where('targetUid', isEqualTo: _myUid)
        .where('action', isEqualTo: 'like')
        .snapshots()
        .asyncMap((snap) async {
      final List<UserModel> likedByUsers = [];

      for (final doc in snap.docs) {
        final String? fromUid = doc.reference.parent.parent?.id;
        if (fromUid == null || fromUid == _myUid) continue;

        final userDoc = await _db.collection('users').doc(fromUid).get();
        if (userDoc.exists && userDoc.data() != null) {
          likedByUsers.add(UserModel.fromMap(userDoc.data()!));
        }
      }
      return likedByUsers;
    });
  }

  /// Watumiaji wote ambao "nimependana" nao (kwa ChatListScreen - Phase 2).
  Stream<List<Map<String, dynamic>>> streamMyMatches() {
    return _db
        .collection('matches')
        .where('users', arrayContains: _myUid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Chats zote za mtumiaji, zikiwa zimepangwa kwa ujumbe wa hivi karibuni
  /// zaidi juu - kwa ChatListScreen. Inasoma moja kwa moja kutoka
  /// chat_rooms (participants + lastMessage + lastMessageAt), hivyo
  /// inasasika papo hapo kila ujumbe mpya unapotumwa.
  ///
  /// MUHIMU: Query hii inahitaji Composite Index kwenye Firestore Console
  /// (Collection: chat_rooms | Fields: participants Array, lastMessageAt
  /// Desc). Firebase itakupa LINK ya moja kwa moja ya kuunda index hiyo
  /// kwenye debug console/logcat mara ya kwanza query hii ikishindwa.
  Stream<List<ChatModel>> streamMyChatRooms() {
    return _db
        .collection('chat_rooms')
        .where('participants', arrayContains: _myUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .asyncMap((snap) async {
      final List<ChatModel> chats = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        final List<dynamic> participants = data['participants'] ?? [];
        final String otherUid = participants
            .cast<String>()
            .firstWhere((uid) => uid != _myUid, orElse: () => '');

        if (otherUid.isEmpty) continue;

        final userDoc = await _db.collection('users').doc(otherUid).get();
        if (!userDoc.exists || userDoc.data() == null) continue;
        final userData = userDoc.data()!;

        final Timestamp? lastMsgTs = data['lastMessageAt'] as Timestamp?;
        final String lastMessage = (data['lastMessage'] ?? '').toString();

        chats.add(ChatModel(
          id: otherUid,
          name: userData['name'] ?? 'Mtumiaji',
          avatarUrl: (userData['profileImageUrl'] != null &&
              (userData['profileImageUrl'] as String).isNotEmpty)
              ? userData['profileImageUrl']
              : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=600',
          lastMessage: lastMessage.isEmpty ? 'Anzeni mazungumzo! 👋' : lastMessage,
          timeSent: _formatTimeAgo(lastMsgTs?.toDate()),
          // Phase 4: mfumo wa coins/timer wa ku-lock chat utaongezwa hapa.
          isLocked: false,
        ));
      }
      return chats;
    });
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