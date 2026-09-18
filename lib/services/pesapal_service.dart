import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Hali ya malipo kama inavyoonekana kwenye jedwali la `transactions`.
enum PesapalStatus {
  /// Bado PesaPal inathibitisha malipo.
  pending,

  /// Malipo yamekamilika; coins zimeongezwa na Edge Function.
  completed,

  /// Malipo yameshindwa / yamerejeshwa.
  failed,

  /// Hali haijulikani (mtandao, rekodi haipo, au bado haijathibitishwa).
  unknown;

  bool get isFinal =>
      this == PesapalStatus.completed || this == PesapalStatus.failed;
}

/// Matokeo ya `create-pesapal-order` Edge Function.
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

  /// URL ya malipo ya PesaPal (fungua kwenye WebView).
  final String redirectUrl;

  /// Order id yetu: `PACIFIC-<uid>-<timestamp>`.
  final String orderId;

  /// PesaPal order_tracking_id.
  final String orderTrackingId;

  /// Kiasi kilicholipwa (TZS) - kinahesabiwa server side.
  final num amount;

  /// Coins zinazopatikana baada ya malipo kufanikiwa.
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

/// Exception ya malipo ya PesaPal (ina ujumbe wa kuonyesha kwa mtumiaji).
class PesapalException implements Exception {
  const PesapalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Huduma ya PesaPal kwa upande wa Flutter.
///
/// MUHIMU: `consumer_key` / `consumer_secret` HAZIPO hapa. Flutter inaita
/// Edge Functions (`create-pesapal-order`) na Supabase Edge Function secrets
/// ndizo zinazoshughulikia PesaPal API 3.0.
class PesapalService {
  PesapalService._();

  static final PesapalService instance = PesapalService._();

  /// Kiwango cha ubadilishaji: 1 Pacific Coin = 25 TZS.
  /// LAZIMA ilingane na COIN_RATE_TZS kwenye
  /// supabase/functions/create-pesapal-order/index.ts.
  static const int kCoinRateTzs = 25;

  /// Kima cha chini / juu cha coins kwa order moja.
  static const int kMinCoins = 10;
  static const int kMaxCoins = 200000;

  /// Sehemu ya URL ya callback_url yetu - PaymentWebViewScreen inaitumia
  /// kugundua kwamba mtumiaji amerudi kutoka PesaPal.
  static const String returnUrlMarker = 'pesapal-return';

  /// Muda wa kusubiri Realtime / polling.
  static const Duration _realtimeTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(seconds: 2);
  static const int _pollAttempts = 6;

  SupabaseClient get _client => Supabase.instance.client;

  /// Badilisha TZS -> coins (kwa UI: "Unapata coins ngapi").
  static int tzsToCoins(num amountTzs) => (amountTzs / kCoinRateTzs).floor();

  /// Badilisha coins -> TZS (kwa UI: "Utalipa kiasi gani").
  static int coinsToTzsAmount(int coins) => coins * kCoinRateTzs;

  /// Mtumiaji aliyeingia kwa sasa (Auth yake inatumika kwa uid/email).
  User? get currentUser => _client.auth.currentUser;

  /// Ita Edge Function `create-pesapal-order` na PesaPal.
  ///
  /// [coins]: idadi ya coins mtumiaji anataka kununua (server inahesabu TZS).
  /// [email] / [phone]: si lazima - kama hazitolewa, Edge Function inazichukua
  /// kutoka profile ya mtumiaji (public.users) au email ya Auth.
  ///
  /// Inarudisha [PesapalOrderResult] yenye `redirectUrl` ya kuifungua kwenye
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
  // Hali ya malipo (status)
  // ---------------------------------------------------------------------------

  /// Soma rekodi moja ya transaction (RLS: mtumiaji anaona zake tu).
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

  /// Subiri hali ya mwisho ya malipo (COMPLETED / FAILED).
  ///
  /// 1. Soma hali ya sasa mara moja (huenda IPN ilikwisha sasisha).
  /// 2. Kama bado PENDING: tumia Supabase Realtime (`.stream()`) - haraka zaidi.
  /// 3. Kama Realtime inashindwa au inagoma: poll kila sekunde 2 (mara 6).
  ///
  /// Inarudisha [PesapalStatus.pending] kama bado haijathibitishwa.
  Future<PesapalStatus> waitForFinalStatus(
    String orderId, {
    Duration realtimeTimeout = _realtimeTimeout,
  }) async {
    final immediate = await fetchStatus(orderId);
    if (immediate == PesapalStatus.completed ||
        immediate == PesapalStatus.failed) {
      return immediate;
    }

    // Realtime (haipathi polling kama inafanya kazi).
    try {
      final realtime = await _watchRealtime(orderId).timeout(realtimeTimeout);
      if (realtime == PesapalStatus.completed ||
          realtime == PesapalStatus.failed) {
        return realtime;
      }
    } catch (_) {
      // Realtime imeshindwa / imeisha muda -> nenda kwa polling.
    }

    return _pollStatus(orderId);
  }

  /// Sikiliza mabadiliko ya rekodi kwa Realtime hadi status ya mwisho ifike.
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

  /// Polling: kila sekunde 2, mara 6 (kama Realtime haipatikani).
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

  /// Badilisha rekodi ya `transactions` -> [PesapalStatus].
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

  /// Edge Function inarudisha `{ "error": "..." }` kila inaposhindwa.
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