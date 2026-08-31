import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/payment_types.dart';

/// Screen for displaying Razorpay Checkout in a WebView container on mobile devices.
/// Receives orderId, keyId, amount, currency, and transactionId from server.
class RazorpayCheckoutScreen extends StatefulWidget {
  final String orderId;
  final String keyId;
  final int amount;
  final String currency;
  final String transactionId;
  final String customerName;
  final String customerEmail;
  final String customerMobile;

  const RazorpayCheckoutScreen({
    super.key,
    required this.orderId,
    required this.keyId,
    required this.amount,
    required this.currency,
    required this.transactionId,
    required this.customerName,
    required this.customerEmail,
    required this.customerMobile,
  });

  static Future<Map<String, dynamic>?> start(
    BuildContext context, {
    required String orderId,
    required String keyId,
    required int amount,
    required String currency,
    required String transactionId,
    required String customerName,
    required String customerEmail,
    required String customerMobile,
  }) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => RazorpayCheckoutScreen(
          orderId: orderId,
          keyId: keyId,
          amount: amount,
          currency: currency,
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerMobile: customerMobile,
        ),
      ),
    );
  }

  @override
  State<RazorpayCheckoutScreen> createState() => _RazorpayCheckoutScreenState();
}

class _RazorpayCheckoutScreenState extends State<RazorpayCheckoutScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
    }
  }

  void _initWebView() {
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Razorpay Checkout</title>
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
</head>
<body style="background-color: #F4F6F8; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; font-family: sans-serif;">
  <div style="text-align: center;">
    <h3 style="color: #2D6A4F;">Initializing Razorpay Payment...</h3>
    <p style="color: #6C757D;">Please do not close this window.</p>
  </div>
  <script>
    var options = {
      "key": "${widget.keyId}",
      "amount": ${widget.amount},
      "currency": "${widget.currency}",
      "name": "VioleafyCross",
      "description": "Order Payment ${widget.transactionId}",
      "image": "https://violeafy.com/assets/logo.png",
      "order_id": "${widget.orderId}",
      "prefill": {
        "name": "${widget.customerName}",
        "email": "${widget.customerEmail}",
        "contact": "${widget.customerMobile}"
      },
      "theme": {
        "color": "#2D6A4F"
      },
      "handler": function (response) {
        window.location.href = "https://violeafy.local/payment_callback?status=success" +
          "&razorpay_payment_id=" + encodeURIComponent(response.razorpay_payment_id) +
          "&razorpay_order_id=" + encodeURIComponent(response.razorpay_order_id) +
          "&razorpay_signature=" + encodeURIComponent(response.razorpay_signature);
      },
      "modal": {
        "ondismiss": function() {
          window.location.href = "https://violeafy.local/payment_callback?status=cancelled";
        }
      }
    };
    var rzp1 = new Razorpay(options);
    rzp1.on('payment.failed', function (response){
      window.location.href = "https://violeafy.local/payment_callback?status=failed" +
        "&code=" + encodeURIComponent(response.error.code) +
        "&description=" + encodeURIComponent(response.error.description);
    });
    window.onload = function() {
      rzp1.open();
    };
  </script>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF4F6F8))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith('https://violeafy.local/payment_callback')) {
              final uri = Uri.parse(request.url);
              final status = uri.queryParameters['status'];

              if (status == 'success') {
                Navigator.of(context).pop({
                  'outcome': PaymentOutcome.success,
                  'razorpay_payment_id': uri.queryParameters['razorpay_payment_id'],
                  'razorpay_order_id': uri.queryParameters['razorpay_order_id'],
                  'razorpay_signature': uri.queryParameters['razorpay_signature'],
                });
              } else if (status == 'cancelled') {
                Navigator.of(context).pop({'outcome': PaymentOutcome.cancelled});
              } else {
                Navigator.of(context).pop({'outcome': PaymentOutcome.failed});
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(htmlContent, baseUrl: 'https://checkout.razorpay.com');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: const Text('Razorpay Secure Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop({'outcome': PaymentOutcome.cancelled}),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            ),
        ],
      ),
    );
  }
}
