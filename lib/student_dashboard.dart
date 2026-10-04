import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'receipt_screen.dart';
import 'student_graphs.dart' as graphs;
import 'student_profile.dart';
import 'student_topups.dart';
import 'student_transfer.dart';

String studentTransactionDisplayLabel(Object? rawType) {
  switch (rawType?.toString().trim().toLowerCase()) {
    case 'transfer-out':
      return 'Fund Transfer';
    case 'transfer-in':
      return 'Fund Received';
    case 'top-up':
      return 'Top-Up';
    case 'payment':
      return 'Payment';
    default:
      final label = rawType?.toString().trim() ?? '';
      return label.isEmpty ? 'Payment' : label;
  }
}

double studentExpenseFromTransactions(
  Iterable<Map<String, dynamic>> transactions,
) {
  return transactions.where((tx) {
    final type = (tx['type'] ?? '').toString().trim().toLowerCase();
    return type == 'payment' || type == 'transfer-out';
  }).fold<double>(
    0,
    (sum, tx) => sum + ((tx['amount'] as num?)?.toDouble() ?? 0),
  );
}

class StudentDashboard extends StatefulWidget {
  final String name;
  final String id;

  const StudentDashboard({super.key, required this.name, required this.id});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _softPink = Color(0xFFF0B8AC);
  static const Color _panelPink = Color(0xFFF2B2A9);
  static const Color _successGreen = Color(0xFF129D37);

  String _selectedFilter = 'Daily';
  List<Map<String, dynamic>> _transactions = [];
  double _totalBalance = 0.0;
  double _totalExpense = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'dashboard_view',
        details: const {'dashboard': 'student'},
      ),
    );
    _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    await Future.wait([
      _fetchSummaryTotals(),
      _fetchTransactions(),
    ]);
  }

  Future<void> _fetchSummaryTotals() async {
    try {
      final summaryResponse = await http.get(
        Uri.parse(
          ApiConfig.url(
            'student_topups.php?student_id=${Uri.encodeQueryComponent(widget.id)}',
          ),
        ),
        headers: AppSessionService.instance.authorizationHeaders,
      );
      if (await AppSessionService.instance.handleResponse(summaryResponse)) {
        return;
      }

      if (summaryResponse.statusCode != 200) return;

      final summary = jsonDecode(summaryResponse.body) as Map<String, dynamic>;
      if (summary['status'] != 'success' || !mounted) return;

      setState(() {
        _totalBalance =
            double.tryParse(summary['total_balance']?.toString() ?? '0') ??
                _totalBalance;
      });
    } catch (e) {
      debugPrint('Student dashboard summary fetch failed: $e');
    }
  }

  Future<void> _fetchTransactions() async {
    final requestedFilter = _selectedFilter;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url(
            'student_transactions.php?student_id=${Uri.encodeQueryComponent(widget.id)}&filter=${Uri.encodeQueryComponent(requestedFilter)}',
          ),
        ),
        headers: AppSessionService.instance.authorizationHeaders,
      );
      if (await AppSessionService.instance.handleResponse(response)) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final rawTransactions = List<Map<String, dynamic>>.from(
            data['transactions'] ?? const [],
          );

          final mapped = rawTransactions.map((tx) {
            final rawType = (tx['transaction_type'] ?? '').toString();
            final type = rawType.toLowerCase().isEmpty
                ? 'payment'
                : rawType.toLowerCase();
            final isTopUp = type == 'top-up';
            final isTransferIn = type == 'transfer-in';
            final isTransferOut = type == 'transfer-out';
            final isCredit = isTopUp || isTransferIn;
            final rawAmount =
                double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
            final rawTimestamp =
                (tx['date_time'] ?? tx['date'] ?? tx['timestamp'] ?? '')
                    .toString();

            String description;
            if (type == 'payment') {
              final items = tx['items'] as List<dynamic>? ?? const [];
              if (items.isNotEmpty) {
                description = items
                    .map((item) => "${item['name']} x${item['qty']}")
                    .join(', ');
              } else {
                description = (tx['description'] ?? 'Payment').toString();
              }
            } else {
              description = (tx['description'] ?? 'Wallet Top-Up').toString();
            }
            final responseTitle =
                (tx['transaction_label'] ?? tx['display_type'] ?? '')
                    .toString()
                    .trim();

            return <String, dynamic>{
              'transaction_id': tx['transaction_id'],
              'type': type,
              'title': responseTitle.isEmpty
                  ? studentTransactionDisplayLabel(type)
                  : responseTitle,
              'is_topup': isTopUp,
              'is_credit': isCredit,
              'description': description,
              'amount': rawAmount,
              'timestamp': rawTimestamp,
              'icon': isTopUp
                  ? Icons.account_balance_wallet_outlined
                  : isTransferIn
                      ? Icons.call_received_rounded
                      : isTransferOut
                          ? Icons.call_made_rounded
                          : Icons.layers_outlined,
            };
          }).toList();

          mapped.sort((a, b) {
            final aRaw = (a['timestamp'] ?? '').toString();
            final bRaw = (b['timestamp'] ?? '').toString();
            return bRaw.compareTo(aRaw);
          });

          if (!mounted || requestedFilter != _selectedFilter) return;
          final responseExpense = double.tryParse(
            data['total_expense']?.toString() ?? '',
          );
          final calculatedExpense = studentExpenseFromTransactions(mapped);
          setState(() {
            _transactions = mapped;
            _totalExpense = responseExpense ?? calculatedExpense;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Student dashboard fetch failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _transactions = [];
      _totalExpense = 0.0;
      _isLoading = false;
    });
  }

  void _onNavTap(int index) {
    if (index == 0) return;

    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              graphs.StudentGraphs(name: widget.name, id: widget.id),
        ),
      );
      return;
    }

    if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StudentTopUps(name: widget.name, id: widget.id),
        ),
      );
      return;
    }

    if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              StudentTransferScreen(name: widget.name, id: widget.id),
        ),
      );
      return;
    }

    if (index == 4) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              StudentProfile(id: widget.id, name: widget.name),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Center(
              child: Image.asset(
                'assets/redlogo.png',
                height: 74,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome',
                          style: TextStyle(
                            color: _primaryRed,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _deepRed,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ProfileAvatar(
                    role: 'student',
                    userId: widget.id,
                    radius: 40,
                    fallbackIcon: Icons.person,
                    iconColor: _primaryRed,
                    backgroundColor: Color(0xFFE7F0FF),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Total Balance',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatCurrency(_totalBalance),
                          style: const TextStyle(
                            color: _successGreen,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 44,
                    color: _primaryRed.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Total Expense',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatCurrency(_totalExpense, negative: true),
                          style: const TextStyle(
                            color: _primaryRed,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _primaryRed,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(42),
                    topRight: Radius.circular(42),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent Activity',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildFilterShell(),
                      const SizedBox(height: 14),
                      Expanded(child: _buildTransactionsPanel()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _StudentBottomNav(
        selectedIndex: 0,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildFilterShell() {
    final filters = ['Daily', 'Weekly', 'Monthly', 'Yearly'];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: filter == filters.first ? 0 : 4,
                right: filter == filters.last ? 0 : 4,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _selectedFilter = filter);
                  _fetchTransactions();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected ? _deepRed : _softPink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    filter,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _primaryRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransactionsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _panelPink,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryRed),
            )
          : _transactions.isEmpty
              ? RefreshIndicator(
                  color: _primaryRed,
                  onRefresh: _refreshDashboard,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 24,
                              ),
                              child: Text(
                                'No activity found.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              : RefreshIndicator(
                  color: _primaryRed,
                  onRefresh: _refreshDashboard,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _transactions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildTransactionCard(_transactions[index]),
                  ),
                ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final isCredit = tx['is_credit'] == true;
    final transactionId =
        int.tryParse((tx['transaction_id'] ?? '').toString()) ?? 0;

    return Material(
      color: Colors.white,
      elevation: 8,
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
                      viewerRole: 'student',
                      viewerId: widget.id,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: _deepRed,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tx['icon'] as IconData? ?? Icons.layers_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (tx['title'] ??
                              studentTransactionDisplayLabel(tx['type']))
                          .toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (tx['description'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _formatTimestamp((tx['timestamp'] ?? '').toString()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatAmount(tx['amount'], isCredit: isCredit),
                    style: TextStyle(
                      color: isCredit ? _successGreen : _primaryRed,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    transactionId > 0 ? 'View Receipt' : 'Completed',
                    style: TextStyle(
                      color: Colors.black38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (transactionId > 0) ...[
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: _primaryRed,
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double value, {bool negative = false}) {
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final sign = negative ? '-\u20B1' : '\u20B1';
    return '$sign$whole.${parts[1]}';
  }

  String _formatAmount(dynamic raw, {required bool isCredit}) {
    final value = double.tryParse(raw?.toString() ?? '0') ?? 0.0;
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final sign = isCredit ? '+' : '-';
    return '$sign\u20B1$whole.${parts[1]}';
  }

  String _formatTimestamp(String raw) {
    if (raw.trim().isEmpty) return 'Time unavailable';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour > 12
        ? parsed.hour - 12
        : (parsed.hour == 0 ? 12 : parsed.hour);
    final minute = parsed.minute.toString().padLeft(2, '0');
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';

    return '${parsed.year}-$month-$day \u2022 ${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }
}

class _StudentBottomNav extends StatelessWidget {
  static const Color _navRed = Color(0xFFC62828);
  static const Color _navDeepRed = Color(0xFFB71C1C);

  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _StudentBottomNav({
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _StudentNavItemData(icon: Icons.home_outlined),
      _StudentNavItemData(icon: Icons.bar_chart_rounded),
      _StudentNavItemData(icon: Icons.account_balance_wallet_outlined),
      _StudentNavItemData(icon: Icons.swap_horiz_rounded),
      _StudentNavItemData(icon: Icons.person_outline_rounded),
    ];

    return Container(
      color: _navRed,
      child: Container(
        height: 92,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(46),
            topRight: Radius.circular(46),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final isSelected = selectedIndex == index;
            final item = items[index];

            return GestureDetector(
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isSelected ? _navDeepRed : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Icon(
                  item.icon,
                  color: isSelected ? Colors.white : _navRed,
                  size: 28,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _StudentNavItemData {
  final IconData icon;

  const _StudentNavItemData({required this.icon});
}
