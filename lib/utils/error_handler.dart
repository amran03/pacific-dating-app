import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hubadilisha exceptions zozote (Supabase, network, socket, timeout) kuwa
/// ujumbe mfupi, rafiki WA KISWAHILI/KIINGEREZA â€” kamwe haionyeshi e.toString() au ujumbe wa database kwa mtumiaji.

class ClientException implements Exception {
  final String message;

  const ClientException(this.message);

  @override
  String toString() => message;
}

/// Je, hii ni error ya NETWORK (socket/DNS/timeout/fetch) si ya programu?
///
/// CHANZO KIMOJA cha ukaguzi wa mtandao kwa app yote — zamani orodha hii
/// ilijirudia mara 1+1+1 kwenye connectivity_service, profile_photo_service
/// na auth_errors. Sasa zote hupaiga hapa.
bool isNetworkError(Object e) {
  if (e is SocketException ||
      e is TimeoutException ||
      e is ClientException ||
      e is AuthRetryableFetchException ||
      e is HandshakeException) {
    return true;
  }
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('timeout') ||
      s.contains('failed to fetch') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection terminated') ||
      s.contains('connection') ||
      s.contains('handshakeexception') ||
      s.contains('clientexception') ||
      s.contains('xmlhttprequest error') ||
      s.contains('no route to host') ||
      s.contains('authretryablefetch') ||
      s.contains('network');
}
/// Matumizi:
///   catch (e) {
///     showAppNotification(context, friendlyError(e),
///         type: AppNotificationType.error);
///   }
///
/// Mbichi (toString) huandikwa kwenye [debugPrint] tu (kwa developer).
String friendlyError(Object e) {
  debugPrint('friendlyError <- $e');

  // ---- Network / connectivity (hakuna mawasiliano halisi) ----
  if (isNetworkError(e)) {
    return 'Hakuna mawasiliano. Angalia internet yako kisha jaribu tena.';
  }

  // ---- Supabase ----

  if (e is PostgrestException) {
    // (Network-level Postgrest errors tayari zimefunikwa na isNetworkError
    // hapo juu.) Zingine za DB (RLS, not found, constraint...) ni ujumbe
    // jumla.
    // Zingine za DB (RLS, not found, constraint...) â€” ujumbe jumla.
    return 'Kuna hitilafu, jaribu tena baadaye.';
  }

  if (e is AuthException) {
    // Errors za auth zina ujumbe wazi (invalid login, email taken...).
    return e.message;
  }

  if (e is StorageException) {
    return 'Imeshindikana kupakia. Angalia internet yako kisha jaribu tena.';
  }

  // ---- Fallback: kitu chochote kingine ----
  return 'Kuna hitilafu, jaribu tena baadaye.';
}
