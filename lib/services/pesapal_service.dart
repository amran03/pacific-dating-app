import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Payment status as seen in the `transactions` table.
enum PesapalStatus {
  /// PesaPal has not confirmed the payment yet.
  pending,

  /// Payment completed; coins were credited by the Edge Function.
  completed,

  /// Payment failed / reversed.
  failed,

  /// Status unknown (network, missing record, or not confirmed yet).
  unknown;

  bool get isFinal =>
      this == PesapalStatus.completed || this == PesapalStatus.failed;
}

/// Result of the `create-pesapal-order` Edge Function.
class PesapalOrderResult {
  const PesapalOrderResult({
    required this.redirectUrl,
    required this.orderId,
    required this.orderTrackingId,
    required this.amount,
    required this.coins,
    this.currency = 'TZS',
    this.description,
  });

  /// PesaPal payment URL (open it in a WebView).
  final String redirectUrl;

  /// Our order id: `PACIFIC-<uid>-<timestamp>`.
  final String orderId;

  /// PesaPal order_tracking_id.
  final String orderTrackingId;

  /// Amount paid (TZS) â€” calculated server side.
  final num amount;

  /// Coins received after a successful payment.
  final int coins;

  final String currency;
  final String? description;

  factory PesapalOrderResult.fromMap(Map<String, dynamic> map) {
    return PesapalOrderResult(
      redirectUrl: (map['redirectUrl'] ?? '').toString(),
      orderId: (map['orderId'] ?? '').toString(),
      orderTrackingId: (map['orderTrackingId'] ?? '').toString(),
      amount: (map['amount'] as num?) ?? 0,
      coins: ((map['coins'] as num?) ?? 0).toInt(),
      currency: (map['currency'] ?? 'TZS').toString(),
      description: map['description']?.toString(),
    );
  }

  bool get isValid => redirectUrl.isNotEmpty && orderId.isNotEmpty;
}

/// PesaPal payment exception (carries a user-facing message).
class PesapalException implements Exception {
  const PesapalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// PesaPal service for the Flutter side.
///
/// IMPORTANT: `consumer_key` / `consumer_secret` are NOT here. Flutter calls
/// Edge Functions (`create-pesapal-order`) and the Supabase Edge Function
/// secrets handle PesaPal API 3.0.
class PesapalService {
  PesapalService._();

  static final PesapalService instance = PesapalService._();

  /// Exchange rate: 1 Pacific Coin = 25 TZS.
  /// MUST match COIN_RATE_TZS in
  /// supabase/functions/create-pesapal-order/index.ts.
  static const int kCoinRateTzs = 25;

  /// Minimum / maximum coins per order.
  static const int kMinCoins = 10;
  static const int kMaxCoins = 200000;

  /// Part of our callback_url â€” PaymentWebViewScreen uses it to detect that
  /// the user has come back from PesaPal.
  static const String returnUrlMarker = 'pesapal-return';

  /// How long to wait for Realtime / polling.
  ///
  /// PesaPal's IPN/callback can lag after the redirect. We wait up to 45s on
  /// Realtime, then fall back to polling every 3s for up to 20 tries (~60s).
  static const Duration _realtimeTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(seconds: 3);
  static const int _pollAttempts = 20;

  SupabaseClient get _client => Supabase.instance.client;

  /// Convert TZS -> coins (for the UI: "How many coins you get").
  static int tzsToCoins(num amountTzs) => (amountTzs / kCoinRateTzs).floor();

  /// Convert coins -> TZS (for the UI: "How much you will pay").
  static int coinsToTzsAmount(int coins) => coins * kCoinRateTzs;

  /// The currently signed-in user (their Auth is used for uid/email).
  User? get currentUser => _client.auth.currentUser;

  /// Call the `create-pesapal-order` Edge Function and PesaPal.
  ///
  /// [coins]: the number of coins the user wants to buy (the server
  /// calculates the TZS amount).
  /// [email] / [phone]: optional â€” if omitted, the Edge Function takes them
  /// from the user's profile (public.users) or the Auth email.
  ///
  /// Returns a [PesapalOrderResult] with the `redirectUrl` to open in the
  /// WebView.
  Future<PesapalOrderResult> createOrder({
    required int coins,
    String? description,
    String? email,
    String? phone,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const PesapalException('You must sign in to buy coins.');
    }
    if (coins < kMinCoins || coins > kMaxCoins) {
      throw PesapalException(
        'Coins must be between $kMinCoins and $kMaxCoins.',
      );
    }

    final Map<String, dynamic> data;
    try {
      final response = await _client.functions.invoke(
        'create-pesapal-order',
        body: {
          'coins': coins,
          'amount': coinsToTzsAmount(coins),
          'description': description ?? '$coins Pacific Coins',
          'email': email ?? user.email,
          'phone': phone,
        },
      );
      data = _asMap(response.data);
    } on FunctionException catch (error) {
      throw PesapalException(_messageFromError(error.details));
    } catch (error) {
      throw PesapalException(
        'Could not start the payment. Please check your internet connection '
        'and try again. ($error)',
      );
    }

    final result = PesapalOrderResult.fromMap(data);
    if (!result.isValid) {
      throw PesapalException(
        _messageFromError(
          data,
          'PesaPal did not return a payment link. Please try again.',
        ),
      );
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Payment status
  // ---------------------------------------------------------------------------

  /// Read a single transaction record (RLS: the user only sees their own).
  Future<Map<String, dynamic>?> getTransaction(String orderId) async {
    final response = await _client
        .from('transactions')
        .select()
        .eq('id', orderId)
        .maybeSingle();
    return response;
  }

  Future<PesapalStatus> fetchStatus(String orderId) async {
    try {
      final row = await getTransaction(orderId);
      return statusFromRow(row);
    } catch (_) {
      return PesapalStatus.unknown;
    }
  }

  /// Wait for the final payment status (COMPLETED / FAILED).
  ///
  /// 1. Read the current status immediately (the IPN may have updated it).
  /// 2. If still PENDING: use Supabase Realtime (`.stream()`) â€” faster.
  /// 3. If Realtime fails or stalls: poll every 3 seconds (20 times).
  ///
  /// Returns [PesapalStatus.pending] if it is still not confirmed.
  Future<PesapalStatus> waitForFinalStatus(
    String orderId, {
    Duration realtimeTimeout = _realtimeTimeout,
  }) async {
    final immediate = await fetchStatus(orderId);
    if (immediate == PesapalStatus.completed ||
        immediate == PesapalStatus.failed) {
      return immediate;
    }

    // Realtime (skips polling when it works).
    try {
      final realtime = await _watchRealtime(orderId).timeout(realtimeTimeout);
      if (realtime == PesapalStatus.completed ||
          realtime == PesapalStatus.failed) {
        return realtime;
      }
    } catch (_) {
      // Realtime failed / timed out -> fall back to polling.
    }

    return _pollStatus(orderId);
  }

  /// Listen for record changes via Realtime until the final status arrives.
  Future<PesapalStatus> _watchRealtime(String orderId) {
    final completer = Completer<PesapalStatus>();
    StreamSubscription<List<Map<String, dynamic>>>? subscription;

    subscription = _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .listen(
      (rows) {
        if (rows.isEmpty || completer.isCompleted) return;
        final status = statusFromRow(rows.first);
        if (status == PesapalStatus.completed ||
            status == PesapalStatus.failed) {
          completer.complete(status);
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.complete(PesapalStatus.unknown);
        }
      },
      cancelOnError: true,
    );

    completer.future.whenComplete(() {
      subscription?.cancel();
    });

    return completer.future;
  }

  /// Polling: every 3 seconds, 20 times (when Realtime is unavailable).
  Future<PesapalStatus> _pollStatus(
    String orderId, {
    int attempts = _pollAttempts,
    Duration interval = _pollInterval,
  }) async {
    PesapalStatus status = PesapalStatus.pending;

    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(interval);
      status = await fetchStatus(orderId);
      if (status == PesapalStatus.completed || status == PesapalStatus.failed) {
        return status;
      }
    }

    return status == PesapalStatus.unknown
        ? PesapalStatus.pending
        : status;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Convert a `transactions` record -> [PesapalStatus].
  static PesapalStatus statusFromRow(Map<String, dynamic>? row) {
    if (row == null) return PesapalStatus.unknown;
    return statusFromString(row['status']?.toString());
  }

  static PesapalStatus statusFromString(String? rawStatus) {
    switch ((rawStatus ?? '').trim().toUpperCase()) {
      case 'COMPLETED':
      case 'SUCCESS':
      case 'PAID':
        return PesapalStatus.completed;
      case 'FAILED':
      case 'REVERSED':
      case 'CANCELLED':
        return PesapalStatus.failed;
      case 'PENDING':
        return PesapalStatus.pending;
      default:
        return PesapalStatus.unknown;
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// The Edge Function returns `{ "error": "..." }` whenever it fails.
  static String _messageFromError(
    dynamic details, [
    String fallback = 'Payment could not be started. Please try again.',
  ]) {
    if (details is Map) {
      final map = _asMap(details);
      final message = map['error'] ?? map['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    if (details is String && details.trim().isNotEmpty) return details.trim();
    return fallback;
  }
}