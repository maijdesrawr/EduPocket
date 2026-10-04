import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rawr/pos_payment_model.dart';
import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'receipt_screen.dart';

class CashierTransactionHistoryScreen extends StatefulWidget {
  final String cashierId;
  final String cashierName;
  final bool showAppBar;

  const CashierTransactionHistoryScreen({
    super.key,
    required this.cashierId,
    required this.cashierName,
    this.showAppBar = true,
  });

  @override
  State<CashierTransactionHistoryScreen> createState() =>
      _CashierTransactionHistoryScreenState();
}

class _CashierTransactionHistoryScreenState
    extends State<CashierTransactionHistoryScreen> {
  late Map<String, List<PaymentTransaction>> _groupedTransactions = {};
  late List<String> _groupKeys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'history_view',
        details: const {'history': 'cashier_transactions'},
      ),
    );
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      final transactions = await _loadTransactions();

      setState(() {
        _groupedTransactions = _groupByDate(transactions);
        _groupKeys = _groupedTransactions.keys.toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshTransactions() async {
    await _fetchTransactions();
  }

  Future<List<PaymentTransaction>> _loadTransactions() async {
    final cashierId = widget.cashierId.trim();

    final primary = await _tryFetchList(
      ApiConfig.url('get_cashier_transactions.php?cashier_id=$cashierId'),
      listField: 'transactions',
    );

    if (primary != null) {
      return _normalizeTransactions(primary, cashierId);
    }

    return <PaymentTransaction>[];
  }

  Future<List<dynamic>?> _tryFetchList(
    String url, {
    required String listField,
  }) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    if (decoded['status'] != 'success') return <dynamic>[];

    final raw = decoded[listField];
    if (raw is List) return raw;
    if (raw is Map) return raw.values.toList();
    return null;
  }

  List<PaymentTransaction> _normalizeTransactions(
    List<dynamic> rawList,
    String cashierId,
  ) {
    final byId = <String, PaymentTransaction>{};

    for (final raw in rawList) {
      if (raw is! Map) continue;
      final map = raw.cast<dynamic, dynamic>();

      final id = map['id']?.toString() ?? '';
      final recipientName = map['recipientName']?.toString() ?? '';
      final recipientNumber = map['recipientNumber']?.toString() ?? '';
      final paymentTitle = map['paymentTitle']?.toString() ?? '';
      final timestampRaw = map['timestamp']?.toString() ?? '';
      final parsedTimestamp = DateTime.tryParse(timestampRaw);
      final amountRaw = map['amount'];
      final amount = amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw?.toString() ?? '');

      if (id.isEmpty ||
          recipientName.isEmpty ||
          paymentTitle.isEmpty ||
          parsedTimestamp == null ||
          amount == null) {
        continue;
      }

      byId[id] = PaymentTransaction(
        id: id,
        recipientName: recipientName,
        recipientNumber: recipientNumber,
        paymentTitle: paymentTitle,
        amount: amount,
        timestamp: parsedTimestamp,
        isCompleted: map['isCompleted'] == true,
      );
    }

    final txns = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return txns;
  }

  Map<String, List<PaymentTransaction>> _groupByDate(
      List<PaymentTransaction> txns) {
    Map<String, List<PaymentTransaction>> grouped = {};
    for (var txn in txns) {
      String key = _getDateLabel(txn.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(txn);
    }
    return grouped;
  }

  String _getDateLabel(DateTime date) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime txnDate = DateTime(date.year, date.month, date.day);

    if (txnDate == today) return 'Today';

    DateTime yesterday = today.subtract(const Duration(days: 1));
    if (txnDate == yesterday) return 'Yesterday';

    return _getMonthName(date.month);
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: null,
      centerTitle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.showAppBar ? _buildAppBar() : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good Morning',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Welcome "${widget.cashierName}"',
                            style: const TextStyle(
                              color: Color(0xFFAC2324),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      ProfileAvatar(
                        role: 'cashier',
                        userId: widget.cashierId,
                        radius: 30,
                        fallbackIcon: Icons.person,
                        iconColor: Colors.white,
                        backgroundColor: const Color(0xFFAC2324),
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
                        topLeft: Radius.circular(74.0),
                        topRight: Radius.circular(74.0),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(74.0),
                        topRight: Radius.circular(74.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(24.0, 0, 24.0, 8.0),
                              child: Text(
                                'Transaction History',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _refreshTransactions,
                                color: const Color(0xFFAC2324),
                                backgroundColor: Colors.white,
                                child: CustomScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  slivers: [
                                    if (_groupKeys.isEmpty)
                                      const SliverFillRemaining(
                                        hasScrollBody: false,
                                        child: Center(
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 24.0),
                                            child: Text(
                                              'No transactions yet',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ..._groupKeys.expand((key) {
                                      final transactions =
                                          _groupedTransactions[key]!;
                                      return [
                                        SliverPersistentHeader(
                                          pinned: true,
                                          delegate: _StickyHeaderDelegate(
                                            child: Container(
                                              height: 40.0,
                                              color: const Color(0xFFAC2324),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 24.0),
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                key,
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ),
                                        SliverPadding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24.0),
                                          sliver: SliverList(
                                            delegate:
                                                SliverChildBuilderDelegate(
                                              (context, index) {
                                                final isFirstItem = index == 0;
                                                return Padding(
                                                  padding: EdgeInsets.only(
                                                      top: isFirstItem
                                                          ? 8.0
                                                          : 0.0),
                                                  child: _buildTransactionTile(
                                                      transactions[index]),
                                                );
                                              },
                                              childCount: transactions.length,
                                            ),
                                          ),
                                        ),
                                        const SliverToBoxAdapter(
                                            child: SizedBox(height: 16)),
                                      ];
                                    }),
                                    const SliverToBoxAdapter(
                                        child: SizedBox(height: 24)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTransactionTile(PaymentTransaction txn) {
    String formatDate(DateTime dt) {
      final String date =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final int hour =
          dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final String time =
          '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      return '$date \u2022 $time';
    }

    final amountColor = txn.amount < 0 ? Colors.red : Colors.green;
    final amountSign = txn.amount < 0 ? '-' : '+';
    final transactionId = int.tryParse(txn.id) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: const Color(0x22000000),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: transactionId > 0
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptScreen(
                        transactionId: transactionId,
                        viewerRole: 'cashier',
                        viewerId: widget.cashierId,
                      ),
                    ),
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txn.recipientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${txn.paymentTitle} \u2022 ${formatDate(txn.timestamp)}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$amountSign\u20B1${txn.amount.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          transactionId > 0 ? 'View Receipt' : 'Completed',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                        if (transactionId > 0) ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.receipt_long_outlined,
                            color: Color(0xFFAC2324),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyHeaderDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => 40.0;

  @override
  double get minExtent => 40.0;

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
