import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';

/// Background/terminated FCM handler — runs in its own isolate.
/// Must stay top-level. No Supabase here and NO PushService import
/// (that would create an import cycle): payload strings are encoded
/// inline in the same `type|uid|name` / `call|...` format used by
/// NotificationService.
@pragma('vm:entry-point')
Future<void> firebaseBgHandler(RemoteMessage msg) async {
  try {
    await Firebase.initializeApp();
    final data = Map<String, dynamic>.from(msg.data);
    if (data['type'] == 'call') {
      final callId = data['call_id']?.toString() ?? '';
      final isVideo = data['is_video']?.toString() == 'true';
      final callerUid = data['from_uid']?.toString() ?? '';
      final callerName = data['from_name']?.toString() ?? 'Unknown';
      await NotificationService.showIncomingCallBackground(
        title: data['title']?.toString() ?? 'Incoming call',
        body: data['body']?.toString() ?? '',
        payload:
            'call|$callId|${isVideo ? 'video' : 'audio'}|$callerName|$callerUid',
      );
    } else {
      final fromUid = data['from_uid']?.toString() ?? '';
      final fromName = data['from_name']?.toString() ?? 'User';
      final type = data['type']?.toString() ?? 'message';
      await NotificationService.showChatMessageBackground(
        title: data['title']?.toString() ?? 'Pacific',
        body: data['body']?.toString() ?? '',
        payload: '$type|$fromUid|$fromName',
      );
    }
  } catch (_) {}
}
