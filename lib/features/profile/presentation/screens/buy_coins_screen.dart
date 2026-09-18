import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/features/profile/presentation/screens/payment_webview_screen.dart';
import 'package:pacific_dating_app/services/pesapal_service.dart';

/// Kifurushi kimoja cha Coins - 1 Coin = 25 TSH (kiwango cha ubadilishaji
/// kilichoombwa). Bei ni coins * 25.
class _CoinPackage {
  final int coins;
  final String? badge; // mfano "Maarufu" au "Zaidi ya thamani"

  const _CoinPackage(this.coins, {this.badge});

  int get priceTsh => coins * PesapalService.kCoinRateTzs;
}

const List<_CoinPackage> _kCoinPackages = [
  _CoinPackage(50),
  _CoinPackage(120, badge: "Maarufu 🔥"),
  _CoinPackage(300),
  _CoinPackage(650, badge: "Thamani Zaidi 💎"),
  _CoinPackage(1400),
  _CoinPackage(3000),
];

/// Skrini ya kununua Coins. 1 Coin = 25 TSH.
///
/// MTIRIRIKO WA MALIPO (PesaPal API 3.0):
///   1. Mtumiaji anagusa kifurushi -> [PesapalService.createOrder] inaita
///      Edge Function `create-pesapal-order` (server inahesabu kiasi,
///      inaunda order kwa PesaPal, inahifadhi rekodi ya PENDING).
///   2. [PaymentWebViewScreen] inafungua redirect_url ya PesaPal kwenye WebView.
///   3. Mtumiaji akimaliza kulipa, PesaPal inaipiga `pesapal-ipn` (webhook)
///      na inamrudisha kwenye `pesapal-return` (callback_url).
///   4. Edge Function inathibitisha malipo kwa GetTransactionStatus, inaweka
///      transactions = COMPLETED na inaongeza `coins` kwenye profile ya
///      mtumiaji (service_role - Flutter haiwezi kuongeza coins yenyewe).
///   5. Skrini hii inaonyesha matokeo; StreamBuilder ya salio inajisasisha
///      yenyewe (Realtime).
///
/// consumer_key/consumer_secret HAZIPO kwenye code hii — ziko kwenye
/// Supabase Edge Function secrets pekee.
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

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnack("Please sign in to buy coins.");
      return;
    }

    setState(() => _processingIndex = index);

    try {
      // Namba ya simu inahitajika kwa PesaPal (M-Pesa/Tigo/Airtel/Card).
      final String phone = await _resolvePhoneNumber(user.id);
      if (phone.isEmpty) {
        if (mounted) setState(() => _processingIndex = null);
        return;
      }

      // 1) Unda order kwa PesaPal kupitia Edge Function (server side).
      final PesapalOrderResult order = await PesapalService.instance.createOrder(
        coins: package.coins,
        description: '${package.coins} Pacific Coins',
        email: user.email,
        phone: phone,
      );

      if (!mounted) return;

      // 2) Fungua ukurasa wa malipo ya PesaPal kwenye WebView.
      final bool? paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PaymentWebViewScreen(
            redirectUrl: order.redirectUrl,
            orderId: order.orderId,
          ),
        ),
      );

      if (!mounted) return;

      // 3) Matokeo (coins zinaongezwa na Edge Function, sio app).
      if (paid == true) {
        _showSnack(
          "Payment successful! ${order.coins} coins added 🎉",
          color: Colors.green,
        );
      } else if (paid == false) {
        _showSnack(
          "Payment failed. No coins were added.",
          color: Colors.red,
        );
      } else {
        _showSnack(
          "Payment not confirmed yet. Coins will be added automatically once "
          "PesaPal confirms it.",
        );
      }
    } on PesapalException catch (e) {
      if (mounted) _showSnack(e.message, color: Colors.red);
    } catch (e) {
      if (mounted) _showSnack("Failed: $e", color: Colors.red);
    } finally {
      if (mounted) setState(() => _processingIndex = null);
    }
  }

  /// Rudisha namba ya simu ya mtumiaji; kama haipo kwenye profile, mwombe.
  Future<String> _resolvePhoneNumber(String uid) async {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('phone_number')
          .eq('uid', uid)
          .maybeSingle();
      final String existing = (row?['phone_number'] ?? '').toString().trim();
      if (existing.isNotEmpty) return existing;
    } catch (_) {
      // Kama kusoma profile kumeshindwa, mwombe mtumiaji namba.
    }
    if (!mounted) return '';
    return await _promptForPhone() ?? '';
  }

  /// Dialog: namba ya simu ya kulipia (PesaPal inaihitaji).
  Future<String?> _promptForPhone() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          "Phone number",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "PesaPal needs your mobile money number to complete this "
                "payment.",
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "0755123456",
                  prefixIcon: Icon(Icons.phone_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'[^\d]'), '');
                  if (digits.length < 9) {
                    return "Enter a valid phone number";
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
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
          "Buy Coins",
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
                  "Kiwango: Coin 1 = TSh ${PesapalService.kCoinRateTzs}",
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
                                : const Text("Buy", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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