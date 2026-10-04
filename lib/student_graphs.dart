import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'student_dashboard.dart';
import 'student_profile.dart';
import 'student_topups.dart';
import 'student_transfer.dart';

class StudentGraphs extends StatefulWidget {
  final String name;
  final String id;

  const StudentGraphs({super.key, required this.name, required this.id});

  @override
  State<StudentGraphs> createState() => _StudentGraphsState();
}

class _StudentGraphsState extends State<StudentGraphs> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _softPink = Color(0xFFF0B8AC);
  static const Color _panelPink = Color(0xFFF2B2A9);
  static const Color _successGreen = Color(0xFF129D37);
  static const Color _expenseOrange = Color(0xFFF57C00);

  String _selectedFilter = 'Daily';
  bool _isLoading = true;
  double _totalBalance = 0.0;
  double _totalExpense = 0.0;
  List<GraphData> _topups = [];
  List<GraphData> _expenses = [];

  @override
  void initState() {
    super.initState();
    _fetchGraphData();
  }

  Future<void> _fetchGraphData() async {
    final requestedFilter = _selectedFilter;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final graphResponse = await http.get(
        Uri.parse(
          ApiConfig.url(
            'student_graphs.php?student_num=${Uri.encodeQueryComponent(widget.id)}&filter=${Uri.encodeQueryComponent(requestedFilter)}',
          ),
        ),
        headers: AppSessionService.instance.authorizationHeaders,
      );
      if (await AppSessionService.instance.handleResponse(graphResponse)) {
        return;
      }

      if (graphResponse.statusCode == 200) {
        final jsonData = jsonDecode(graphResponse.body) as Map<String, dynamic>;
        if (jsonData['status'] == 'success') {
          final rawData = List<Map<String, dynamic>>.from(
            jsonData['data'] ?? const [],
          );

          
          final Map<String, double> weeklyTopups = {};
          final Map<String, double> weeklyExpenses = {};

          for (final item in rawData) {
            final label = (item['label'] ?? '').toString();
            final topup = (item['topup'] as num?)?.toDouble() ?? 0.0;
            final expense = (item['expense'] as num?)?.toDouble() ?? 0.0;

            weeklyTopups[label] = (weeklyTopups[label] ?? 0) + topup;
            weeklyExpenses[label] = (weeklyExpenses[label] ?? 0) + expense;
          }


          final fetchedTopups = weeklyTopups.entries
              .map((e) => GraphData(e.key, e.value))
              .toList();
          final fetchedExpenses = weeklyExpenses.entries
              .map((e) => GraphData(e.key, e.value))
              .toList();

          double balance = _totalBalance;
          final graphExpenseTotal = fetchedExpenses.fold<double>(
            0,
            (sum, item) => sum + item.value,
          );
          final expenseTotal = double.tryParse(
                jsonData['total_expense']?.toString() ?? '',
              ) ??
              graphExpenseTotal;

          final summaryResponse = await http.get(
            Uri.parse(
              ApiConfig.url(
                'student_topups.php?student_id=${Uri.encodeQueryComponent(widget.id)}',
              ),
            ),
            headers: AppSessionService.instance.authorizationHeaders,
          );
          if (await AppSessionService.instance
              .handleResponse(summaryResponse)) {
            return;
          }

          if (summaryResponse.statusCode == 200) {
            final summary =
                jsonDecode(summaryResponse.body) as Map<String, dynamic>;
            if (summary['status'] == 'success') {
              balance = double.tryParse(
                      summary['total_balance']?.toString() ?? '0') ??
                  balance;
            }
          }

          if (!mounted || requestedFilter != _selectedFilter) return;
          setState(() {
            _topups = fetchedTopups;
            _expenses = fetchedExpenses;
            _totalBalance = balance;
            _totalExpense = expenseTotal;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Student graphs fetch failed: $e');
    }

    if (!mounted || requestedFilter != _selectedFilter) return;
    setState(() {
      _topups = [];
      _expenses = [];
      _totalExpense = 0.0;
      _totalBalance = 0.0;
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

    if (index == 1) return;

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
                      _buildFilterShell(),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Student Transaction Graph',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _buildLegendChip(_successGreen, 'Top-Up'),
                          const SizedBox(width: 8),
                          _buildLegendChip(_expenseOrange, 'Expense'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(child: _buildChartPanel()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _StudentBottomNav(
        selectedIndex: 1,
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
                  _fetchGraphData();
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

  Widget _buildLegendChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildChartPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
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
          : _topups.isEmpty && _expenses.isEmpty
              ? const Center(
                  child: Text(
                    'No graph data available.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Expenses',
                      style: TextStyle(
                        color: _primaryRed,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _StudentBarChart(
                        topups: _topups,
                        expenses: _expenses,
                        filter: _selectedFilter,
                      ),
                    ),
                  ],
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
}

class _StudentBarChart extends StatelessWidget {
  final List<GraphData> topups;
  final List<GraphData> expenses;
  final String filter;

  const _StudentBarChart({
    required this.topups,
    required this.expenses,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final maxLength = [
      topups.length,
      expenses.length,
    ].reduce((a, b) => a > b ? a : b);

    if (maxLength == 0) {
      return const SizedBox.shrink();
    }

    var maxY = 0.0;

    for (final item in [...topups, ...expenses]) {
      if (item.value > maxY) {
        maxY = item.value;
      }
    }

    if (maxY <= 0) {
      maxY = 1000;
    } else {
      maxY *= 1.2;
    }

    final interval = maxY / 4;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        groupsSpace: 16,

        
        
        
        barTouchData: BarTouchData(
          enabled: true,

          touchTooltipData: BarTouchTooltipData(
            tooltipBorderRadius: BorderRadius.circular(10),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = rodIndex == 0
                  ? (groupIndex < topups.length ? topups[groupIndex] : null)
                  : (groupIndex < expenses.length
                      ? expenses[groupIndex]
                      : null);

              final type = rodIndex == 0 ? 'Top-Up' : 'Expense';
              final amount = rod.toY.toStringAsFixed(2);
              final label = item?.label ?? '';

              return BarTooltipItem(
                '$type\n$label\n₱$amount',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),

          
          
          
          touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
            if (event is FlTapUpEvent &&
                response != null &&
                response.spot != null) {
              final touchedSpot = response.spot!;
              final groupIndex = touchedSpot.touchedBarGroupIndex;
              final rodIndex = touchedSpot.touchedRodDataIndex;

              if (groupIndex < 0) return;

              GraphData? selectedItem;

              if (rodIndex == 0) {
                if (groupIndex < topups.length) {
                  selectedItem = topups[groupIndex];
                }
              } else {
                if (groupIndex < expenses.length) {
                  selectedItem = expenses[groupIndex];
                }
              }

              if (selectedItem == null) return;

              final type = rodIndex == 0 ? 'Top-Up' : 'Expense';

              final topupValue =
                  groupIndex < topups.length ? topups[groupIndex].value : 0.0;

              final expenseValue = groupIndex < expenses.length
                  ? expenses[groupIndex].value
                  : 0.0;

              _showInterpretationDialog(
                context,
                type: type,
                item: selectedItem,
                topupValue: topupValue,
                expenseValue: expenseValue,
              );
            }
          },
        ),

        
        
        
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: const Color(0x66C62828),
            strokeWidth: 1,
            dashArray: const [4, 3],
          ),
        ),

        borderData: FlBorderData(show: false),

        
        
        
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, meta) {
                return Text(
                  _compactPeso(value),
                  style: const TextStyle(
                    color: Color(0xFFB73D35),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();

                final rawLabel = index < topups.length
                    ? topups[index].label
                    : (index < expenses.length ? expenses[index].label : '');

                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _displayLabel(rawLabel, filter),
                    style: const TextStyle(
                      color: Color(0xFFB73D35),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        
        
        
        barGroups: List.generate(maxLength, (index) {
          final topupValue = index < topups.length ? topups[index].value : 0.0;

          final expenseValue =
              index < expenses.length ? expenses[index].value : 0.0;

          return BarChartGroupData(
            x: index,
            barsSpace: 6,
            barRods: [
              
              BarChartRodData(
                toY: topupValue,
                color: const Color(0xFF129D37),
                width: 10,
                borderRadius: BorderRadius.circular(6),
              ),

              
              BarChartRodData(
                toY: expenseValue,
                color: const Color(0xFFF57C00),
                width: 10,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          );
        }),
      ),
    );
  }

  
  
  

  void _showInterpretationDialog(
    BuildContext context, {
    required String type,
    required GraphData item,
    required double topupValue,
    required double expenseValue,
  }) {
    final interpretation = _generateInterpretation(
      type: type,
      item: item,
      topupValue: topupValue,
      expenseValue: expenseValue,
    );

    final isTopUp = type == 'Top-Up';

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isTopUp
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isTopUp
                            ? Icons.account_balance_wallet_rounded
                            : Icons.shopping_cart_rounded,
                        color: isTopUp
                            ? const Color(0xFF129D37)
                            : const Color(0xFFF57C00),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type == 'Top-Up'
                                ? 'Money Received'
                                : 'Spending Interpretation',
                            style: const TextStyle(
                              color: Color(0xFFC62828),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _periodLabel(),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '₱${item.value.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isTopUp
                              ? const Color(0xFF129D37)
                              : const Color(0xFFF57C00),
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                
                const Text(
                  'What this means',
                  style: TextStyle(
                    color: Color(0xFFC62828),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  interpretation,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 20),

                
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _summaryValue(
                          'Received',
                          topupValue,
                          const Color(0xFF129D37),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 38,
                        color: Colors.black12,
                      ),
                      Expanded(
                        child: _summaryValue(
                          'Expense',
                          expenseValue,
                          const Color(0xFFF57C00),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  
  
  

  String _generateInterpretation({
    required String type,
    required GraphData item,
    required double topupValue,
    required double expenseValue,
  }) {
    final received = topupValue;
    final spent = expenseValue;

    
    
    

    if (type == 'Top-Up') {
      if (received == 0) {
        return 'You did not receive any money from your parent during '
            'this period.';
      }

      if (spent == 0) {
        return 'For this period, you received '
            '₱${received.toStringAsFixed(2)} from your parent and did not '
            'record any expenses. This means none of your remaining balance'
            'was spent during this period.';
      }

      if (received > spent) {
        final remaining = received - spent;

        return 'For this period, you received '
            '₱${received.toStringAsFixed(2)} from your parent and spent '
            '₱${spent.toStringAsFixed(2)}. You spent less than the amount '
            'you received, with ₱${remaining.toStringAsFixed(2)} left '
            'as your balance.';
      }

      if (spent > received) {
        final difference = spent - received;

        return 'For this period, you received '
            '₱${received.toStringAsFixed(2)} from your parent but spent '
            '₱${spent.toStringAsFixed(2)}. Your expenses were '
            '₱${difference.toStringAsFixed(2)} higher.';
      }

      return 'For this period, you received '
          '₱${received.toStringAsFixed(2)} from your parent and spent '
          'the same amount.';
    }

    
    
    

    if (spent == 0) {
      return 'You did not record any expenses during this period.';
    }

    if (received == 0) {
      return 'For this period, you spent '
          '₱${spent.toStringAsFixed(2)}. No money received from your parent '
          'was recorded during this period.';
    }

    if (spent < received) {
      final remaining = received - spent;

      return 'For this period, you received '
          '₱${received.toStringAsFixed(2)} from your parent and spent '
          '₱${spent.toStringAsFixed(2)}. You spent less than the amount '
          'you received, with ₱${remaining.toStringAsFixed(2)} left '
          'as your remaining balance.';
    }

    if (spent > received) {
      final difference = spent - received;

      return 'For this period, you received '
          '₱${received.toStringAsFixed(2)} from your parent and spent '
          '₱${spent.toStringAsFixed(2)}. Your expenses were '
          '₱${difference.toStringAsFixed(2)} higher than the amount '
          'you received.';
    }

    return 'For this period, you received '
        '₱${received.toStringAsFixed(2)} from your parent and spent '
        'the same amount.';
  }

  
  
  

  String _periodLabel() {
    switch (filter) {
      case 'Daily':
        return 'Daily transaction';

      case 'Weekly':
        return 'Weekly transaction';

      case 'Monthly':
        return 'Monthly transaction';

      case 'Yearly':
        return 'Yearly transaction';

      default:
        return 'Transaction';
    }
  }

  
  
  

  Widget _summaryValue(
    String label,
    double value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '₱${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  
  
  

  static String _compactPeso(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
    }

    return value.toInt().toString();
  }

  
  
  

  static String _displayLabel(String label, String filter) {
    if (label.trim().isEmpty) {
      return '';
    }

    final parsed = DateTime.tryParse(label);

    if (parsed != null && filter == 'Daily') {
      const names = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ];

      return names[parsed.weekday - 1];
    }

    if (filter == 'Monthly') {
      final parts = label.split(' ');

      return parts.isNotEmpty ? parts.first : label;
    }

    if (filter == 'Weekly') {
      return label;
    }

    return label;
  }
}


class GraphData {
  final String label;
  final double value;

  GraphData(this.label, this.value);
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
