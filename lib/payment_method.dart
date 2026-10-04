import 'dart:async';
import 'package:flutter/material.dart';
import 'payment_failure_view.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'payment.dart';
import 'receipt_screen.dart';
import 'app_session_service.dart';

class PaymentMethodPage extends StatefulWidget {
  final http.Client? client;
  final Future<bool> Function(Uri)? launchCheckout;
  final String userName;
  final String userId;
  final String selectedChildId;
  final String selectedChildName;
  final double amount;

  const PaymentMethodPage({
    super.key,
    this.client,
    this.launchCheckout,
    required this.userName,
    required this.userId,
    required this.selectedChildId,
    required this.selectedChildName,
    required this.amount,
  });

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage>
    with WidgetsBindingObserver {
  late final http.Client _client;
  bool _busy = false;
  String? _failureMessage;
  Timer? _statusTimer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    WidgetsBinding.instance.addObserver(this);
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_foreground && _checkoutId != null && _failureMessage == null) {
        unawaited(_checkPayment(silent: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _failureMessage == null) {
      unawaited(_checkPayment(silent: true));
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    if (widget.client == null) _client.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _openCheckout(Uri uri) =>
      widget.launchCheckout?.call(uri) ??
      launchUrl(uri, mode: LaunchMode.externalApplication);

  void _retryPayment() {
    setState(() {
      _failureMessage = null;
      _checkoutId = null;
      _checkoutUrl = null;
    });
  }

  String? _checkoutId;
  Uri? _checkoutUrl;

  String get userName => widget.userName;
  String get userId => widget.userId;
  String get selectedChildId => widget.selectedChildId;
  String get selectedChildName => widget.selectedChildName;
  double get amount => widget.amount;

  Future<void> _checkPayment({bool silent = false}) async {
    if (_busy || _checkoutId == null) return;

    setState(() => _busy = true);

    try {
      final response = await _client.post(
        Uri.parse(ApiConfig.url('checkout_status.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'checkout_id': _checkoutId!,
        },
      ).timeout(const Duration(seconds: 35));

      if (await AppSessionService.instance.handleResponse(response) ||
          !mounted) {
        return;
      }

      final data = jsonDecode(response.body);
      final transactionId = int.tryParse('${data['transaction_id']}') ?? 0;

      if (data['status'] == 'success' && transactionId > 0) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(
              transactionId: transactionId,
              viewerRole: 'parent',
              viewerId: userId,
            ),
          ),
        );
      } else if (['failed', 'expired', 'cancelled'].contains(data['status'])) {
        setState(
          () => _failureMessage = data['message']?.toString() ??
              'Payment failed. Please try again.',
        );
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message'] ?? 'Payment is awaiting confirmation.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to check payment. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _goToWallet(BuildContext context, String method) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WalletPage(
          userName: userName,
          userId: userId,
          selectedChildId: selectedChildId,
          selectedChildName: selectedChildName,
          amount: amount,
          paymentMethod: method,
        ),
      ),
    );
  }

  Future<void> _startPayMongo(
    BuildContext context,
    String method,
  ) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final response = await _client.post(
        Uri.parse(
          ApiConfig.url('create_paymongo_checkout.php'),
        ),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'amount': amount.toString(),
          'method': method,
          'parent_id': userId,
          'child_id': selectedChildId,
        },
      );

      if (await AppSessionService.instance.handleResponse(response)) return;
      if (!context.mounted) return;

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        final checkoutUrl = data['checkout_url'];

        setState(() {
          _checkoutId = data['checkout_id'].toString();
          _checkoutUrl = Uri.parse(checkoutUrl);
        });

        final uri = Uri.parse(checkoutUrl);

        final opened = await _openCheckout(uri);

        if (!context.mounted) return;

        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open payment page'),
            ),
          );
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message'] ?? 'Payment creation failed',
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ------------------------------------------------------------
  // PAYMENT METHOD CARD UI
  // ------------------------------------------------------------

  Widget _paymentMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.grey,
                  size: 17,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_failureMessage != null) {
      return PaymentFailureView(
        message: _failureMessage!,
        onRetry: _retryPayment,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Payment Method',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --------------------------------------------------
              // AMOUNT CARD
              // --------------------------------------------------

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.red,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Amount to Add',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '₱${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // --------------------------------------------------
              // SECTION TITLE
              // --------------------------------------------------

              const Text(
                'Choose Payment Method',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Select how you would like to add funds to the student account.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 18),

              // --------------------------------------------------
              // LOADING
              // --------------------------------------------------

              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.red,
                    ),
                  ),
                ),

              // --------------------------------------------------
              // BANK TRANSFER
              // --------------------------------------------------

              // --------------------------------------------------
              // GCASH
              // --------------------------------------------------

              _paymentMethodCard(
                icon: Icons.phone_android_rounded,
                title: 'GCash',
                subtitle: 'Pay securely using your GCash account',
                iconColor: Colors.blue,
                enabled: !_busy && _checkoutId == null,
                onTap: () => _startPayMongo(context, 'GCash'),
              ),

              const SizedBox(height: 14),

              // --------------------------------------------------
              // MAYA
              // --------------------------------------------------

              _paymentMethodCard(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Maya',
                subtitle: 'Pay securely using your Maya account',
                iconColor: Colors.green,
                enabled: !_busy && _checkoutId == null,
                onTap: () => _startPayMongo(context, 'Maya'),
              ),

              // --------------------------------------------------
              // CHECKOUT STATUS
              // --------------------------------------------------

              if (_checkoutId != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.payment_rounded,
                            color: Colors.red,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Payment in Progress',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Finish your payment in the browser, then return here to check the payment status.',
                        style: TextStyle(
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _checkoutUrl == null
                              ? null
                              : () => _openCheckout(
                                    _checkoutUrl!,
                                  ),
                          icon: const Icon(
                            Icons.open_in_new,
                          ),
                          label: const Text(
                            'Reopen Payment Page',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(
                              color: Colors.red,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _checkPayment,
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                          ),
                          label: const Text(
                            'Check Payment Status',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
