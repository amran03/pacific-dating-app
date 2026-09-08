import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (!AppConfig.isSupabaseConfigured) {
      debugPrint(
        'Supabase NOT configured. Add your credentials via:\n'
        '  flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...\n'
        'or edit lib/core/config/app_config.dart',
      );
      return;
    }

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      );
      _initialized = true;
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

