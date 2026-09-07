import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/features/chat/domain/models/gift_model.dart';

/// Modal ya kutuma zawadi - muundo wa TikTok: tray ya kusogeza kwa mlalo,
/// coins zako halisi zinaonekana juu, na kutuma zawadi kunapunguza coins
/// zako papo hapo kupitia Firestore transaction (salama dhidi ya "double
/// spend" hata ukibonyeza haraka mara mbili).
///
/// MUHIMU: Hii ndiyo widget MOJA inayotumika sehemu zote mbili - Discover
/// na Chat - badala ya kuwa na mifumo miwili tofauti ya gifts.
class GiftModalBottomSheet {
  static void show(
      BuildContext context, {
        required String recipientUid,
        required String recipientName,
        required void Function(GiftModel gift) onGiftSent,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GiftSheetContent(
        recipientUid: recipientUid,
        recipientName: recipientName,
        onGiftSent: onGiftSent,
      ),
    );
  }
}

class _GiftSheetContent extends StatefulWidget {
  final String recipientUid;
  final String recipientName;
  final void Function(GiftModel gift) onGiftSent;

  const _GiftSheetContent({
    required this.recipientUid,
    required this.recipientName,
    required this.onGiftSent,
  });

  @override
  State<_GiftSheetContent> createState() => _GiftSheetContentState();
}

class _GiftSheetContentState extends State<_GiftSheetContent> {
  String? _sendingGiftId;
  String? _errorMessage;
  Set<String> _unlockedGifts = {};

  @override
  void initState() {
    super.initState();
    _loadUnlockedGifts();
  }

  Future<void> _loadUnlockedGifts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unlocked = prefs.getStringList('unlocked_gifts') ?? [];
      if (mounted) {
        setState(() => _unlockedGifts = unlocked.toSet());
      }
    } catch (_) {}
  }

  Future<void> _unlockGift(String giftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unlocked = prefs.getStringList('unlocked_gifts') ?? [];
      if (!unlocked.contains(giftId)) {
        unlocked.add(giftId);
        await prefs.setStringList('unlocked_gifts', unlocked);
      }
      if (mounted) {
        setState(() => _unlockedGifts = unlocked.toSet());
      }
    } catch (_) {}
  }

  bool _isGiftUnlocked(String giftId) => _unlockedGifts.contains(giftId);

  Future<void> _sendGift(GiftModel gift, int currentCoins) async {
    if (_sendingGiftId != null) return; // Zuia kutuma mbili kwa wakati mmoja

    // Check if gift is already unlocked - if so, allow without coin check
    final isUnlocked = _isGiftUnlocked(gift.id);
    
    if (!isUnlocked && currentCoins < gift.coinPrice) {
      setState(() => _errorMessage = "Huna Coins za kutosha kwa ${gift.name}. Nunua Coins zaidi.");
      return;
    }

    setState(() {
      _sendingGiftId = gift.id;
      _errorMessage = null;
    });

    final String myUid = FirebaseAuth.instance.currentUser!.uid;
    final myRef = FirebaseFirestore.instance.collection('users').doc(myUid);

    try {
      // If gift is already unlocked, skip coin deduction
      if (!isUnlocked) {
        // Transaction inahakikisha coins hazipunguzwi chini ya sifuri hata
        // kama request mbili zikitokea kwa wakati mmoja (atomic).
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(myRef);
          final int liveCoins = (snapshot.data()?['coins'] ?? 0) as int;

          if (liveCoins < gift.coinPrice) {
            throw Exception('INSUFFICIENT_COINS');
          }

          transaction.update(myRef, {'coins': liveCoins - gift.coinPrice});
        });
      }

      // Rekodi zawadi kwa historia
      await FirebaseFirestore.instance.collection('gifts_sent').add({
        'fromUid': myUid,
        'toUid': widget.recipientUid,
        'giftId': gift.id,
        'giftName': gift.name,
        'giftEmoji': gift.emoji,
        'coinCost': gift.coinPrice,
        'sentAt': FieldValue.serverTimestamp(),
      });

      // Arifa kwa recipient - NotificationScreen inaisoma hii moja kwa moja
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final String myName = (myDoc.data()?['name'] ?? 'Mtumiaji') as String;

      await FirebaseFirestore.instance.collection('notifications').add({
        'toUid': widget.recipientUid,
        'type': 'gift',
        'title': 'Umepokea Zawadi Mpya! 🎁',
        'description': '$myName amekutumia ${gift.emoji} ${gift.name}.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });

      // Mark gift as permanently unlocked after successful send
      await _unlockGift(gift.id);

      if (!mounted) return;
      Navigator.pop(context);
      widget.onGiftSent(gift);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingGiftId = null;
        _errorMessage = e.toString().contains('INSUFFICIENT_COINS')
            ? "Huna Coins za kutosha kwa ${gift.name}."
            : "Imeshindikana kutuma zawadi. Jaribu tena.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
          builder: (context, snapshot) {
            final int myCoins = snapshot.hasData && snapshot.data!.exists
                ? ((snapshot.data!.data() as Map<String, dynamic>?)?['coins'] ?? 0) as int
                : 0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "Tuma Zawadi kwa ${widget.recipientName} 🎁",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.coinGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("🪙 ", style: TextStyle(fontSize: 14)),
                            Text(
                              "$myCoins",
                              style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.coinGold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              // Nafasi ya baadaye kuunganisha In-App Purchases
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Ununuzi wa Coins unakuja hivi karibuni! 🪙")),
                              );
                            },
                            child: const Text("Nunua", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // TikTok-style: tray ya kusogeza kwa MLALO
                  SizedBox(
                    height: 158,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      itemCount: pasificGifts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final gift = pasificGifts[index];
                        final bool isUnlocked = _isGiftUnlocked(gift.id);
                        final bool canAfford = isUnlocked || myCoins >= gift.coinPrice;
                        final bool isSending = _sendingGiftId == gift.id;

                        return _GiftCard(
                          gift: gift,
                          canAfford: canAfford,
                          isUnlocked: isUnlocked,
                          isSending: isSending,
                          index: index,
                          onTap: canAfford
                              ? () => _sendGift(gift, myCoins)
                              : () {
                                  setState(() => _errorMessage =
                                      "Huna Coins za kutosha kwa ${gift.name}.");
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// GIFT CARD — impressive tier-styled card:
//  - staggered entrance animation (scale + fade, kila card inachelewa)
//  - premium : gradient ya rangi ya zawadi + glow
//  - luxury  : glow inayopulsa (repeat) + border ya mwanga + tag "VIP"
//  - locked  : dim + chip ya lock (huna coins)
// ============================================================

class _GiftCard extends StatefulWidget {
  final GiftModel gift;
  final bool canAfford;
  final bool isUnlocked;
  final bool isSending;
  final int index;
  final VoidCallback onTap;

  const _GiftCard({
    required this.gift,
    required this.canAfford,
    required this.isUnlocked,
    required this.isSending,
    required this.index,
    required this.onTap,
  });

  @override
  State<_GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends State<_GiftCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.5,
    );

    // Staggered entrance: kila card inaingia na uchelewa kidogo.
    Future.delayed(Duration(milliseconds: 90 * widget.index), () {
      if (mounted) setState(() => _entered = true);
    });

    // Luxury tu ndiyo ina pulse ya kudumu (performance-friendly).
    if (widget.gift.isLuxury) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Widget _buildCardInner(GiftModel gift, bool locked, double glow) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Tier tag kwa luxury/premium
        if (!locked && (gift.isLuxury || gift.isPremium))
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gift.glowColor,
                  gift.glowColor.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              gift.isLuxury ? "VIP" : "PRO",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),

        // Emoji au spinner wakati wa kutuma
        widget.isSending
            ? const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              )
            : Transform.scale(
                scale: gift.isLuxury ? 1.0 + 0.08 * _glowController.value : 1.0,
                child: Opacity(
                  opacity: locked ? 0.35 : 1.0,
                  child: Text(
                    gift.emoji,
                    style: const TextStyle(fontSize: 42),
                  ),
                ),
              ),

        const SizedBox(height: 6),

        // Jina (au lock/unlock chip)
        locked
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      "Locked",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              )
            : widget.isUnlocked
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_open_rounded,
                        size: 12,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          "Unlocked",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    gift.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),

        const SizedBox(height: 3),

        // Price pill
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: locked
                ? Colors.grey.shade200
                : widget.isUnlocked
                    ? AppColors.success.withValues(alpha: 0.16)
                    : AppColors.coinGold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.isUnlocked ? "✓ Unlocked" : "🪙 ${gift.coinPrice}",
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: locked
                  ? Colors.grey.shade500
                  : widget.isUnlocked
                      ? AppColors.success
                      : AppColors.coinGoldDark,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gift = widget.gift;
    final bool locked = !widget.canAfford;

    // Glow intensity: luxury inapulsa, premium ni static glow ndogo.
    final double glow = gift.isLuxury
        ? 0.35 + 0.35 * _glowController.value
        : (gift.isPremium ? 0.28 : 0.12);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _entered ? 1.0 : 0.6,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _entered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 380),
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Container(
                width: 100,
                decoration: BoxDecoration(
                  gradient: locked
                      ? null
                      : LinearGradient(
                          colors: [
                            gift.glowColor.withValues(alpha: 0.16),
                            gift.glowColor.withValues(alpha: 0.05),
                            Colors.white,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                  color: locked ? Colors.grey.shade100 : null,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: locked
                        ? Colors.grey.shade300
                        : gift.isLuxury
                            ? gift.glowColor.withValues(alpha: glow)
                            : gift.glowColor.withValues(alpha: 0.3),
                    width: gift.isLuxury ? 2 : 1.5,
                  ),
                  boxShadow: locked
                      ? null
                      : [
                          BoxShadow(
                            color: gift.glowColor.withValues(alpha: glow),
                            blurRadius: gift.isLuxury ? 22 : 12,
                            spreadRadius: gift.isLuxury ? 2 : 0,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                child: _buildCardInner(gift, locked, glow),
              );
            },
          ),
        ),
      ),
    );
  }
}