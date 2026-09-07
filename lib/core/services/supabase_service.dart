import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  // TODO: Replace with your actual Supabase credentials
  static const String _supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseAnonKey,
      );
      debugPrint('Supabase initialized successfully');
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
      rethrow;
    }
  }

  SupabaseClient get client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchGifts() async {
    try {
      final response = await client
          .from('gifts')
          .select()
          .order('coin_price', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching gifts: $e');
      return [];
    }
  }
}
