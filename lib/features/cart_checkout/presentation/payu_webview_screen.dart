import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/env_config.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/payment_types.dart';

/// Android / iOS in-app WebView payment screen for PayU Hosted Checkout.
///
/// Features:
/// - Single-load per payment session (no lifecycle reloads).
/// - Enabled JavaScript and DOM storage.
/// - Custom mobile Chrome User-Agent.
/// - Handoff for UPI intent URLs (`upi://`, `paytmmp://`, `gpay://`, `phonepe://`).
/// - Terminal callback redirect detection for success, failure, and cancellation.
class PayUWebViewScreen extends StatefulWidget {
  final String transactionId;

  const PayUWebViewScreen({super.key, required this.transactionId});

  static Future<PaymentResult?> start(BuildContext context, String transactionId) {
    return Navigator.of(context).push<PaymentResult>(
      MaterialPageRoute(
        builder: (_) => PayUWebViewScreen(transactionId: transactionId),
      ),
    );
  }

  @override
  State<PayUWebViewScreen> createState() => _PayUWebViewScreenState();
}

class _PayUWebViewScreenState extends State<PayUWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasTerminated = false;

  @override
  void initState() {
    super.initState();
    final redirectUrl = '${EnvConfig.baseUrl}/api/payment/redirect?transactionId=${widget.transactionId}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
            _checkCallbackUrl(url);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _checkCallbackUrl(url);
          },
          onNavigationRequest: (NavigationRequest request) async {
            final url = request.url;
            final uri = Uri.parse(url);

            // Handle UPI / External PSP app intent schemes
            if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'about') {
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else if (url.startsWith('intent://')) {
                  // Extract browser_fallback_url parameter if target native app is not installed
                  final fallbackMatch = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
                  if (fallbackMatch != null) {
                    final fallbackUrl = Uri.decodeFull(fallbackMatch.group(1)!);
                    final fallbackUri = Uri.tryParse(fallbackUrl);
                    if (fallbackUri != null && await canLaunchUrl(fallbackUri)) {
                      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
                    }
                  }
                } else {
                  await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
                }
              } catch (e) {
                debugPrint('[PayUWebView] Intent launch error for $url: $e');
              }
              return NavigationDecision.prevent;
            }

            if (_checkCallbackUrl(url)) {
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            // Ignore transient ERR_BLOCKED_BY_ORB or subresource network warnings
            debugPrint('[PayUWebView] WebResourceError (${error.errorCode}): ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(redirectUrl));
  }

  bool _checkCallbackUrl(String url) {
    if (_hasTerminated) return true;

    final lower = url.toLowerCase();
    if (lower.contains('payment_status=success') || lower.contains('/api/payment/callback/success')) {
      _finishWithResult(PaymentOutcome.success);
      return true;
    }
    if (lower.contains('payment_status=cancelled') || lower.contains('status=cancelled')) {
      _finishWithResult(PaymentOutcome.cancelled);
      return true;
    }
    if (lower.contains('payment_status=failed') || lower.contains('/api/payment/callback/failure')) {
      _finishWithResult(PaymentOutcome.failed);
      return true;
    }
    return false;
  }

  void _finishWithResult(PaymentOutcome outcome) {
    if (_hasTerminated) return;
    _hasTerminated = true;
    if (mounted) {
      Navigator.of(context).pop(
        PaymentResult(outcome: outcome, transactionId: widget.transactionId),
      );
    }
  }

  Future<void> _handleBackPress() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      _finishWithResult(PaymentOutcome.cancelled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PayU Checkout'),
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _handleBackPress,
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
      ),
    );
  }
}
