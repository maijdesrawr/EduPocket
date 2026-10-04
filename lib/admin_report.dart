import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'admin_home.dart';
import 'admin_profile.dart';
import 'admin_users.dart';
import 'api_config.dart';
import 'receipt_screen.dart';

@visibleForTesting
int adminReportTransactionId(Map<String, dynamic> transaction) {
  return int.tryParse(
        (transaction['transaction_id'] ?? transaction['id'] ?? '').toString(),
      ) ??
      0;
}

class AdminReportsPage extends StatefulWidget {
  final String adminName;
  final String adminId;

  const AdminReportsPage({
    super.key,
    required this.adminName,
    required this.adminId,
  });

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _softTab = Color(0xFFF0B8AC);
  static const Color _panelPink = Color(0xFFF2B2A9);
  static const Color _successGreen = Color(0xFF119D34);

  final TextEditingController _searchController = TextEditingController();

  int _selectedIndex = 2;
  bool _isLoading = true;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse(ApiConfig.url('get_all_transactions.php')),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final transactions = List<Map<String, dynamic>>.from(
            data['transactions'] ?? const [],
          );
          if (!mounted) return;
          setState(() {
            _transactions = transactions;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _transactions = [];
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transactions = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onNavTap(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminHome(name: widget.adminName, id: widget.adminId),
        ),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AdminUsers(adminName: widget.adminName, adminId: widget.adminId),
        ),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminProfilePage(
            adminName: widget.adminName,
            adminId: widget.adminId,
          ),
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    return _transactions.where((tx) {
      final type = (tx['type'] ?? '').toString().toLowerCase();
      if (_selectedFilter == 'Top-ups' && type != 'top-up') {
        return false;
      }
      if (_selectedFilter == 'Payments' && type != 'payment') {
        return false;
      }

      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;

      final title = _transactionTitle(tx).toLowerCase();
      final name = (tx['name'] ?? '').toString().toLowerCase();
      return title.contains(query) || name.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Center(
              child: Image.asset(
                'assets/redlogo.png',
                height: 72,
                fit: BoxFit.contain,
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
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.monetization_on_outlined,
                            color: _softTab,
                            size: 26,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Transaction Records',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSearchField(),
                      const SizedBox(height: 16),
                      _buildFilterTabs(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
                          decoration: BoxDecoration(
                            color: _panelPink,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: _buildTransactionsPanel(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search, color: Colors.black87, size: 22),
          hintText: 'Search By Name...',
          hintStyle: TextStyle(
            color: Color(0xFF9A9A9A),
            fontSize: 14,
          ),
          contentPadding: EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    const filters = ['All', 'Top-ups', 'Payments'];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: filters.map((filter) {
          final selected = _selectedFilter == filter;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _selectedFilter = filter);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected ? _deepRed : _softTab,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    filter,
                    style: TextStyle(
                      color: selected ? Colors.white : _primaryRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryRed),
      );
    }

    final transactions = _filteredTransactions;
    if (transactions.isEmpty) {
      return RefreshIndicator(
        color: _primaryRed,
        onRefresh: _fetchTransactions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(
              child: Text(
                'No transactions found.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _primaryRed,
      onRefresh: _fetchTransactions,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: transactions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _buildTransactionCard(
          transactions[index],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final title = _transactionTitle(tx);
    final name = (tx['name'] ?? 'Unknown User').toString().trim();
    final timestamp = _formatTimestamp((tx['date'] ?? '').toString());
    final isTopUp = _isTopUp(tx);
    final amount = _formatAmount(tx, isTopUp);
    final transactionId = adminReportTransactionId(tx);

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x2A000000),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: transactionId > 0
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptScreen(
                      transactionId: transactionId,
                      viewerRole: 'admin',
                      viewerId: widget.adminId,
                    ),
                  ),
                )
            : () => _showTransactionDetails(tx),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
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
                      timestamp,
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
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: TextStyle(
                      color: isTopUp ? _successGreen : Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (transactionId > 0) ...[
                        const Icon(
                          Icons.receipt_long_outlined,
                          color: _primaryRed,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        transactionId > 0 ? 'View Receipt' : 'View Details',
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 10,
                          decoration: TextDecoration.underline,
                        ),
                      ),
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

  Widget _buildBottomNav() {
    return SafeArea(
      top: false,
      child: Container(
        color: _primaryRed,
        child: Container(
          height: 92,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(46),
              topRight: Radius.circular(46),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded),
              _buildNavItem(1, Icons.groups_rounded),
              _buildNavItem(2, Icons.query_stats_rounded),
              _buildNavItem(3, Icons.person_outline_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final selected = _selectedIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _onNavTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? _deepRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          size: 28,
          color: selected ? Colors.white : _primaryRed,
        ),
      ),
    );
  }

  bool _isTopUp(Map<String, dynamic> tx) {
    final type = (tx['type'] ?? '').toString().toLowerCase();
    return type == 'top-up';
  }

  String _transactionTitle(Map<String, dynamic> tx) {
    final note = (tx['note'] ?? '').toString().trim();
    if (note.isNotEmpty) return note;
    return _isTopUp(tx) ? 'Wallet Top-up' : 'Payment';
  }

  String _formatAmount(Map<String, dynamic> tx, bool isTopUp) {
    final parsed =
        double.tryParse((tx['amount'] ?? '0').toString().trim()) ?? 0.0;
    final fixed = parsed.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final sign = isTopUp ? '+' : '-';
    return '$sign\u20B1$whole.${parts[1]}';
  }

  String _formatTimestamp(String raw) {
    if (raw.trim().isEmpty) return 'Time unavailable';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final date =
        '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    final hour = parsed.hour > 12
        ? parsed.hour - 12
        : (parsed.hour == 0 ? 12 : parsed.hour);
    final minute = parsed.minute.toString().padLeft(2, '0');
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
    return '$date \u2022 ${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }

  void _showTransactionDetails(Map<String, dynamic> tx) {
    final isTopUp = _isTopUp(tx);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_transactionTitle(tx)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student: ${(tx['name'] ?? 'Unknown User').toString()}'),
              const SizedBox(height: 8),
              Text(
                'Type: ${isTopUp ? 'Top-up' : 'Payment'}',
              ),
              const SizedBox(height: 8),
              Text('Amount: ${_formatAmount(tx, isTopUp)}'),
              const SizedBox(height: 8),
              Text(
                'Timestamp: ${_formatTimestamp((tx['date'] ?? '').toString())}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
