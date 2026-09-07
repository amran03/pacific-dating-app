import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  final _client = Supabase.instance.client;

  Future<String?> uploadProfileImage(String uid, File imageFile) async {
    try {
      final fileName = '$uid.jpg';
      final path = 'profile_images/$fileName';

      await _client.storage.from('avatars').upload(
            path,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );

      final String downloadUrl =
          _client.storage.from('avatars').getPublicUrl(path);
      return downloadUrl;
    } catch (e) {
      debugPrint("Hitilafu wakati wa kupakia picha: $e");
      return null;
    }
  }

  Future<String?> uploadChatMedia(String chatId, File file, String extension) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
      final path = '$chatId/$fileName';

      await _client.storage.from('chat_media').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      final String downloadUrl =
          _client.storage.from('chat_media').getPublicUrl(path);
      return downloadUrl;
    } catch (e) {
      debugPrint("Error uploading chat media: $e");
      return null;
    }
  }
}
