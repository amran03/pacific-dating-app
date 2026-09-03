import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  Future<void> _sendGift(GiftModel gift, int currentCoins) async {
    if (_sendingGiftId != null) return; // Zuia kutuma mbili kwa wakati mmoja

    if (currentCoins < gift.coinPrice) {
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
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: pasificGifts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final gift = pasificGifts[index];
                        final bool canAfford = myCoins >= gift.coinPrice;
                        final bool isSending = _sendingGiftId == gift.id;

                        return GestureDetector(
                          onTap: canAfford ? () => _sendGift(gift, myCoins) : () {
                            setState(() => _errorMessage = "Huna Coins za kutosha kwa ${gift.name}.");
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 96,
                            decoration: BoxDecoration(
                              gradient: canAfford
                                  ? const LinearGradient(
                                colors: [Color(0xFFFFF0F5), Color(0xFFF3E8FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                                  : null,
                              color: canAfford ? null : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: canAfford
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                isSending
                                    ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                                )
                                    : Opacity(
                                  opacity: canAfford ? 1.0 : 0.4,
                                  child: Text(gift.emoji, style: const TextStyle(fontSize: 38)),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  gift.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: canAfford ? Colors.black87 : Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "🪙 ${gift.coinPrice}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: canAfford ? Colors.grey.shade700 : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
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