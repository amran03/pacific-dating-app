// Tests za logic safi ya PesapalService (hazihitaji Supabase/network).
//
// Hizi zinahakikisha ubadilishaji wa bei (1 coin = 25 TZS), ubadilishaji wa
// hali ya malipo kutoka jedwali la `transactions`, na usomaji wa jibu la
// Edge Function `create-pesapal-order`.

import 'package:flutter_test/flutter_test.dart';

import 'package:pacific_dating_app/services/pesapal_service.dart';

void main() {
  group('PesapalService coin <-> TZS', () {
    test('coinsToTzsAmount: 1 coin = 25 TZS', () {
      expect(PesapalService.coinsToTzsAmount(1), 25);
      expect(PesapalService.coinsToTzsAmount(50), 1250);
      expect(PesapalService.coinsToTzsAmount(1000), 25000);
    });

    test('tzsToCoins: ina-floor kiasi kisichogawanyika kikamilifu', () {
      expect(PesapalService.tzsToCoins(5000), 200);
      expect(PesapalService.tzsToCoins(5499), 219); // 219.96 -> 219
      expect(PesapalService.tzsToCoins(99), 3); // 3.96 -> 3
      expect(PesapalService.tzsToCoins(24), 0); // 0.96 -> 0
    });
  });

  group('PesapalService.statusFromString', () {
    test('COMPLETED/SUCCESS/PAID -> completed', () {
      for (final value in ['COMPLETED', 'success', ' paid ']) {
        expect(PesapalService.statusFromString(value), PesapalStatus.completed);
      }
    });

    test('FAILED/REVERSED/CANCELLED -> failed', () {
      for (final value in ['FAILED', 'reversed', 'Cancelled']) {
        expect(PesapalService.statusFromString(value), PesapalStatus.failed);
      }
    });

    test('PENDING -> pending; nyingine -> unknown', () {
      expect(PesapalService.statusFromString('PENDING'), PesapalStatus.pending);
      expect(PesapalService.statusFromString(null), PesapalStatus.unknown);
      expect(PesapalService.statusFromString(''), PesapalStatus.unknown);
      expect(PesapalService.statusFromString('foo'), PesapalStatus.unknown);
    });

    test('statusFromRow inasoma column ya status', () {
      expect(
        PesapalService.statusFromRow({'status': 'COMPLETED'}),
        PesapalStatus.completed,
      );
      expect(PesapalService.statusFromRow(null), PesapalStatus.unknown);
    });

    test('isFinal: pending/unknown si ya mwisho', () {
      expect(PesapalStatus.completed.isFinal, isTrue);
      expect(PesapalStatus.failed.isFinal, isTrue);
      expect(PesapalStatus.pending.isFinal, isFalse);
      expect(PesapalStatus.unknown.isFinal, isFalse);
    });
  });

  group('PesapalOrderResult.fromMap', () {
    test('inasoma jibu la create-pesapal-order', () {
      final result = PesapalOrderResult.fromMap({
        'redirectUrl': 'https://pay.pesapal.com/iframe/PesapalIframe3',
        'orderId': 'PACIFIC-abc-1700000000000',
        'orderTrackingId': 'track-123',
        'amount': 5000,
        'coins': 50,
        'currency': 'TZS',
        'description': '50 Pacific Coins',
      });

      expect(result.isValid, isTrue);
      expect(result.coins, 50);
      expect(result.amount, 5000);
      expect(result.currency, 'TZS');
      expect(result.orderId, 'PACIFIC-abc-1700000000000');
    });

    test('haipo redirectUrl/orderId -> sio valid', () {
      expect(PesapalOrderResult.fromMap(const {}).isValid, isFalse);
      expect(
        PesapalOrderResult.fromMap(const {'redirectUrl': 'https://x'}).isValid,
        isFalse,
      );
    });
  });
}