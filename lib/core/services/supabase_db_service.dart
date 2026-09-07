import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/profile/data/user_model.dart';

class SupabaseDbService {
  final _client = Supabase.instance.client;

  Future<void> saveUserProfile(UserModel user) async {
    await _client.from('users').upsert(user.toMap());
  }

  Future<UserModel?> getUserProfile(String uid) async {
    final response = await _client
        .from('users')
        .select()
        .eq('uid', uid)
        .maybeSingle();

    if (response != null) {
      return UserModel.fromMap(response);
    }
    return null;
  }

  // Generic stream for user profile updates (Realtime)
  Stream<Map<String, dynamic>> streamUserProfile(String uid) {
    return _client
        .from('users')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .map((event) => event.first);
  }
}
