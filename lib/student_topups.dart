import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'receipt_screen.dart';
import 'student_dashboard.dart';
import 'student_graphs.dart' as graphs;
import 'student_profile.dart';
import 'student_transfer.dart';

@visibleForTesting
Map<String, dynamic> mapStudentTopUpForHistory(
  Map<String, dynamic> transaction, {
  required String studentName,
}) {
  final amount =
      double.tryParse(transaction['amount']?.toString() ?? '0') ?? 0.0;
  final transactionId =
      int.tryParse(transaction['transaction_id']?.toString() ?? '') ?? 0;

  return <String, dynamic>{
    'transaction_id': transactionId,
    'title': 'Wallet Top-up',
    'name': studentName,
    'amount': amount,
    'status': (transaction['status'] ?? 'Completed').toString(),
    'timestamp': (transaction['date_time'] ?? '').toString(),
    'method': (transaction['method'] ?? '').toString(),
  };
}

class StudentTopUps extends StatefulWidget {
  final String name;
  final String id;

  const StudentTopUps({super.key, required this.name, required this.id});

  @override
  State<StudentTopUps> createState() => _StudentTopUpsState();
}

class _StudentTopUpsState extends State<StudentTopUps> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _panelPink = Color(0xFFF2B2A9);
  static const Color _successGreen = Color(0xFF129D37);

  bool _isLoading = true;
  double _totalBalance = 0.0;
  double _totalExpense = 0.0;
  List<Map<String, dynamic>> _topups = [];

  @override
  void initState() {
    super.initState();
    _fetchTopUps();
  }

  Future<void> _fetchTopUps() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url(
            'student_topups.php?student_id=${Uri.encodeQueryComponent(widget.id)}',
          ),
        ),
        headers: AppSessionService.instance.authorizationHeaders,
      );
      if (await AppSessionService.instance.handleResponse(response)) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final rawTopups = List<Map<String, dynamic>>.from(
            data['topups'] ?? const [],
          );

          final mapped = rawTopups
              .map(
                (tx) => mapStudentTopUpForHistory(
                  tx,
                  studentName: widget.name,
                ),
              )
              .toList();

          if (!mounted) return;
          setState(() {
            _topups = mapped;
            _totalBalance =
                double.tryParse(data['total_balance']?.toString() ?? '0') ??
                    0.0;
            _totalExpense =
                double.tryParse(data['total_expense']?.toString() ?? '0') ??
                    0.0;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Student topups fetch failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _topups = [];
      _totalBalance = 0.0;
      _totalExpense = 0.0;
      _isLoading = false;
    });
  }

  void _onNavTap(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              StudentDashboard(name: widget.name, id: widget.id),
        ),
      );
      return;
    }

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

    if (index == 2) return;

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
                    backgroundColor: const Color(0xFFE7F0FF),
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
                      Row(
                        children: const [
                          Icon(
                            Icons.layers_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Recent Top-ups',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(child: _buildTopupsPanel()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _StudentBottomNav(
        selectedIndex: 2,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildTopupsPanel() {
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
          : _topups.isEmpty
              ? RefreshIndicator(
                  color: _primaryRed,
                  onRefresh: _fetchTopUps,
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
                                'No top-ups found.',
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
                  onRefresh: _fetchTopUps,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _topups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildTopupCard(_topups[index]),
                  ),
                ),
    );
  }

  Widget _buildTopupCard(Map<String, dynamic> tx) {
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
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
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
                      (tx['title'] ?? 'Wallet Top-up').toString(),
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
                      (tx['name'] ?? widget.name).toString(),
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
                    _formatAmount(tx['amount']),
                    style: const TextStyle(
                      color: _successGreen,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (tx['status'] ?? 'Completed').toString(),
                        style: const TextStyle(
                          color: Colors.black38,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (transactionId > 0) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.receipt_long_outlined,
                          color: _primaryRed,
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

  String _formatAmount(dynamic raw) {
    final value = double.tryParse(raw?.toString() ?? '0') ?? 0.0;
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '+\u20B1$whole.${parts[1]}';
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
