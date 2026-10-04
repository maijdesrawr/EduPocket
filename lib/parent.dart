import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'receipt_action.dart';
import 'app_session_service.dart';
import 'parent_bottom_nav.dart';
import 'parent_profile.dart';
import 'profile_avatar.dart';
import 'topup.dart';
import 'transaction_history.dart';

enum _ParentHomeMode { dashboard, spendingLimits }

class ParentDashboard extends StatefulWidget {
  final String name;
  final String id;

  const ParentDashboard({super.key, required this.name, required this.id});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _softRed = Color(0xFFD6322D);
  static const Color _softTab = Color(0xFFF0B8AC);
  static const Color _panelPink = Color(0xFFF2B2A9);
  static const Color _successGreen = Color(0xFF119D34);

  final TextEditingController _limitController = TextEditingController();
  final ScrollController _activitiesController = ScrollController();

  bool _isLoading = true;
  bool _isSavingLimit = false;
  bool _isUpdatingFreeze = false;
  bool _isFetchingDashboard = false;
  int _freezeRevision = 0;
  int _selectedChildIndex = 0;
  String? _limitChildId;
  String _limitPeriod = 'weekly';
  _ParentHomeMode _mode = _ParentHomeMode.dashboard;
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _activities = [];
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'dashboard_view',
        details: const {'dashboard': 'parent'},
      ),
    );
    _fetchDashboardData();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _mode != _ParentHomeMode.dashboard) return;
      _fetchDashboardData(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _activitiesController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _fetchDashboardData({
    bool silent = false,
    bool scrollActivitiesToTop = false,
  }) async {
    if (_isFetchingDashboard) return;
    _isFetchingDashboard = true;
    final freezeRevision = _freezeRevision;

    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url(
            'parent_dashboard.php?parent_id=${Uri.encodeQueryComponent(widget.id)}',
          ),
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final fetchedChildren = List<Map<String, dynamic>>.from(
            data['children'] ?? const [],
          );
          final fetchedActivities = List<Map<String, dynamic>>.from(
            data['activities'] ?? const [],
          );

          if (!mounted || _isUpdatingFreeze || freezeRevision != _freezeRevision) {
            _isFetchingDashboard = false;
            return;
          }
          final nextSelectedIndex = fetchedChildren.isEmpty
              ? 0
              : (_selectedChildIndex >= fetchedChildren.length
                  ? fetchedChildren.length - 1
                  : _selectedChildIndex);
          final selectedChildId = fetchedChildren.isEmpty
              ? null
              : ((_limitChildId != null &&
                      fetchedChildren.any(
                        (child) =>
                            (child['child_id'] ?? '').toString() ==
                            _limitChildId,
                      ))
                  ? _limitChildId
                  : (fetchedChildren[nextSelectedIndex]['child_id'] ?? '')
                      .toString());
          setState(() {
            _children = fetchedChildren;
            _activities = fetchedActivities;
            _selectedChildIndex = nextSelectedIndex;
            _limitChildId = selectedChildId;
            _isLoading = false;
          });
          if (scrollActivitiesToTop) {
            _scheduleActivitiesScrollToTop();
          }
          if (_mode == _ParentHomeMode.spendingLimits) {
            _syncLimitInputsFromChild(_childById(selectedChildId));
          }
          _isFetchingDashboard = false;
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _children = [];
        _activities = [];
        _limitChildId = null;
        _isLoading = false;
      });
    }

    _isFetchingDashboard = false;
  }

  Map<String, dynamic>? get _selectedChild {
    if (_children.isEmpty) return null;
    return _children[_selectedChildIndex];
  }

  Map<String, dynamic>? _childById(String? childId) {
    if (childId == null || childId.isEmpty) return null;
    for (final child in _children) {
      if ((child['child_id'] ?? '').toString() == childId) {
        return child;
      }
    }
    return null;
  }

  void _openSpendingLimits() {
    final child = _selectedChild;
    if (child == null) return;

    setState(() {
      _mode = _ParentHomeMode.spendingLimits;
    });
    _syncLimitInputsFromChild(child);
  }

  void _syncLimitInputsFromChild(Map<String, dynamic>? child) {
    if (child == null) return;

    final currentLimit = _asDouble(child['transaction_limit']);
    _limitChildId = (child['child_id'] ?? '').toString();
    _limitPeriod = _normalizedPeriod(child['transaction_limit_period']);
    _limitController.text =
        currentLimit > 0 ? _editableAmount(currentLimit) : '';
  }

  Future<void> _saveSpendingLimit() async {
    final childId = _limitChildId ?? '';
    final amount = double.tryParse(_limitController.text.trim());

    if (childId.isEmpty) {
      _showSnack('Please select a child first.');
      return;
    }
    if (amount == null || amount <= 0 || amount > 100000) {
      _showSnack('Enter an amount between 1 and 100,000.');
      return;
    }

    setState(() => _isSavingLimit = true);

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('set_spending_limit.php')),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'parent_id': widget.id,
          'student_num': childId,
          'amount': amount.toStringAsFixed(2),
          'limit_period': _limitPeriod,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          if (!mounted) return;
          _showSnack('Spending limit saved successfully.');
          setState(() {
            _mode = _ParentHomeMode.dashboard;
          });
          await _fetchDashboardData();
          return;
        }

        _showSnack(
            (data['message'] ?? 'Failed to save spending limit').toString());
        return;
      }

      _showSnack('Failed to save spending limit.');
    } catch (_) {
      _showSnack('Unable to save spending limit right now.');
    } finally {
      if (mounted) {
        setState(() => _isSavingLimit = false);
      }
    }
  }

  Future<void> _freezeStudent(String studentNum, bool freeze) async {
    if (_isUpdatingFreeze) return;
    setState(() => _isUpdatingFreeze = true);
    try {
      final response = await http.post(
        Uri.parse(
          ApiConfig.url('freeze_student.php'),
        ),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'parent_id': widget.id,
          'student_num': studentNum,
          'action': freeze ? 'freeze' : 'unfreeze',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          _showSnack(
            freeze ? 'Account has been frozen.' : 'Account has been unfrozen.',
          );
          if (!mounted) return;
          setState(() {
            final child = _childById(studentNum);
            if (child != null) child['is_frozen'] = freeze ? 1 : 0;
            _freezeRevision++;
          });
        } else {
          _showSnack(
            data['message'] ?? 'Failed to update account.',
          );
        }
      } else {
        _showSnack('Unable to update account (${response.statusCode}).');
      }
    } catch (e) {
      _showSnack(
        'Unable to update account.',
      );
    } finally {
      if (mounted) setState(() => _isUpdatingFreeze = false);
    }
  }

  Future<void> _onItemTapped(int index) async {
    if (index == 0) {
      if (_mode == _ParentHomeMode.spendingLimits) {
        setState(() => _mode = _ParentHomeMode.dashboard);
      }
      return;
    }

    if (index == 1) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TopUpContent(userName: widget.name, userId: widget.id),
        ),
      );

      if (result == true) {
        await _fetchDashboardData(
          silent: true,
          scrollActivitiesToTop: true,
        );
      }
      return;
    }

    if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TransactionHistoryPage(userName: widget.name, userId: widget.id),
        ),
      );
      return;
    }

    if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ParentProfilePage(userName: widget.name, userId: widget.id),
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
            const SizedBox(height: 16),
            Center(
              child: Image.asset(
                'assets/redlogo.png',
                height: 72,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome',
                          style: TextStyle(
                            color: _softRed,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _deepRed,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildHeroAvatar(),
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _mode == _ParentHomeMode.dashboard
                              ? _buildDashboardContent()
                              : _buildSpendingLimitContent(),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ParentBottomNav(
        selectedIndex: 0,
        onTap: (index) {
          _onItemTapped(index);
        },
      ),
    );
  }

  Widget _buildDashboardContent() {
    return Column(
      key: const ValueKey('dashboard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChildrenSelector(),
        const SizedBox(height: 16),
        _buildSummaryCard(_selectedChild),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _buildSetLimitButton(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFreezeButton(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _buildActivitiesPanel(_selectedChild),
        ),
      ],
    );
  }

  Widget _buildFreezeButton() {
    final child = _selectedChild;

    if (child == null) {
      return const SizedBox();
    }

    final isFrozen = child['is_frozen'].toString() == "1";

    return ElevatedButton(
      onPressed: _isUpdatingFreeze
          ? null
          : () async {
              final studentNum = (child['child_id'] ?? '').toString();
              if (studentNum.isEmpty) {
                _showSnack('Student account information is missing.');
                return;
              }

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(isFrozen ? 'Unfreeze Account' : 'Freeze Account'),
                  content: Text(
                    isFrozen
                        ? 'Allow this student to use the account again?'
                        : 'Freeze this student account? The student will not be able to use it until it is unfrozen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(isFrozen ? 'Unfreeze' : 'Freeze'),
                    ),
                  ],
                ),
              );

              if (confirmed != true || !mounted) return;

              await _freezeStudent(
                studentNum,
                !isFrozen,
              );
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: isFrozen ? Colors.green : Colors.white,
        foregroundColor: isFrozen ? Colors.white : Colors.red,
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      child: _isUpdatingFreeze
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              isFrozen ? "Unfreeze Account" : "Freeze Account",
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
    );
  }

  Widget _buildSpendingLimitContent() {
    final selectedChild = _childById(_limitChildId) ?? _selectedChild;

    return Column(
      key: const ValueKey('spending_limits'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.layers_outlined,
              color: Colors.white,
              size: 26,
            ),
            SizedBox(width: 8),
            Text(
              'Spending Limits',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 34),
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
        Center(
          child: _buildLimitChildDropdown(selectedChild),
        ),
        const SizedBox(height: 22),
        const Text(
          'Input Amount',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildLimitAmountField()),
            const SizedBox(width: 12),
            _buildLimitPeriodDropdown(),
          ],
        ),
        const Spacer(),
        Center(
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isSavingLimit || _children.isEmpty)
                  ? null
                  : _saveSpendingLimit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _primaryRed,
                elevation: 10,
                shadowColor: Colors.black38,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSavingLimit
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _primaryRed,
                      ),
                    )
                  : const Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }

  Widget _buildHeroAvatar() {
    return ProfileAvatar(
      role: 'parent',
      userId: widget.id,
      radius: 40,
      fallbackIcon: Icons.person,
      iconColor: _softRed,
      backgroundColor: const Color(0xFFE7F0FF),
    );
  }

  Widget _buildChildrenSelector() {
    if (_children.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'No linked students',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF7A7A7A),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final useExpandedTabs = _children.length <= 2;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: useExpandedTabs
          ? Row(
              children: List.generate(
                _children.length,
                (index) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 4,
                      right: index == _children.length - 1 ? 0 : 4,
                    ),
                    child: _buildChildTab(index),
                  ),
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  _children.length,
                  (index) => Padding(
                    padding: EdgeInsets.only(
                      right: index == _children.length - 1 ? 0 : 8,
                    ),
                    child: SizedBox(
                      width: 150,
                      child: _buildChildTab(index),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildChildTab(int index) {
    final child = _children[index];
    final selected = _selectedChildIndex == index;
    final label = (child['child_name'] ?? 'Student').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _selectedChildIndex = index);
        _scheduleActivitiesScrollToTop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 32,
        decoration: BoxDecoration(
          color: selected ? _deepRed : _softTab,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : _primaryRed,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic>? child) {
    if (child == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Text(
          'Link a student account to view balance details.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black54,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final childName = (child['child_name'] ?? 'Student').toString();
    final balance = _asDouble(child['balance']);
    final expense = _asDouble(child['expense']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Text(
            "$childName's Account Report Balance:",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Total Balance',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatCurrency(balance),
                      style: const TextStyle(
                        color: _successGreen,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Total Expense',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatCurrency(expense, negative: true),
                      style: const TextStyle(
                        color: _deepRed,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSetLimitButton() {
    return ElevatedButton(
      onPressed: _children.isEmpty ? null : _openSpendingLimits,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 10,
        shadowColor: Colors.black38,
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      child: const Text(
        'Set Spending Limits',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildActivitiesPanel(Map<String, dynamic>? child) {
    final activities = child == null
        ? const <Map<String, dynamic>>[]
        : _activitiesForChild((child['child_id'] ?? '').toString());

    return Container(
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
      child: child == null
          ? _buildActivitiesEmptyState('No linked student activity yet.')
          : activities.isEmpty
              ? _buildActivitiesEmptyState(
                  'No transactions found for this child.')
              : RefreshIndicator(
                  color: _primaryRed,
                  onRefresh: _fetchDashboardData,
                  child: ListView.separated(
                    controller: _activitiesController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 18),
                    itemCount: activities.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) =>
                        _buildActivityCard(activities[index]),
                  ),
                ),
    );
  }

  Widget _buildLimitChildDropdown(Map<String, dynamic>? selectedChild) {
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
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedChild == null
              ? null
              : (selectedChild['child_id'] ?? '').toString(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          isExpanded: true,
          borderRadius: BorderRadius.circular(18),
          items: _children.map((child) {
            final childId = (child['child_id'] ?? '').toString();
            return DropdownMenuItem<String>(
              value: childId,
              child: Text(
                (child['child_name'] ?? 'Student').toString(),
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
              _limitChildId = value;
            });
            _syncLimitInputsFromChild(_childById(value));
          },
        ),
      ),
    );
  }

  Widget _buildLimitAmountField() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _limitController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          border: InputBorder.none,
          prefixText: '\u20B1  ',
          prefixStyle: TextStyle(
            color: Colors.black54,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          hintText: '1 - 100,000',
          hintStyle: TextStyle(
            color: Colors.black45,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildLimitPeriodDropdown() {
    return Container(
      width: 120,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _limitPeriod,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          borderRadius: BorderRadius.circular(18),
          items: const [
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _limitPeriod = value);
          },
        ),
      ),
    );
  }

  Widget _buildActivitiesEmptyState(String message) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          color: _primaryRed,
          onRefresh: _fetchDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> item) {
    final isTopUp = _isTopUp(item);
    final name = (item['name'] ?? '').toString().trim();
    final note = _activityNote(item);
    final timestamp = _formatTimestamp(
      (item['timestamp'] ?? item['date'] ?? '').toString(),
    );
    final amount = _formatAmount(_asDouble(item['amount']), isTopUp: isTopUp);

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x2A000000),
      borderRadius: BorderRadius.circular(18),
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
                    name.isEmpty ? 'Student' : name,
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
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
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
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                amount,
                style: TextStyle(
                  color: isTopUp ? _successGreen : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ReceiptAction(
                  transactionId:
                      int.tryParse((item['transaction_id'] ?? '').toString()) ??
                          0,
                  viewerRole: 'parent',
                  viewerId: widget.id),
            ]),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _activitiesForChild(String childId) {
    final filtered = _activities.where((activity) {
      return (activity['child_id'] ?? '').toString() == childId;
    }).toList();

    filtered.sort((a, b) {
      final aRaw = (a['timestamp'] ?? a['date'] ?? '').toString();
      final bRaw = (b['timestamp'] ?? b['date'] ?? '').toString();
      return bRaw.compareTo(aRaw);
    });

    return filtered;
  }

  void _scheduleActivitiesScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_activitiesController.hasClients) return;
      _activitiesController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isTopUp(Map<String, dynamic> item) {
    final type = (item['transaction_type'] ?? '').toString().toLowerCase();
    return type == 'top-up';
  }

  String _activityNote(Map<String, dynamic> item) {
    final raw = (item['note'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    return _isTopUp(item) ? 'Wallet Top-Up' : 'Payment';
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _editableAmount(double value) {
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _normalizedPeriod(dynamic raw) {
    final value = raw?.toString().toLowerCase().trim() ?? '';
    if (value == 'daily' || value == 'weekly' || value == 'monthly') {
      return value;
    }
    return 'daily';
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

  String _formatAmount(double value, {required bool isTopUp}) {
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
