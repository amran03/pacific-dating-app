import 'package:supabase_flutter/supabase_flutter.dart';

class VIPService {
  final _client = Supabase.instance.client;

  String get _myUid => _client.auth.currentUser!.id;

  static const Map<String, Map<String, dynamic>> tiers = {
    'bronze': {
      'name': 'Bronze Ring',
      'minBalance': 500,
      'cost': 200,
      'color': 'Copper',
    },
    'gold': {
      'name': 'Gold Ring',
      'minBalance': 2000,
      'cost': 1000,
      'color': 'Gold',
    },
    'diamond': {
      'name': 'Diamond Ring',
      'minBalance': 5000,
      'cost': 3000,
      'color': 'Diamond',
    },
  };

  Future<bool> isEligible(String tier) async {
    final response = await _client.from('users').select('coins').eq('uid', _myUid).maybeSingle();
    if (response == null) return false;

    final int currentCoins = response['coins'] ?? 0;
    final int minBalance = tiers[tier]?['minBalance'] ?? 999999;

    return currentCoins >= minBalance;
  }

  Future<void> purchaseBadge(String tier) async {
    final tierData = tiers[tier];
    if (tierData == null) throw Exception('Invalid tier');

    final int cost = tierData['cost'];
    final int minBalance = tierData['minBalance'];

    final response = await _client.from('users').select().eq('uid', _myUid).single();
    final int currentCoins = response['coins'] ?? 0;

    if (currentCoins < minBalance) {
      throw Exception('MINIMUM_BALANCE_NOT_MET');
    }
    if (currentCoins < cost) {
      throw Exception('INSUFFICIENT_COINS');
    }

    final int currentTotalSpent = response['total_spent_coins'] ?? 0;

    await _client.from('users').update({
      'coins': currentCoins - cost,
      'badge_tier': tier,
      'total_spent_coins': currentTotalSpent + cost,
    }).eq('uid', _myUid);
  }

  Future<String> getCurrentTier() async {
    final response = await _client.from('users').select('badge_tier').eq('uid', _myUid).maybeSingle();
    return response?['badge_tier'] ?? 'none';
  }
}
