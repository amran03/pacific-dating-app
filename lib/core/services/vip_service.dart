import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';

class VIPService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  /// Definiton of VIP Tiers
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

  /// Check if user is eligible to buy a specific tier
  Future<bool> isEligible(String tier) async {
    final doc = await _db.collection('users').doc(_myUid).get();
    if (!doc.exists) return false;

    final int currentCoins = doc.data()?['coins'] ?? 0;
    final int minBalance = tiers[tier]?['minBalance'] ?? 999999;

    return currentCoins >= minBalance;
  }

  /// Purchase a VIP badge
  Future<void> purchaseBadge(String tier) async {
    final userRef = _db.collection('users').doc(_myUid);
    final tierData = tiers[tier];
    if (tierData == null) throw Exception('Invalid tier');

    final int cost = tierData['cost'];

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(userRef);
      if (!snap.exists) throw Exception('User not found');

      final int currentCoins = snap.data()?['coins'] ?? 0;
      final int minBalance = tierData['minBalance'];

      if (currentCoins < minBalance) {
        throw Exception('MINIMUM_BALANCE_NOT_MET');
      }
      if (currentCoins < cost) {
        throw Exception('INSUFFICIENT_COINS');
      }

      final int currentTotalSpent = snap.data()?['totalSpentCoins'] ?? 0;

      transaction.update(userRef, {
        'coins': currentCoins - cost,
        'badgeTier': tier,
        'totalSpentCoins': currentTotalSpent + cost,
      });
    });
  }

  /// Get current user's VIP status
  Future<String> getCurrentTier() async {
    final doc = await _db.collection('users').doc(_myUid).get();
    return doc.data()?['badgeTier'] ?? 'none';
  }
}
