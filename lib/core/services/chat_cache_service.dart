import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';

/// Hifadhi ya ndani (storage ya simu) kwa chats + messages.
///
/// Lengo: mtumiaji aweze KUFUNGUA app na kutumia offline — orodha ya
/// mazungumzo na ujumbe wa mwisho unaonekana kutoka cache hata mtandao
/// ukishindikana; mtandao ukirudi, data halisi inasasisha background.
///
/// Nyepesi kwa makusudi: SharedPreferences + JSON (hakuna hive/isar).
/// Keys (`chat id` = uid zilizopangwa na '_'):
///   `chat_cache_v1:<uid>`            -> JSON list ya ChatModel
///   `msg_cache_v1:<chatId>`          -> JSON list ya message rows (max 80)
class ChatCacheService {
  ChatCacheService._();
  static final ChatCacheService instance = ChatCacheService._();

  static const String _chatPrefix = 'chat_cache_v1:';
  static const String _msgPrefix = 'msg_cache_v1:';
  static const int _maxCachedMessages = 80;

  // ---- CHATS (orodha ya mazungumzo) ----

  /// Hifadhi orodha ya chats (inaitwa kila data halisi inapowasili —
  /// background, bila kubadilisha UI).
  Future<void> saveChats(String myUid, List<ChatModel> chats) async {
    try {
      if (myUid.isEmpty) return;
      final List<Map<String, dynamic>> rows = chats
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'avatarUrl': c.avatarUrl,
                'lastMessage': c.lastMessage,
                'timeSent': c.timeSent,
                'isLocked': c.isLocked,
                'unlockCostCoins': c.unlockCostCoins,
              })
          .toList();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_chatPrefix$myUid', jsonEncode(rows));
    } catch (e) {
      debugPrint('ChatCache.saveChats failed: $e');
    }
  }

  /// Pakia chats kutoka cache (offline / stream imeshindwa). Rudisha []
  /// kama hakuna kitu.
  Future<List<ChatModel>> loadChats(String myUid) async {
    try {
      if (myUid.isEmpty) return [];
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString('$_chatPrefix$myUid');
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> rows = jsonDecode(raw) as List<dynamic>;
      return rows.map((e) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
        return ChatModel(
          id: (m['id'] ?? '') as String,
          name: (m['name'] ?? 'User') as String,
          avatarUrl: (m['avatarUrl'] ?? '') as String,
          lastMessage: (m['lastMessage'] ?? '') as String,
          timeSent: (m['timeSent'] ?? '') as String,
          isLocked: m['isLocked'] == true,
          unlockCostCoins: (m['unlockCostCoins'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('ChatCache.loadChats failed: $e');
      return [];
    }
  }

  // ---- MESSAGES (ujumbe wa kila chat) ----

  /// Hifadhi ujumbe wa chat (max [_maxCachedMessages] ya karibuni).
  /// Inaitwa kutoka stream ya ujumbe — background tu, hakuna UI effect.
  Future<void> saveMessages(
    String chatId,
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      if (chatId.isEmpty || messages.isEmpty) return;
      final List<Map<String, dynamic>> rows =
          messages.take(_maxCachedMessages).toList();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_msgPrefix$chatId', jsonEncode(rows));
    } catch (e) {
      debugPrint('ChatCache.saveMessages failed: $e');
    }
  }

  /// Pakia ujumbe uliohifadhiwa wa chat (offline fallback).
  Future<List<Map<String, dynamic>>> loadMessages(String chatId) async {
    try {
      if (chatId.isEmpty) return [];
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString('$_msgPrefix$chatId');
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> rows = jsonDecode(raw) as List<dynamic>;
      return rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('ChatCache.loadMessages failed: $e');
      return [];
    }
  }
}