import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'receipt_screen.dart';
import 'topup_receipt_navigation.dart';

class WalletPage extends StatefulWidget {
  final String userName;
  final String userId;
  final String selectedChildId;
  final String selectedChildName;
  final double amount;
  final String paymentMethod;

  const WalletPage({
    super.key,
    required this.userName,
    required this.userId,
    required this.selectedChildId,
    required this.selectedChildName,
    required this.amount,
    required this.paymentMethod,
  });

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  bool loading = false;

  Future<void> _submitTopUp() async {
    if (loading) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Confirm bank transfer'),
              content: Text(
                  'Add PHP ${widget.amount.toStringAsFixed(2)} to ${widget.selectedChildName}?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Confirm')),
              ],
            ));
    if (confirmed != true || !mounted || loading) return;
    setState(() => loading = true);

    final url = Uri.parse(ApiConfig.url('record_topup.php'));

    try {
      final response = await http.post(
        url,
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'parent_id': widget.userId,
          'child_id': widget.selectedChildId,
          'amount': widget.amount.toString(),
          'method': widget.paymentMethod,
        },
      );
      await AppSessionService.instance.handleResponse(response);
      if (!mounted) return;

      setState(() => loading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          final transactionId = topUpTransactionIdFromResponse(data);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Top-up successful! New balance: Php ${data['new_balance']}',
              ),
            ),
          );
          if (transactionId <= 0) {
            Navigator.pop(context, true);
            return;
          }

          final viewReceipt = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Top-up successful'),
              content: const Text(
                'Your official receipt is ready to view or print.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Done'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View receipt'),
                ),
              ],
            ),
          );
          if (!mounted) return;

          if (viewReceipt == true) {
            await Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiptScreen(
                  transactionId: transactionId,
                  viewerRole: 'parent',
                  viewerId: widget.userId,
                ),
              ),
            );
          } else {
            Navigator.pop(context, true);
          }
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: ${data['message']}')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Network error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Page'),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Parent: ${widget.userName}'),
                  Text('Child: ${widget.selectedChildName}'),
                  Text('Amount: Php ${widget.amount.toStringAsFixed(2)}'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _submitTopUp,
                    child: const Text('Confirm Top-Up'),
                  ),
                ],
              ),
      ),
    );
  }
}
