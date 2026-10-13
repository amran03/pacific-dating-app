import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper that fans out a push notification through the `send-push`
/// Supabase Edge Function (FCM). Best-effort: failures are logged and
/// never break the caller flow. Works for messages, matches, gifts —
/// and incoming calls (which ring even when the app is killed).
class PushSender {
  PushSender._();

  /// Sends a push to [toUid]. For calls also pass [callId]/[isVideo].
  static Future<void> send({
    required String toUid,
    required String type,
    required String title,
    required String body,
    String fromUid = '',
    String fromName = '',
    String callId = '',
    bool isVideo = false,
  }) async {
    if (toUid.isEmpty) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'to_uid': toUid,
          'type': type,
          'title': title,
          'body': body,
          'from_uid': fromUid,
          'from_name': fromName,
          if (type == 'call') 'call_id': callId,
          if (type == 'call') 'is_video': isVideo,
        },
      );
    } catch (e) {
      debugPrint('Pacific: send-push failed: $e');
    }
  }
}
