// Tests za error_handler — chanzo KIMOJA cha ukaguzi wa mtandao (app yote:
// connectivity_service, profile_photo_service, auth_errors zinatumia
// isNetworkError badala ya kujirudia orodha 1+1+1).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pacific_dating_app/utils/error_handler.dart';

void main() {
  group('isNetworkError', () {
    test('SocketException ni network', () {
      expect(isNetworkError(const SocketException('no internet')), isTrue);
    });

    test('TimeoutException ni network', () {
      expect(isNetworkError(TimeoutException('t')), isTrue);
    });

    test('ujumbe wa network string ni network', () {
      expect(
        isNetworkError(Exception('Failed to fetch: connection refused')),
        isTrue,
      );
      expect(
        isNetworkError(Exception('ClientException with SocketException')),
        isTrue,
      );
      expect(
        isNetworkError(AuthRetryableFetchException(message: 'Failed to fetch')),
        isTrue,
      );
    });

    test('hitilafu ya kawaida si network', () {
      expect(isNetworkError(Exception('duplicate key value')), isFalse);
      expect(isNetworkError(ArgumentError('bad')), isFalse);
    });
  });

  group('friendlyError', () {
    test('network -> ujumbe wa mawasiliano (Kiingereza/Swahili rafiki)', () {
      final msg = friendlyError(const SocketException('down'));
      expect(msg.toLowerCase(), contains('mawasiliano'));
    });

    test('PostgrestException ya DB -> ujumbe jumla, si mbichi', () {
      final msg = friendlyError(
        const PostgrestException(message: 'relation does not exist'),
      );
      expect(msg, 'Kuna hitilafu, jaribu tena baadaye.');
    });

    test('AuthException -> ujumbe wake (si jumla)', () {
      final msg = friendlyError(
        const AuthException('Email rate limit exceeded'),
      );
      expect(msg, 'Email rate limit exceeded');
    });
  });
}