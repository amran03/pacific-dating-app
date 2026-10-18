import 'package:flutter/material.dart';

/// Skrini ya katikati inayoonyeshwa data haijapakia kwa sababu ya offline.
///
/// Matumizi kwenye StreamBuilder/FutureBuilder:
///   if (snapshot.hasError || !online) {
///     return NoInternetView(onRetry: () => _reload());
///   }
class NoInternetView extends StatelessWidget {
  final VoidCallback? onRetry;
  final String message;
  const NoInternetView({
    super.key,
    this.onRetry,
    this.message = 'Hakuna internet. Unganisha mtandao kisha jaribu tena.',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 56,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Hakuna Internet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Jaribu tena',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
