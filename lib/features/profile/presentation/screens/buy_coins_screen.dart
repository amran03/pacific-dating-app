import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';

/// Kifurushi kimoja cha Coins - 1 Coin = 100 TSH (kiwango cha ubadilishaji
/// kilichoombwa). Bei ni coins * 100.
class _CoinPackage {
  final int coins;
  final String? badge; // mfano "Maarufu" au "Zaidi ya thamani"

  const _CoinPackage(this.coins, {this.badge});

  int get priceTsh => coins * 100;
}

const List<_CoinPackage> _kCoinPackages = [
  _CoinPackage(50),
  _CoinPackage(120, badge: "Maarufu 🔥"),
  _CoinPackage(300),
  _CoinPackage(650, badge: "Thamani Zaidi 💎"),
  _CoinPackage(1400),
  _CoinPackage(3000),
];

/// Skrini ya kununua Coins. 1 Coin = 100 TSH.
///
/// MUHIMU (soma kabla ya ku-deploy kibiashara): Skrini hii kwa sasa
/// inaunganisha moja kwa moja na Supabase kuongeza coins BILA malipo
/// halisi ya pesa - ni MODE YA MAJARIBIO ili uweze kujaribu mtiririko
/// mzima wa app yako (coins zikitumika kwa gifts n.k.) bila kusubiri
/// malipo halisi kuunganishwa.
///
/// Kuunganisha malipo halisi (M-Pesa, Tigo Pesa, Airtel Money, au Card
/// kupitia Stripe/Flutterwave/Selcom) kunahitaji: (1) akaunti ya
/// mtoa-huduma wa malipo, (2) Edge Function ya kuthibitisha malipo
/// upande wa server kabla ya kuongeza coins (ili mtu asiweze kudanganya
/// app kwa kuruka malipo). Hilo ni hatua inayofuata - niambie ukiwa
/// tayari kuchagua mtoa-huduma wa malipo, nitakusaidia kuiunganisha.
class BuyCoinsScreen extends StatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends State<BuyCoinsScreen> {
  int? _processingIndex;

  String _formatTsh(int amount) {
    // Weka comma kila tarakimu 3 (mfano 12000 -> 12,000)
    final String raw = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final int posFromEnd = raw.length - i;
      buffer.write(raw[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }

  Future<void> _purchasePackage(int index, _CoinPackage package) async {
    if (_processingIndex != null) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    setState(() => _processingIndex = index);

    try {
      // Fetch current coins
      final userResponse = await client.from('users').select('coins').eq('uid', user.id).single();
      final int currentCoins = (userResponse['coins'] ?? 0) as int;

      // Update coins
      await client.from('users').update({
        'coins': currentCoins + package.coins,
      }).eq('uid', user.id);

      // Rekodi ununuzi kwa historia + arifa (NotificationScreen inaisoma hii)
      await client.from('notifications').insert({
        'to_uid': user.id,
        'type': 'coins',
        'title': 'Coins Zimeongezwa! 🪙',
        'description': 'Umefanikiwa kununua ${package.coins} Coins.',
        'created_at': DateTime.now().toIso8601String(),
        'read': false,
      });

      await client.from('coin_purchases').insert({
        'uid': user.id,
        'coins': package.coins,
        'price_tsh': package.priceTsh,
        'purchased_at': DateTime.now().toIso8601String(),
        'status': 'test_mode', // itabadilika kuwa 'paid' baada ya malipo halisi
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Umefanikiwa kuongeza ${package.coins} Coins! 🎉"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imeshindikana: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _processingIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final String myUid = client.auth.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Nunua Coins",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Salio la sasa
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.coinGold, Color(0xFFFFC94D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.coinGold.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: client.from('users').stream(primaryKey: ['uid']).eq('uid', myUid),
              builder: (context, snapshot) {
                final int coins = snapshot.hasData && snapshot.data!.isNotEmpty
                    ? (snapshot.data!.first['coins'] ?? 0) as int
                    : 0;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Salio Lako Sasa",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Row(
                      children: [
                        const Text("🪙 ", style: TextStyle(fontSize: 20)),
                        Text(
                          "$coins",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  "Kiwango: Coin 1 = TSh 100",
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _kCoinPackages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.95,
              ),
              itemBuilder: (context, index) {
                final package = _kCoinPackages[index];
                final bool isProcessing = _processingIndex == index;

                return GestureDetector(
                  onTap: isProcessing ? null : () => _purchasePackage(index, package),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: package.badge != null
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : Colors.grey.shade200,
                        width: package.badge != null ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (package.badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              package.badge!,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        const Spacer(),
                        const Text("🪙", style: TextStyle(fontSize: 34)),
                        const SizedBox(height: 6),
                        Text(
                          "${package.coins} Coins",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "TSh ${_formatTsh(package.priceTsh)}",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 34,
                          child: ElevatedButton(
                            onPressed: isProcessing ? null : () => _purchasePackage(index, package),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isProcessing
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                                : const Text("Nunua", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
  }
}