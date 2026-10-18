import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/services/connectivity_service.dart';

/// TOAST ya mtandao (si banner ya kudumu).
///
///  - Mtandao ukishapotea: popup nyekundu "Hakuna internet. Unganisha
///    mtandao" inaonekana na KUONDOKA yenyewe chini ya sekunde 5 (4.5s).
///  - Mtandao ukirudi: popup ya kijani "Umerudi online" (~2.5s) halafu
///    inatoweka.
///  - Hakuna UI ya kudumu juu ya app — toast inaonyeshwa TU pale status
///    inapobadilika (transitions), si kila rebuild.
///
/// Matumizi (main.dart): weka kwenye Stack ya MaterialApp.builder —
/// inajenga SizedBox.shrink tu; kazi yake ni kusikiliza na kuonyesha
/// toast kupitia overlay ya app (showAppNotification).
class OfflineToastListener extends StatefulWidget {
  const OfflineToastListener({super.key});

  @override
  State<OfflineToastListener> createState() => _OfflineToastListenerState();
}

class _OfflineToastListenerState extends State<OfflineToastListener> {
  StreamSubscription<bool>? _sub;

  // Onyo wa kutofautisha transition halisi kutoka state ya kwanza.
  bool? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _lastEmitted = ConnectivityService.instance.isCurrentlyOnline;
    _sub = ConnectivityService.instance.isOnline.listen(_onStatus);
  }

  void _onStatus(bool online) {
    if (!mounted) return;
    // State ya kwanza tayari imeanza na start(); tusionyeshi toast ya
    // "hakuna internet" mtumiaji akiwa tayari offline kabla ya app.
    if (_lastEmitted == null || _lastEmitted == online) {
      _lastEmitted = online;
      return;
    }
    _lastEmitted = online;

    if (!online) {
      // Chini ya sekunde 5 — 4.5s halafu overlay inaondoa yenyewe.
      showAppNotification(
        context,
        'Hakuna internet. Unganisha mtandao',
        type: AppNotificationType.error,
        duration: const Duration(milliseconds: 4500),
      );
    } else {
      showAppNotification(
        context,
        'Umerudi online',
        type: AppNotificationType.success,
        duration: const Duration(milliseconds: 2500),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}