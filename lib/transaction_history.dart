import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_session_service.dart';
import 'api_config.dart';
import 'parent.dart';
import 'parent_bottom_nav.dart';
import 'parent_profile.dart';
import 'receipt_screen.dart';
import 'receipt_action.dart';
import 'topup.dart';

class TransactionHistoryPage extends StatefulWidget {
  final String userName;
  final String userId;

  const TransactionHistoryPage({
    super.key,
    required this.userName,
    required this.userId,
  });

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _panelPink = Color(0xFFF2B2A9);
  static const Color _successGreen = Color(0xFF129D37);

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _children = [];

  bool _isLoading = true;
  String? _selectedChildId;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'history_view',
        details: const {'history': 'parent_transactions'},
      ),
    );
    _fetchChildren();
  }

  Future<void> _fetchChildren() async {
    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url(
            'get_linked_children.php?parent_id=${Uri.encodeQueryComponent(widget.userId)}',
          ),
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final rawChildren = List<Map<String, dynamic>>.from(
            data['children'] ?? [],
          );

          final seenStudentNums = <String>{};
          final dedupedChildren = <Map<String, dynamic>>[];
          for (final child in rawChildren) {
            final studentNum = (child['student_num'] ?? '').toString();
            if (studentNum.isEmpty) continue;
            if (seenStudentNums.add(studentNum)) {
              dedupedChildren.add(child);
            }
          }

          final dedupedIds = dedupedChildren
              .map((child) => (child['student_num'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toSet();

          String? nextSelected = _selectedChildId;
          if (nextSelected == null || !dedupedIds.contains(nextSelected)) {
            nextSelected = dedupedChildren.isNotEmpty
                ? dedupedChildren.first['student_num']?.toString()
                : null;
          }

          setState(() {
            _children = dedupedChildren;
            _selectedChildId = nextSelected;
          });
          await _fetchTransactions();
          return;
        }
      }
    } catch (e) {
      debugPrint('Error fetching children: $e');
    }

    setState(() {
      _children = [];
      _selectedChildId = null;
      _transactions = [];
      _isLoading = false;
    });
  }

  Future<void> _fetchTransactions() async {
    if (_selectedChildId == null) {
      setState(() {
        _transactions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url(
            'transaction_history.php?parent_id=${Uri.encodeQueryComponent(widget.userId)}&child_id=${Uri.encodeQueryComponent(_selectedChildId!)}',
          ),
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final fetchedTransactions = List<Map<String, dynamic>>.from(
            data['transactions'] ?? const [],
          );
          fetchedTransactions.sort((a, b) {
            final aRaw = (a['timestamp'] ?? a['date'] ?? '').toString();
            final bRaw = (b['timestamp'] ?? b['date'] ?? '').toString();
            return bRaw.compareTo(aRaw);
          });

          setState(() {
            _transactions = fetchedTransactions;
          });
        } else {
          setState(() => _transactions = []);
        }
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ParentDashboard(name: widget.userName, id: widget.userId),
        ),
      );
      return;
    }

    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TopUpContent(userName: widget.userName, userId: widget.userId),
        ),
      );
      return;
    }

    if (index == 2) {
      return;
    }

    if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ParentProfilePage(
            userName: widget.userName,
            userId: widget.userId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTransactions = _transactions.where((tx) {
      final isTopUp = tx['is_topup'] == true;

      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Top-ups') return isTopUp;
      if (_selectedFilter == 'Expenses') return !isTopUp;

      return true;
    }).toList();

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
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.monetization_on_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Transaction History',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Center(
                        child: Text(
                          'Select a child:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(child: _buildChildDropdown()),
                      const SizedBox(height: 14),
                      _buildFilterShell(),
                      const SizedBox(height: 14),
                      Expanded(
                        child: _buildTransactionsPanel(filteredTransactions),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ParentBottomNav(
        selectedIndex: 2,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildChildDropdown() {
    if (_children.isEmpty) {
      return _buildDropdownShell(
        child: Text(
          _isLoading ? 'Loading children...' : 'No linked students',
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return _buildDropdownShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedChildId,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          isExpanded: true,
          borderRadius: BorderRadius.circular(18),
          items: _children.map((child) {
            return DropdownMenuItem<String>(
              value: child['student_num'],
              child: Text(
                (child['Fname'] ?? 'Student').toString(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedChildId = value;
            });
            _fetchTransactions();
          },
        ),
      ),
    );
  }

  Widget _buildDropdownShell({required Widget child}) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(height: 44, child: Center(child: child)),
    );
  }

  Widget _buildFilterShell() {
    final filters = ['All', 'Top-ups', 'Expenses'];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected ? _deepRed : _panelPink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    filter,
                    style: TextStyle(
                      color: isSelected ? Colors.white : _primaryRed,
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

  Widget _buildTransactionsPanel(
      List<Map<String, dynamic>> filteredTransactions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
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
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryRed),
            )
          : filteredTransactions.isEmpty
              ? RefreshIndicator(
                  color: _primaryRed,
                  onRefresh: _fetchChildren,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 24,
                              ),
                              child: Text(
                                'No transactions found.',
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
                  onRefresh: _fetchChildren,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filteredTransactions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildTransactionCard(filteredTransactions[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final isTopUp = tx['is_topup'] == true;
    final transactionId =
        int.tryParse((tx['transaction_id'] ?? '').toString()) ?? 0;
    final note = (tx['note'] ?? 'Transaction').toString();
    final name = (tx['name'] ?? '').toString();
    final timestamp = _formatTimestamp(
      (tx['timestamp'] ?? tx['date'] ?? '').toString(),
    );

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
                      viewerRole: 'parent',
                      viewerId: widget.userId,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
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
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  _formatAmount(tx['amount'], isTopUp: isTopUp),
                  style: TextStyle(
                    color: isTopUp ? _successGreen : _primaryRed,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                ReceiptAction(
                    transactionId: transactionId,
                    viewerRole: 'parent',
                    viewerId: widget.userId),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(dynamic raw, {required bool isTopUp}) {
    final normalized = (raw?.toString() ?? '').replaceAll(',', '').trim();
    final value = double.tryParse(normalized) ?? 0.0;
    final fixed = value.abs().toStringAsFixed(2);
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
}
