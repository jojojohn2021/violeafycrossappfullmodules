import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/payment_types.dart';

/// Mobile (Android & iOS) WebView checkout screen for Cashfree, PayU, and PhonePe.
/// Supports UPI/external app intent schemes (`upi://`, `phonepe://`, `gpay://`, `intent://`, etc.)
/// and intercepts backend return/callback redirects to trigger authoritative server verification.
class HostedGatewayCheckoutScreen extends StatefulWidget {
  final String title;
  final String providerCode;
  final String transactionId;
  final String? initialUrl;
  final String? initialHtml;
  final String? htmlBaseUrl;

  const HostedGatewayCheckoutScreen({
    super.key,
    required this.title,
    required this.providerCode,
    required this.transactionId,
    this.initialUrl,
    this.initialHtml,
    this.htmlBaseUrl,
  });

  static Future<Map<String, dynamic>?> startCashfree(
    BuildContext context, {
    required String paymentSessionId,
    required String environment,
    required String transactionId,
    required String returnUrl,
  }) {
    final mode = environment.toLowerCase() == 'production' ? 'production' : 'sandbox';
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cashfree Secure Payment</title>
  <script src="https://sdk.cashfree.com/js/v3/cashfree.js"></script>
</head>
<body style="background-color: #F4F6F8; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; font-family: sans-serif;">
  <div style="text-align: center;">
    <h3 style="color: #2D6A4F;">Opening Cashfree Secure Payment...</h3>
    <p style="color: #6C757D;">Please do not close this window.</p>
  </div>
  <script>
    window.onload = function() {
      try {
        var cashfree = Cashfree({ mode: ${jsonEncode(mode)} });
        cashfree.checkout({
          paymentSessionId: ${jsonEncode(paymentSessionId)},
          redirectTarget: "_self"
        });
      } catch (e) {
        window.location.href = "/payment-result?txnid=${Uri.encodeComponent(transactionId)}&payment_status=failed";
      }
    };
  </script>
</body>
</html>
''';
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => HostedGatewayCheckoutScreen(
          title: 'Cashfree Secure Payment',
          providerCode: 'cashfree',
          transactionId: transactionId,
          initialHtml: html,
          htmlBaseUrl: 'https://sdk.cashfree.com',
        ),
      ),
    );
  }

  static Future<Map<String, dynamic>?> startPayU(
    BuildContext context, {
    required String actionUrl,
    required Map<String, String> fields,
    required String transactionId,
  }) {
    final buffer = StringBuffer();
    fields.forEach((key, value) {
      final escapedKey = const HtmlEscape().convert(key);
      final escapedVal = const HtmlEscape().convert(value);
      buffer.writeln('<input type="hidden" name="$escapedKey" value="$escapedVal" />');
    });

    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PayU Secure Payment</title>
</head>
<body style="background-color: #F4F6F8; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; font-family: sans-serif;">
  <div style="text-align: center;">
    <h3 style="color: #2D6A4F;">Redirecting to PayU Secure Payment...</h3>
    <p style="color: #6C757D;">Please wait...</p>
  </div>
  <form id="payuForm" method="POST" action="${const HtmlEscape().convert(actionUrl)}">
    ${buffer.toString()}
  </form>
  <script>window.onload = function() { document.getElementById('payuForm').submit(); };</script>
</body>
</html>
''';
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => HostedGatewayCheckoutScreen(
          title: 'PayU Secure Payment',
          providerCode: 'payu',
          transactionId: transactionId,
          initialHtml: html,
          htmlBaseUrl: actionUrl,
        ),
      ),
    );
  }

  static Future<Map<String, dynamic>?> startPhonePe(
    BuildContext context, {
    required String redirectUrl,
    required String transactionId,
  }) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => HostedGatewayCheckoutScreen(
          title: 'PhonePe Secure Payment',
          providerCode: 'phonepe',
          transactionId: transactionId,
          initialUrl: redirectUrl,
        ),
      ),
    );
  }

  @override
  State<HostedGatewayCheckoutScreen> createState() => _HostedGatewayCheckoutScreenState();
}

class _HostedGatewayCheckoutScreenState extends State<HostedGatewayCheckoutScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
    }
  }

  void _finish(PaymentOutcome outcome) {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop({'outcome': outcome});
  }

  bool _isReturnUrl(String url) {
    return url.contains('/payment-result') ||
        url.contains('/payment_callback') ||
        url.contains('/api/payment/cashfree/return') ||
        url.contains('/api/payment/phonepe/return');
  }

  PaymentOutcome _outcomeFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final st = (uri?.queryParameters['payment_status'] ?? uri?.queryParameters['status'] ?? '').toLowerCase();
    if (st == 'success') return PaymentOutcome.success;
    if (st == 'cancelled') return PaymentOutcome.cancelled;
    if (st == 'failed') return PaymentOutcome.failed;
    // Return URLs without explicit terminal status trigger authoritative S2S verification.
    return PaymentOutcome.pending;
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF4F6F8))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            if (_isReturnUrl(url)) {
              if (mounted) setState(() => _isLoading = true);
              _finish(_outcomeFromUrl(url));
              return NavigationDecision.prevent;
            }

            if (!url.startsWith('http://') && !url.startsWith('https://')) {
              try {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              } catch (e) {
                debugPrint('[HostedGatewayCheckout] External scheme launch error ($url): $e');
              }
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (widget.initialHtml != null) {
      _controller.loadHtmlString(widget.initialHtml!, baseUrl: widget.htmlBaseUrl);
    } else if (widget.initialUrl != null) {
      _controller.loadRequest(Uri.parse(widget.initialUrl!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _finish(PaymentOutcome.cancelled),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primaryGreen),
              ),
          ],
        ),
      ),
    );
  }
}
