import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'admin_profile.dart';
import 'admin_report.dart';
import 'admin_users.dart';
import 'api_config.dart';
import 'receipt_action.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';

class AdminHome extends StatefulWidget {
  final String name;
  final String id;

  const AdminHome({super.key, required this.name, required this.id});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);
  static const Color _softRed = Color(0xFFD6322D);
  static const Color _cardShadow = Color(0x33000000);
  static const Color _mutedText = Color(0xFF8B8B8B);
  static const Color _successGreen = Color(0xFF139B2E);

  int _selectedIndex = 0;
  int _totalUsers = 0;
  bool _showUserBreakdown = false;
  Map<String, int> _userBreakdown = const {
    'admins': 0,
    'students': 0,
    'canteens': 0,
    'cashiers': 0,
    'parents': 0,
  };
  double _totalBalance = 0.0;
  bool _isLoading = true;
  List<dynamic> _activities = [];

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'dashboard_view',
        details: const {'dashboard': 'admin'},
      ),
    );
    fetchDashboardData();
  }

  Future<void> fetchDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse(ApiConfig.url('get_admin_dashboard.php')),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _totalUsers = int.tryParse(data['total_users'].toString()) ?? 0;
          final breakdown = data['user_breakdown'];
          if (breakdown is Map) {
            _userBreakdown = {
              for (final role in const [
                'admins',
                'students',
                'canteens',
                'cashiers',
                'parents',
              ])
                role: int.tryParse('${breakdown[role]}') ?? 0,
            };
          }
          _totalBalance =
              double.tryParse(data['total_balance'].toString()) ?? 0.0;
          _activities = List<dynamic>.from(data['activities'] ?? const []);
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  void _onNavTap(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AdminUsers(adminName: widget.name, adminId: widget.id),
        ),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AdminReportsPage(adminName: widget.name, adminId: widget.id),
        ),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AdminProfilePage(adminName: widget.name, adminId: widget.id),
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
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildUserStatCard(),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildStatCard(
                              icon: Icons.payments_outlined,
                              label: 'Total Balance',
                              value: _isLoading
                                  ? '--'
                                  : _formatMoney(_totalBalance),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickActionCard(
                              icon: Icons.group_add_outlined,
                              label: 'Manage Users',
                              onTap: () => _onNavTap(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickActionCard(
                              icon: Icons.query_stats_outlined,
                              label: 'View Reports',
                              onTap: () => _onNavTap(2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Recent Activity',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _onNavTap(2),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                'View All',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _buildRecentActivitySection(),
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

  Widget _buildHeroAvatar() {
    return ProfileAvatar(
      role: 'admin',
      userId: widget.id,
      radius: 30,
      fallbackIcon: Icons.person,
      iconColor: Colors.white,
      backgroundColor: Colors.grey,
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _mutedText, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserStatCard() {
    return GestureDetector(
      onTap: _isLoading
          ? null
          : () => setState(() => _showUserBreakdown = !_showUserBreakdown),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        transitionBuilder: (child, animation) {
          final rotate = Tween(begin: math.pi, end: 0.0).animate(animation);
          return AnimatedBuilder(
            animation: rotate,
            child: child,
            builder: (context, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(rotate.value),
              child: child,
            ),
          );
        },
        child: _showUserBreakdown
            ? Container(
                key: const ValueKey('user-breakdown'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withAlpha(26),
                      spreadRadius: 1,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    'admins',
                    'students',
                    'canteens',
                    'cashiers',
                    'parents',
                  ].map((role) {
                    final count = _userBreakdown[role] ?? 0;
                    final label =
                        '${role[0].toUpperCase()}${role.substring(1)}';
                    return SizedBox(
                      height: 13,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  color: _mutedText, fontSize: 9)),
                          Text(_formatNumber(count),
                              style: const TextStyle(
                                  color: _primaryRed,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              )
            : KeyedSubtree(
                key: const ValueKey('total-users'),
                child: _buildStatCard(
                  icon: Icons.groups_2_outlined,
                  label: 'Total Users',
                  value: _isLoading ? '--' : _formatNumber(_totalUsers),
                ),
              ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: _primaryRed, size: 20),
              const SizedBox(height: 6),
              SizedBox(
                height: 22,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitySection() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_activities.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 24),
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
        child: const Center(
          child: Text(
            'No recent activity found',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _activities.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildActivityCard(_activities[index] as Map<String, dynamic>);
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final amount = _activityAmountText(activity);
    final isPositive = _activityIsPositive(activity);
    final title = (activity['title'] ?? '').toString().trim();
    final subtitle = _activitySubtitle(activity);
    final timestamp = _activityTimestamp(activity);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Unknown User' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount.isEmpty ? '\u20B10' : amount,
                style: TextStyle(
                  color: isPositive ? _successGreen : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              ReceiptAction(
                  transactionId: int.tryParse(
                          (activity['transaction_id'] ?? '').toString()) ??
                      0,
                  viewerRole: 'admin',
                  viewerId: widget.id),
            ],
          ),
        ],
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

  String _formatNumber(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }

  String _formatMoney(double value) {
    final hasDecimals = value.truncateToDouble() != value;
    final fixed = value.abs().toStringAsFixed(hasDecimals ? 2 : 0);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = parts.length > 1 ? '$whole.${parts[1]}' : whole;
    final prefix = value < 0 ? '-\u20B1 ' : '\u20B1 ';
    return '$prefix$formatted';
  }

  String _activitySubtitle(Map<String, dynamic> activity) {
    final description =
        (activity['description'] ?? activity['paymentTitle'] ?? '')
            .toString()
            .trim();
    if (description.isNotEmpty && description.toLowerCase() != 'payment') {
      return description;
    }

    final raw = (activity['transaction_type'] ?? activity['subtitle'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return 'Recent transaction';

    switch (raw.toLowerCase()) {
      case 'top-up':
        return 'Parent Top-up';
      case 'payment':
        return 'Payment';
      default:
        return raw;
    }
  }

  String _activityTimestamp(Map<String, dynamic> activity) {
    final raw = (activity['timestamp'] ?? activity['date_time'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return 'Time unavailable';

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

  bool _activityIsPositive(Map<String, dynamic> activity) {
    final type = (activity['transaction_type'] ?? activity['subtitle'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (type == 'top-up') return true;
    if (type == 'payment') return false;

    final rawAmount = (activity['amount'] ?? '').toString().trim();
    return rawAmount.startsWith('+');
  }

  String _activityAmountText(Map<String, dynamic> activity) {
    final rawAmount = activity['amount'];
    double value;

    if (rawAmount is num) {
      value = rawAmount.toDouble();
    } else {
      final parsed =
          rawAmount?.toString().replaceAll(RegExp(r'[^0-9.\-]'), '').trim() ??
              '';
      value = double.tryParse(parsed) ?? 0;
    }

    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = '$whole.${parts[1]}';
    final sign = _activityIsPositive(activity) ? '+' : '-';
    return '$sign\u20B1$formatted';
  }
}
