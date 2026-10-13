import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/services/pesapal_service.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

/// Payment stages shown to the user.
enum _PaymentStage { loading, paying, confirming, success, failed, unknown }

/// Screen for paying through PesaPal in a WebView.
///
/// Flow:
///   1. `create-pesapal-order` (Edge Function) returns redirectUrl + orderId.
///   2. This screen opens the redirectUrl in a WebView -> the user pays.
///   3. PesaPal redirects the user to our callback_url, which contains
///      "pesapal-return" -> we start waiting for the actual payment status.
///   4. The status is read from the "transactions" table (Realtime; if
///      Realtime is unavailable -> polling every 3 seconds, 20 times).
///   5. `Navigator.pop(context, true | false | null)`:
///        true  = COMPLETED (coins were credited)
///        false = FAILED
///        null  = the user closed it / not confirmed yet
class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({
    super.key,
    required this.redirectUrl,
    required this.orderId,
  });

  /// URL ya malipo kutoka PesaPal (SubmitOrderRequest -> redirect_url).
  final String redirectUrl;

  /// Order id yetu (`PACIFIC-<uid>-<timestamp>`) - primary key ya transactions.
  final String orderId;

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;

  final PesapalService _pesapal = PesapalService.instance;

  _PaymentStage _stage = _PaymentStage.loading;
  String _message = 'Opening PesaPal...';
  int _progress = 0;

  bool _returnDetected = false;
  bool _resolved = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            _handleUrl(url);
            if (mounted && _stage == _PaymentStage.loading) {
              setState(() {
                _stage = _PaymentStage.paying;
                _message = 'Complete your payment';
              });
            }
          },
          onPageFinished: (url) => _handleUrl(url),
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _handleUrl(url);
          },
          onWebResourceError: (error) {
            // PesaPal uses many redirects; sub-resource errors
            // (e.g. images) should not block the user.
            if (error.isForMainFrame == true &&
                mounted &&
                !_returnDetected &&
                _stage == _PaymentStage.loading) {
              setState(() {
                _stage = _PaymentStage.unknown;
                _message = 'Could not open the payment page. '
                    'Check your internet connection and try again.';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));

    // Safety: if the callback never happens (e.g. the browser was closed),
    // check the payment status after 90 seconds before releasing the screen.
    _watchdog = Timer(const Duration(seconds: 90), () {
      if (!_returnDetected) _confirmPayment();
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  /// Detect when PesaPal sends us back to our callback_url.
  void _handleUrl(String url) {
    if (_returnDetected) return;
    if (!url.contains(PesapalService.returnUrlMarker)) return;

    _returnDetected = true;
    _watchdog?.cancel();
    _confirmPayment();
  }

  /// Wait for the real payment status in the "transactions" table.
  ///
  /// Realtime is used when available (faster); if unavailable, we poll
  /// every 3 seconds (20 times) as described.
  Future<void> _confirmPayment() async {
    if (_resolved) return;
    if (mounted) {
      setState(() {
        _stage = _PaymentStage.confirming;
        _message = 'Confirming your payment...';
      });
    }

    PesapalStatus status;
    try {
      // Realtime is the fast path; polling (3s x 20) is the fallback.
      status = await _pesapal.waitForFinalStatus(
        widget.orderId,
        realtimeTimeout: const Duration(seconds: 45),
      );
    } catch (_) {
      status = PesapalStatus.unknown;
    }

    if (!mounted) return;

    switch (status) {
      case PesapalStatus.completed:
        _finish(
          _PaymentStage.success,
          true,
          'Payment successful. Your coins have been added.',
        );
      case PesapalStatus.failed:
        _finish(
          _PaymentStage.failed,
          false,
          'Payment failed. No coins were added.',
        );
      case PesapalStatus.pending:
      case PesapalStatus.unknown:
        _finish(
          _PaymentStage.unknown,
          null,
          'We could not confirm your payment yet. If money was deducted, '
              'your coins will be added automatically in a moment - please '
              'check "Buy Coins" again shortly.',
        );
    }
  }

  /// Finish the flow: show the message, then return the result to the previous screen.
  void _finish(_PaymentStage stage, bool? result, String message) {
    if (_resolved) return;
    setState(() {
      _resolved = true;
      _stage = stage;
      _message = message;
    });

    // Brief delay so the user sees the message before going back.
    Timer(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  void _close() {
    _watchdog?.cancel();
    Navigator.of(context).pop(_resultFor(_stage));
  }

  bool? _resultFor(_PaymentStage stage) {
    switch (stage) {
      case _PaymentStage.success:
        return true;
      case _PaymentStage.failed:
        return false;
      case _PaymentStage.loading:
      case _PaymentStage.paying:
      case _PaymentStage.confirming:
      case _PaymentStage.unknown:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showProgress = _progress > 0 && _progress < 100;
    final bool showConfirming = _stage == _PaymentStage.confirming;
    final bool showResult = _stage == _PaymentStage.success ||
        _stage == _PaymentStage.failed ||
        _stage == _PaymentStage.unknown;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: _close,
        ),
        title: const Text(
          'PesaPal Checkout',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        bottom: showProgress
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (showConfirming) _buildStatusOverlay(),
          if (showResult) _buildResultOverlay(),
        ],
      ),
    );
  }

  /// Overlay wakati wa kuthibitisha malipo na PesaPal.
  Widget _buildStatusOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Confirming payment',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// Final display: success / failed / not confirmed.
  Widget _buildResultOverlay() {
    late final IconData icon;
    late final Color color;
    late final String title;

    switch (_stage) {
      case _PaymentStage.success:
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        title = 'Payment successful';
      case _PaymentStage.failed:
        icon = Icons.cancel_rounded;
        color = Colors.red;
        title = 'Payment failed';
      case _PaymentStage.loading:
      case _PaymentStage.paying:
      case _PaymentStage.confirming:
      case _PaymentStage.unknown:
        icon = Icons.info_rounded;
        color = AppColors.primary;
        title = 'Payment not confirmed';
    }

    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 78, color: color),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_resultFor(_stage)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.sm,
                ),
              ),
              child: const Text(
                'Back to app',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}