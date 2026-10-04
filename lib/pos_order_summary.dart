import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class PosOrderSummaryItem {
  final String name;
  final int qty;
  final double unitPrice;

  const PosOrderSummaryItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  double get subtotal => qty * unitPrice;
}

class PosOrderSummaryScreen extends StatefulWidget {
  final List<PosOrderSummaryItem> items;
  final String canteenId;
  final String apiBaseUrl;
  final VoidCallback? onConfirmPayment;

  const PosOrderSummaryScreen({
    super.key,
    required this.items,
    required this.canteenId,
    this.apiBaseUrl = ApiConfig.baseUrl,
    this.onConfirmPayment,
  });

  @override
  State<PosOrderSummaryScreen> createState() => _PosOrderSummaryScreenState();
}

class _PosOrderSummaryScreenState extends State<PosOrderSummaryScreen> {
  static const Color _brandRed = Color(0xFFC62828);

  int _nextOrderNumber = 1;

  @override
  void initState() {
    super.initState();
    _loadNextOrderNumber();
  }

  Future<void> _loadNextOrderNumber() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${widget.apiBaseUrl}/get_next_order_number.php?canteen_id=${widget.canteenId}',
        ),
      );
      final data = jsonDecode(response.body);
      if (data is Map && data['status'] == 'success') {
        final parsed = int.tryParse(data['next_order_number'].toString());
        if (parsed != null && parsed > 0 && mounted) {
          setState(() {
            _nextOrderNumber = parsed;
          });
        }
      }
    } catch (_) {}
  }

  double _total() {
    var sum = 0.0;
    for (final item in widget.items) {
      sum += item.subtotal;
    }
    return sum;
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F1F1),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(46),
          topRight: Radius.circular(46),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navIcon(context, 'assets/icons/home-red.png', false),
          _navIcon(context, 'assets/icons/history-red.png', false),
          _navIcon(context, 'assets/icons/qr-white.png', true),
        ],
      ),
    );
  }

  Widget _navIcon(BuildContext context, String iconPath, bool selected) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? _brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(12),
        child: Image.asset(iconPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _total();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F1F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F1F1),
        elevation: 0,
        centerTitle: true,
        title: Image.asset('assets/icons/logo-red.png', height: 58),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 6),
              const Text(
                'Order Summary',
                style: TextStyle(
                  color: _brandRed,
                  fontSize: 32 / 1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(48),
                      topRight: Radius.circular(48),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    'Ordered Items',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F1F1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFE4E4E4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Order#${_nextOrderNumber.toString().padLeft(5, '0')}',
                                              style: const TextStyle(
                                                color: Color(0xFF4A4A4A),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (widget.items.isEmpty)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(vertical: 8),
                                                child: Text(
                                                  'No selected items',
                                                  style: TextStyle(
                                                    color: Color(0xFF6A6A6A),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              )
                                            else
                                              ...widget.items.map((item) {
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 34,
                                                        child: Text(
                                                          '${item.qty}x',
                                                          style: const TextStyle(
                                                            color: Color(0xFF4A4A4A),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          item.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            color: Color(0xFF4A4A4A),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        '\u20B1${item.subtotal.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          color: Color(0xFF4A4A4A),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                          ],
                                        ),
                                      ),
                                      const Divider(height: 1, color: Color(0xFFD9D9D9)),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                                        child: Row(
                                          children: [
                                            const Text(
                                              'Total',
                                              style: TextStyle(
                                                color: Color(0xFF4A4A4A),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '\u20B1${total.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Color(0xFF4A4A4A),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: widget.items.isNotEmpty
                                ? (widget.onConfirmPayment ??
                                    () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Confirm payment tapped'),
                                        ),
                                      );
                                    })
                                : null,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFFF1F1F1),
                              disabledBackgroundColor: const Color(0xFFDDDDDD),
                              foregroundColor: _brandRed,
                              disabledForegroundColor: const Color(0xFF9A9A9A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              minimumSize: const Size.fromHeight(46),
                            ),
                            child: const Text(
                              'Confirm Payment',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 108),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(alignment: Alignment.bottomCenter, child: _buildBottomNav(context)),
        ],
      ),
    );
  }
}
