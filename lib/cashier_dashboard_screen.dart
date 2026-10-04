import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:rawr/pos_payment_model.dart';
import 'api_config.dart';
import 'app_session_service.dart';
import 'cashier_topup-buttons.dart';
import 'cashier_transaction_history_screen.dart';
import 'cashier_qr_scanner_screen.dart';
import 'cashier_profile.dart';
import 'profile_avatar.dart';
import 'receipt_screen.dart';

class CashierDashboardScreen extends StatefulWidget {
  final String name;
  final String id;
  final void Function(int index)? onNavigate;

  const CashierDashboardScreen({
    super.key,
    required this.name,
    required this.id,
    this.onNavigate,
  });

  @override
  State<CashierDashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<CashierDashboardScreen> {
  int _selectedIndex = 0;
  List<PaymentTransaction> _recentTransactions = [];
  double _balance = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'dashboard_view',
        details: const {'dashboard': 'cashier'},
      ),
    );
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url('get_cashier_dashboard.php?cashier_id=${widget.id}'),
        ),
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);

        if (jsonData['status'] == 'success') {
          final List<dynamic> data = jsonData['transactions'];

          setState(() {
            _balance = (jsonData['balance'] is num)
                ? (jsonData['balance'] as num).toDouble()
                : double.tryParse(jsonData['balance'].toString()) ?? 0.0;

            _recentTransactions = data.map((txn) {
              return PaymentTransaction(
                id: txn['id'].toString(),
                recipientName: txn['recipientName'].toString(),
                recipientNumber: txn['recipientNumber'].toString(),
                paymentTitle: txn['paymentTitle'].toString(),
                amount: txn['amount'] is num
                    ? (txn['amount'] as num).toDouble()
                    : double.tryParse(txn['amount'].toString()) ?? 0.0,
                timestamp: DateTime.parse(txn['timestamp'].toString()),
                isCompleted: txn['isCompleted'] ?? true,
              );
            }).toList();

            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
          debugPrint('Server error: ${jsonData['message']}');
        }
      } else {
        setState(() => _isLoading = false);
        debugPrint('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Fetch error: $e');
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      _fetchTransactions();
    }
    widget.onNavigate?.call(index);
  }

  Future<void> _openStudentTopUpPrompt() async {
    final controller = TextEditingController();
    final studentNumber = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Student Top-Up'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter student number',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    final trimmed = (studentNumber ?? '').trim();
    if (trimmed.isEmpty || !mounted) return;

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => CashierTopUpScreen(
          studentNumber: trimmed,
          cashierId: widget.id,
          onNavigate: _onNavTap,
        ),
      ),
    );

    if (result is Map && result['navIndex'] is int && mounted) {
      _onNavTap(result['navIndex'] as int);
      return;
    }

    if (result == true && mounted) {
      await _fetchTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.white,
      appBar: _selectedIndex == 3 ? null : _buildAppBar(),
      body: _selectedIndex == 0
          ? _buildMainDashboard()
          : _selectedIndex == 1
              ? CashierTransactionHistoryScreen(
                  cashierId: widget.id,
                  cashierName: widget.name,
                  showAppBar: false,
                )
              : _selectedIndex == 2
                  ? QRScannerScreen(
                      cashierId: widget.id,
                      showAppBar: false,
                      onNavigate: _onNavTap,
                    )
                  : CashierProfileScreen(
                      cashierId: widget.id,
                      cashierName: widget.name,
                    ),
      bottomNavigationBar: Container(
        color: const Color(0xFFAC2324),
        child: _buildBottomNav(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Image.asset(
        'assets/icons/logo-red.png',
        height: 60,
      ),
      centerTitle: true,
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(46.0),
          topRight: Radius.circular(46.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(
            iconRed: 'assets/icons/home-red.png',
            iconWhite: 'assets/icons/home-white.png',
            index: 0,
          ),
          _navItem(
            iconRed: 'assets/icons/history-red.png',
            iconWhite: 'assets/icons/history-white.png',
            index: 1,
          ),
          _navItem(
            iconRed: 'assets/icons/qr-red.png',
            iconWhite: 'assets/icons/qr-white.png',
            index: 2,
          ),
          _profileNavItem(index: 3),
        ],
      ),
    );
  }

  Widget _navItem({
    required String iconRed,
    required String iconWhite,
    required int index,
  }) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onNavTap(index),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFAC2324) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(12),
        child: Image.asset(isSelected ? iconWhite : iconRed),
      ),
    );
  }

  Widget _profileNavItem({required int index}) {
    final bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onNavTap(index),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFAC2324) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.person_outline,
          color: isSelected ? Colors.white : const Color(0xFFAC2324),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildMainDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    'Welcome "${widget.name}"',
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
                userId: widget.id,
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
                padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBalanceBox(),
                    const SizedBox(height: 20),
                    _buildQuickActionsSection(context),
                    const SizedBox(height: 20),
                    _buildRecentTransactionsHeader(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : RefreshIndicator(
                              color: Colors.white,
                              backgroundColor: const Color(0xFFAC2324),
                              onRefresh: _fetchTransactions,
                              child: _recentTransactions.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: const [
                                        SizedBox(height: 100),
                                        Center(
                                          child: Text(
                                            'No transactions yet',
                                            style:
                                                TextStyle(color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding:
                                          const EdgeInsets.only(bottom: 24.0),
                                      itemCount: _recentTransactions.length,
                                      itemBuilder: (context, index) {
                                        return _transactionTile(
                                            _recentTransactions[index]);
                                      },
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
    );
  }

  Widget _buildBalanceBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.name} account current balance:',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '\u20B1${_balance.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFAC2324)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _quickActionButton(
                'QR Scanner',
                Icons.qr_code_scanner,
                () => _onNavTap(2),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _quickActionButton(
                'Transaction History',
                Icons.history,
                () => _onNavTap(1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickActionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        height: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withAlpha(26),
              spreadRadius: 1,
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFAC2324), size: 20),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactionsHeader() {
    return const Text('Recent Transaction Activity',
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white));
  }

  Widget _transactionTile(PaymentTransaction txn) {
    String formatDate(DateTime dt) {
      final String date =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final int hour =
          dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final String time =
          '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
      return '$date \u2022 $time';
    }

    final transactionId = int.tryParse(txn.id) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
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
                        viewerId: widget.id,
                      ),
                    ),
                  )
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withAlpha(20),
                  spreadRadius: 1,
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(txn.recipientName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        txn.paymentTitle,
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatDate(txn.timestamp),
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        '${txn.amount < 0 ? '-' : '+'}\u20B1${txn.amount.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                            color: txn.amount < 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(transactionId > 0 ? 'View Receipt' : 'Completed',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12)),
                      if (transactionId > 0) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.receipt_long_outlined,
                            size: 16, color: Color(0xFFAC2324)),
                      ],
                    ]),
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
