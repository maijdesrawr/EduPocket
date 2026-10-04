import 'package:flutter/material.dart';
import 'receipt_screen.dart';

class ReceiptAction extends StatelessWidget {
  final int transactionId;
  final String viewerRole;
  final String viewerId;
  const ReceiptAction(
      {super.key,
      required this.transactionId,
      required this.viewerRole,
      required this.viewerId});

  @override
  Widget build(BuildContext context) {
    if (transactionId <= 0) return const SizedBox.shrink();
    return TextButton.icon(
      style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFAC2324),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(vertical: 4)),
      onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ReceiptScreen(
                  transactionId: transactionId,
                  viewerRole: viewerRole,
                  viewerId: viewerId))),
      icon: const Icon(Icons.receipt_long_outlined, size: 13),
      label: const Text('View Receipt'),
    );
  }
}
