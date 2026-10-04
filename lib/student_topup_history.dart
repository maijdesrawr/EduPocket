import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'app_session_service.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home:
        TransactionHistoryScreen(parentId: "123", parentName: "Raizza Ignacio"),
  ));
}

class TransactionHistoryScreen extends StatefulWidget {
  final String parentId;
  final String parentName;

  const TransactionHistoryScreen({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _topups = [];

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'history_view',
        details: const {'history': 'student_topups'},
      ),
    );
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    final url = Uri.parse(
      ApiConfig.url('get_parent_child_topups.php'),
    ).replace(queryParameters: {'parent_id': widget.parentId});
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded["status"] == "success") {
          setState(() {
            _topups = decoded["topups"];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Good Morning",
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 16)),
                          Text('Welcome "${widget.parentName}"',
                              style: const TextStyle(
                                  color: Color(0xFFAC2324),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFFAC2324),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFAC2324),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(74),
                        topRight: Radius.circular(74),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _topups.length,
                        itemBuilder: (context, index) {
                          final txn = _topups[index];
                          return _buildTransactionTile(txn);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTransactionTile(dynamic txn) {
    final String childName = txn["child_name"] ?? "Unknown";
    final String paymentTitle = txn["method"] ?? "Top-up";
    final String dateTime = txn["date_time"] ?? "";
    final double amount = double.tryParse(txn["amount"].toString()) ?? 0.0;
    final bool isPayment = paymentTitle.toLowerCase().contains("payment");

    final amountColor = isPayment ? Colors.red : Colors.green;
    final amountSign = isPayment ? "-" : "+";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withAlpha(30), blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(childName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text("$paymentTitle • $dateTime",
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("$amountSign₱${amount.toStringAsFixed(2)}",
                  style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 2),
              Text(txn["status"] ?? "Completed",
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
