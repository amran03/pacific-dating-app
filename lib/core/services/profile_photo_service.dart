import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pacific_dating_app/services/connectivity_service.dart';
import 'package:pacific_dating_app/utils/error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Huduma ya picha za profile (max 6).
///
///  - Hukusanya picha (pickMultiImage), huzibana (compress) kabla ya upload.
///  - Huweka metadata kwenye profile_photos (position 0 = picha ya mbele).
///  - Huwezesha kupanga upya (reorder) + kufuta (storage + row).
///  - Huhakikisha users.profile_image_url inalingana na picha ya position 0.
class ProfilePhoto {
  final String id;
  final String userId;
  final String url;
  final int position;

  const ProfilePhoto({
    required this.id,
    required this.userId,
    required this.url,
    required this.position,
  });

  factory ProfilePhoto.fromMap(Map<String, dynamic> map) {
    return ProfilePhoto(
      id: (map['id'] ?? '') as String,
      userId: (map['user_id'] ?? '') as String,
      url: (map['url'] ?? '') as String,
      position: (map['position'] ?? 0) as int,
    );
  }
}

/// Error ya picha — inaonyesha CHANZO halisi (mtandao, ruhusa, kikomo, n.k.)
/// badala ya ujumbe mmoja mpaka "imeshindikana". UI huonyesha [message] kwenye
/// popup, na [isNetwork] hutumika kuona kama ni mtandao pekee.
class ProfilePhotoException implements Exception {
  final String message;
  final bool isNetwork;
  const ProfilePhotoException(this.message, {this.isNetwork = false});

  @override
  String toString() => message;
}

class ProfilePhotoService {
  ProfilePhotoService._();
  static final ProfilePhotoService instance = ProfilePhotoService._();

  final _client = Supabase.instance.client;
  final _picker = ImagePicker();

  static const int maxPhotos = 6;
  static const String bucket = 'profile-photos';

  // ---- Picha zilizopo ----

  /// Pakia picha zote za mtumiaji kutoka `profile_photos` (zimepangwa).
  Future<List<ProfilePhoto>> fetchPhotos(String userId) async {
    try {
      final rows = await _client
          .from('profile_photos')
          .select()
          .eq('user_id', userId)
          .order('position');
      final list = (rows as List)
          .map((e) => ProfilePhoto.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort((a, b) => a.position.compareTo(b.position));
      return list;
    } catch (e) {
      debugPrint('fetchPhotos failed: $e');
      return [];
    }
  }

  /// Chagua picha nyingi (hadi [remaining]). Huzibana kabla ya kurudisha.
  Future<List<XFile>> pickMultiImage({int remaining = -1}) async {
    try {
      final int limit =
          remaining <= 0 ? maxPhotos : remaining.clamp(1, maxPhotos).toInt();
      final picked = await _picker.pickMultiImage(limit: limit);
      if (picked.isEmpty) return [];
      return picked.take(limit).toList();
    } catch (e) {
      debugPrint('pickMultiImage failed: $e');
      return [];
    }
  }

  /// Weka picha moja: compress -> upload storage -> insert row -> sync main.
  ///
  /// Inathrow [ProfilePhotoException] yenye ujumbe rafiki + chanzo halisi
  /// (mtandao/ruhusa/kikomo/n.k.) ili UI ionyeshe popup sahihi — si ujumbe
  /// mmoja mweusi "imeshindikana".
  Future<ProfilePhoto?> uploadOne(
    String userId,
    XFile file, {
    int? position,
  }) async {
    // Ukosefu wa mtandao: usijaribu upload (kuta timeout ndefu) — onyesha
    // popup ya mtandao mara moja.
    if (!ConnectivityService.instance.isCurrentlyOnline) {
      throw const ProfilePhotoException(
        'Hakuna mtandao. Unganisha internet kisha jaribu tena.',
        isNetwork: true,
      );
    }

    try {
      final bytes = await file.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1080,
        minHeight: 1080,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      // Some devices can return an empty list on failure — fall back to original.
      final Uint8List data = compressed.isEmpty ? bytes : compressed;

      final existing = await fetchPhotos(userId);
      final int pos = (position ?? existing.length).clamp(0, maxPhotos - 1).toInt();
      final fileName =
          '$userId/${DateTime.now().millisecondsSinceEpoch}_$pos.jpg';

      await _client.storage.from(bucket).uploadBinary(
            fileName,
            data,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      final url = _client.storage.from(bucket).getPublicUrl(fileName);

      final row = (await _client.from('profile_photos').insert({
        'user_id': userId,
        'url': url,
        'position': pos,
      }).select().maybeSingle());
      if (row == null) return null;
      final photo =
          ProfilePhoto.fromMap(Map<String, dynamic>.from(row as Map));
      await _syncMainPhoto(userId);
      return photo;
    } catch (e) {
      debugPrint('uploadOne failed: $e');
      // Weka ujumbe halisi (mtandao/ruhusa/kikomo) — UI waonyeshe popup sahihi.
      throw _classify(e, upload: true);
    }
  }

  /// Badilisha error yoyote kuwa [ProfilePhotoException] rafiki — chanzo halisi
  /// (network vs permission vs limit vs nyingine).
  ProfilePhotoException _classify(Object e, {bool upload = false}) {
    if (e is ProfilePhotoException) return e;

    final String s = e.toString();
    final String low = s.toLowerCase();

    // ---- Network-level (halisi hakuna mtandao) — isNetworkError ndio
    // chanzo kimoja cha ukaguzi wa mtandao app yote (error_handler).
    if (isNetworkError(e)) {
      return const ProfilePhotoException(
        'Hakuna mtandao. Unganisha internet kisha jaribu tena.',
        isNetwork: true,
      );
    }

    // ---- Kikomo cha picha 6 (DB trigger) ----
    if (low.contains('profile_photo_limit') ||
        low.contains('kikomo cha picha') ||
        (upload && low.contains('limit'))) {
      return const ProfilePhotoException(
        'Umefika kikomo cha picha 6. Futa picha moja kwanza.',
      );
    }

    // ---- Ruhusa / RLS / bucket ----
    if (e is StorageException ||
        low.contains('row-level security') ||
        low.contains('permission') ||
        low.contains('not authorized') ||
        low.contains('violates') ||
        low.contains('bucket not found') ||
        low.contains('403') ||
        low.contains('401')) {
      return const ProfilePhotoException(
        'Hakuna ruhusa kupakia picha kwenye akaunti hii.',
      );
    }

    // ---- Ujumbe mwingine wa Supabase ----
    return ProfilePhotoException(
      upload
          ? 'Imeshindikana kupakia picha. Jaribu tena baadaye.'
          : 'Imeshindikana. Jaribu tena baadaye.',
    );
  }

  /// Futa picha (storage + row) kisha sync picha ya mbele.
  Future<bool> deletePhoto(ProfilePhoto photo) async {
    try {
      final uri = Uri.tryParse(photo.url);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final idx = uri.pathSegments.indexOf(bucket);
        final objectPath = idx >= 0
            ? uri.pathSegments.sublist(idx + 1).join('/')
            : uri.pathSegments.last;
        if (objectPath.isNotEmpty) {
          await _client.storage.from(bucket).remove([objectPath]);
        }
      }
      await _client.from('profile_photos').delete().eq('id', photo.id);
      await _syncMainPhoto(photo.userId);
      return true;
    } catch (e) {
      debugPrint('deletePhoto failed: $e');
      return false;
    }
  }

  /// Pangilia upya: batch-update positions kwa mpangilio wa [orderedIds].
  Future<bool> reorder(String userId, List<String> orderedIds) async {
    try {
      for (var i = 0; i < orderedIds.length; i++) {
        await _client
            .from('profile_photos')
            .update({'position': i}).eq('id', orderedIds[i]);
      }
      await _syncMainPhoto(userId);
      return true;
    } catch (e) {
      debugPrint('reorder failed: $e');
      return false;
    }
  }

  /// Weka users.profile_image_url = url ya position 0 (au null kama hakuna).
  Future<void> _syncMainPhoto(String userId) async {
    try {
      final photos = await fetchPhotos(userId);
      final mainUrl = photos.isEmpty ? null : photos.first.url;
      await _client.from('users').update({
        'profile_image_url': mainUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', userId);
    } catch (e) {
      debugPrint('_syncMainPhoto failed: $e');
    }
  }
}

