import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pacific_dating_app/core/services/vip_service.dart';
import 'package:pacific_dating_app/core/services/core_error_service.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';

/// Screen inayomruhusu mtumiaji kuona coins alizonazo, tier yake ya sasa,
/// na kununua VIP Badge (Bronze / Gold / Diamond) kwa kutumia VIPService
/// iliyopo tayari.
class VIPPurchaseScreen extends StatefulWidget {
  const VIPPurchaseScreen({super.key});

  @override
  State<VIPPurchaseScreen> createState() => _VIPPurchaseScreenState();
}

class _VIPPurchaseScreenState extends State<VIPPurchaseScreen> {
  final VIPService _vipService = VIPService();
  final CoreErrorService _errorService = CoreErrorService();

  // Tier inayonunuliwa kwa sasa (kuzuia mtumiaji kubonyeza mara mbili)
  String? _purchasingTier;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Color _tierColor(String tier) {
    switch (tier) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'diamond':
        return const Color(0xFFB9F2FF);
      default:
        return AppColors.primary;
    }
  }

  Future<void> _handlePurchase(String tier) async {
    setState(() => _purchasingTier = tier);
    try {
      await _vipService.purchaseBadge(tier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Hongera! Umenunua ${VIPService.tiers[tier]!['name']} 🎉"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _errorService.showError(context, _errorService.mapExceptionToMessage(e));
    } finally {
      if (mounted) setState(() => _purchasingTier = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VIP Badges"),
        backgroundColor: AppColors.primary,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(_uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final int coins = data?['coins'] ?? 0;
          final String currentTier = data?['badgeTier'] ?? 'none';

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold),
                        const SizedBox(width: 8),
                        Text("Salio lako: $coins Coins",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Tier ya sasa: ${currentTier == 'none' ? 'Hakuna' : currentTier.toUpperCase()}",
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: VIPService.tiers.entries.map((entry) {
                    final tierKey = entry.key;
                    final tierData = entry.value;
                    final int cost = tierData['cost'];
                    final int minBalance = tierData['minBalance'];
                    final bool isCurrent = currentTier == tierKey;
                    final bool eligible = coins >= minBalance && coins >= cost;
                    final bool isLoading = _purchasingTier == tierKey;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrent ? _tierColor(tierKey) : Colors.grey.shade300,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _tierColor(tierKey).withOpacity(0.15),
                            ),
                            child: Icon(Icons.workspace_premium_rounded,
                                color: _tierColor(tierKey)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tierData['name'],
                                    style: const TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  "Bei: $cost Coins  •  Salio la chini: $minBalance",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 96,
                            child: isCurrent
                                ? const Chip(label: Text("Inatumika"))
                                : ElevatedButton(
                              onPressed: (!eligible || isLoading)
                                  ? null
                                  : () => _handlePurchase(tierKey),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _tierColor(tierKey),
                                foregroundColor: Colors.black87,
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                                  : const Text("Nunua"),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}