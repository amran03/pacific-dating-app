import 'package:flutter/material.dart';
import 'package:pacific_dating_app/core/services/vip_service.dart';
import 'package:pacific_dating_app/core/services/core_error_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BadgeStoreScreen extends StatefulWidget {
  const BadgeStoreScreen({super.key});

  @override
  State<BadgeStoreScreen> createState() => _BadgeStoreScreenState();
}

class _BadgeStoreScreenState extends State<BadgeStoreScreen> {
  final VIPService _vipService = VIPService();

  bool _isLoading = false;
  int _currentCoins = 0;
  String _currentTier = 'none';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        if (!mounted) return;

        CoreErrorService().showError(
          context,
          "Tafadhali ingia kwenye akaunti yako kwanza.",
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!mounted) return;

      final data = userDoc.data();

      final dynamic coinsValue = data?['coins'];
      final dynamic tierValue = data?['badgeTier'];

      final int coins = coinsValue is int
          ? coinsValue
          : int.tryParse(coinsValue?.toString() ?? '0') ?? 0;

      final String tier =
      tierValue is String && tierValue.trim().isNotEmpty
          ? tierValue
          : 'none';

      setState(() {
        _currentCoins = coins;
        _currentTier = tier;
      });
    } catch (e) {
      if (!mounted) return;

      CoreErrorService().showError(
        context,
        "Imeshindikana kupakia taarifa za VIP.",
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _buyBadge(String tier) async {
    if (_isLoading) return;

    final tierData = VIPService.tiers[tier];

    if (tierData == null) {
      if (!mounted) return;

      CoreErrorService().showError(
        context,
        "Badge hii haipatikani.",
      );
      return;
    }

    final dynamic minBalanceValue = tierData['minBalance'];
    final dynamic costValue = tierData['cost'];

    final int minBalance = minBalanceValue is int
        ? minBalanceValue
        : int.tryParse(minBalanceValue?.toString() ?? '0') ?? 0;

    final int cost = costValue is int
        ? costValue
        : int.tryParse(costValue?.toString() ?? '0') ?? 0;

    // Check minimum balance before starting purchase.
    if (_currentCoins < minBalance) {
      if (!mounted) return;

      CoreErrorService().showError(
        context,
        "Unahitaji kuwa na angalau $minBalance coins ili uweze "
            "kununua badge hii.",
      );
      return;
    }

    // Check if user already owns this badge.
    if (_currentTier == tier) {
      if (!mounted) return;

      CoreErrorService().showError(
        context,
        "Tayari unamiliki $tier badge.",
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _vipService.purchaseBadge(tier);

      if (!mounted) return;

      // Refresh coins and badge after successful purchase.
      await _loadUserData();

      if (!mounted) return;

      CoreErrorService().showError(
        context,
        "Hongera! Umepata $tier badge!",
        color: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;

      String message = "Imeshindikana kununua badge.";

      final error = e.toString();

      if (error.contains('MINIMUM_BALANCE_NOT_MET')) {
        message =
        "Unahitaji kuwa na angalau $minBalance coins ili uweze "
            "kununua badge hii.";
      } else if (error.contains('INSUFFICIENT_COINS')) {
        message = "Huna coins za kutosha kulipia badge hii.";
      } else if (error.contains('BADGE_ALREADY_OWNED')) {
        message = "Tayari unamiliki badge hii.";
      }

      CoreErrorService().showError(
        context,
        message,
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),

        title: const Text(
          "VIP Status Store",
          style: TextStyle(
            color: Colors.amber,
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: 1.1,
          ),
        ),

        centerTitle: true,

        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.amber,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Colors.amber,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  "$_currentCoins",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.amber,
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Chagua Hadhi Yako",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              "Ongeza mvuto wa profile yako na uweze "
                  "kutambulika kama mtu mwenye uwezo.",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 32),

            // BRONZE
            _buildTierCard(
              tier: 'bronze',
              name: 'Bronze Ring',
              description: 'The Rising Star',
              minBalance: 500,
              cost: 200,
              color: const Color(0xFFCD7F32),
            ),

            const SizedBox(height: 20),

            // GOLD
            _buildTierCard(
              tier: 'gold',
              name: 'Gold Ring',
              description: 'The Elite Member',
              minBalance: 2000,
              cost: 1000,
              color: const Color(0xFFFFD700),
            ),

            const SizedBox(height: 20),

            // DIAMOND
            _buildTierCard(
              tier: 'diamond',
              name: 'Diamond Ring',
              description: 'The Legendary Status',
              minBalance: 5000,
              cost: 3000,
              color: const Color(0xFFB9F2FF),
            ),

            const SizedBox(height: 40),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.amber,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Habari Muhimu",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Ili uweze kununua badge, lazima ufikishe "
                        "kiwango cha chini cha coins kwenye akaunti "
                        "yako kwanza. Hii inathibitisha hadhi yako ya VIP.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard({
    required String tier,
    required String name,
    required String description,
    required int minBalance,
    required int cost,
    required Color color,
  }) {
    final bool isOwned = _currentTier == tier;
    final bool isEligible = _currentCoins >= minBalance;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isOwned
            ? color.withOpacity(0.15)
            : const Color(0xFF1A1A1A),

        borderRadius: BorderRadius.circular(24),

        border: Border.all(
          color: isOwned
              ? color
              : Colors.white.withOpacity(0.1),
          width: isOwned ? 2 : 1,
        ),

        boxShadow: [
          if (isOwned)
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
        ],
      ),

      child: Row(
        children: [
          // Ring Visual
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.workspace_premium_rounded,
                color: color,
                size: 30,
              ),
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isOwned ? color : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  "Minimum: $minBalance coins",
                  style: TextStyle(
                    color: isEligible
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          if (isOwned)
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 24,
            )
          else
            ElevatedButton(
              onPressed: (!_isLoading && isEligible)
                  ? () => _buyBadge(tier)
                  : null,

              style: ElevatedButton.styleFrom(
                backgroundColor: isEligible
                    ? color
                    : Colors.grey.shade800,

                disabledBackgroundColor:
                Colors.grey.shade800,

                foregroundColor: Colors.black,

                disabledForegroundColor:
                Colors.grey.shade500,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),

                elevation: 0,

                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),

              child: Text(
                "$cost 🪙",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}