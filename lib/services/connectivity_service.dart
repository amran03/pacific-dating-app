import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pacific_dating_app/utils/error_handler.dart';

/// Hudhibiti upatikanaji wa mtandao (online/offline) kwa app nzima.
///
/// Stream ya [isOnline]:
///  - `true` â€” kuna mtandao (data/WiFi) NA Supabase inafikika (ping nyepesi).
///  - `false` â€” hakuna mtandao au Supabase haifikiki.
///
/// Matumizi kwenye UI (banner, skrini za "No Internet"):
///   StreamBuilder kwa online/offline stream:
///     stream: ConnectivityService.instance.isOnline,
///     ...
///   );
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final _connectivity = Connectivity();
  final _checker = InternetConnection();

  /// Controller ya stream ya online/offline. Anaanza online=true (tunajaribu
  /// mara moja kwa [start]) ili UI isisubiri kabla ya kuonyesha data.
  final _onlineController = StreamController<bool>.broadcast();
  Stream<bool> get isOnline => _onlineController.stream;

  bool _lastKnown = true;
  bool get isCurrentlyOnline => _lastKnown;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _started = false;

  /// Anza kusikiliza mabadiliko ya mtandao. Salama kuitwa mara moja tu
  /// (k.m. kwenye main() baada ya Supabase ku-initialize).
  void start() {
    if (_started) return;
    _started = true;

    _connSub = _connectivity.onConnectivityChanged.listen((results) async {
      final hasNetwork =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (!hasNetwork) {
        _emit(false);
      } else {
        // Kuna interface ya mtandao â€” thibitisha kwa ping + Supabase.
        await _recheck();
      }
    });

    // Hakiki mara moja mwanzoni.
    _recheck();
  }

  /// Ping halisi (internet + Supabase health). Salama kuitika kwa "Jaribu tena".
  Future<void> _recheck() async {
    final ok = await _testConnection();
    _emit(ok);
  }

  /// Ruhusu UI (k.m. kitufe "Jaribu tena") kusubiri upya mara moja.
  Future<bool> refresh() async {
    final ok = await _testConnection();
    _emit(ok);
    return ok;
  }

  void _emit(bool value) {
    if (_lastKnown == value) return;
    _lastKnown = value;
    if (!_onlineController.isClosed) _onlineController.add(value);
  }

  /// Hufanya ping mbili: (1) internet halisi, (2) Supabase (HEAD nyepesi).
  /// Ikiwa internet ipo lakini Supabase inashindikana -> offline (=true UX:
  /// user haoni data mbichi ya error, anaona banner ya "hakuna mawasiliano").
  Future<bool> _testConnection() async {
    try {
      final hasInternet = await _checker.hasInternetAccess
          .timeout(const Duration(seconds: 6));
      if (!hasInternet) return false;

      // Ping Supabase â€” thibitisha backend inafikika (si WiFi tu).
      try {
        await Supabase.instance.client
            .from('users')
            .select('uid')
            .limit(1)
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        if (_isNetworkLevel(e)) {
          debugPrint('Supabase unreachable (network): $e');
          return false;
        }
        // Server reachable (app-level error, e.g. RLS/permission) - still ONLINE.
        debugPrint('Supabase reachable but returned app-level error: $e');
        return true;
      }
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (e) {
      debugPrint('Connection test error: $e');
      return false;
    }
  }

  /// Je, hii ni error ya NETWORK (socket/DNS/timeout/fetch) si ya programu?
  /// Ukaguzi: error_handler.isNetworkError — chanzo kimoja app yote
  /// (zamani orodha hii ilijirudia hapa, profile_photo_service na
  /// error_handler — 1+1+1; sasa ni 3+2=5).
  bool _isNetworkLevel(Object e) => isNetworkError(e);

  void dispose() {
    _connSub?.cancel();
    _onlineController.close();
    _started = false;
  }
}
