import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rawr/api_config.dart';
import 'package:rawr/parent.dart' as parent_page;
import 'package:rawr/parent_bottom_nav.dart';
import 'payment_method.dart';
import 'parent_profile.dart';
import 'transaction_history.dart';

class TopUpContent extends StatefulWidget {
  final String userName;
  final String userId;

  const TopUpContent({super.key, required this.userName, required this.userId});

  @override
  State<TopUpContent> createState() => _TopUpContentState();
}

class _TopUpContentState extends State<TopUpContent> {
  static const Color _primaryRed = Color(0xFFC62828);

  final TextEditingController _amountController = TextEditingController();
  final List<double> _topUpOptions = const [
    10,
    50,
    100,
    200,
    300,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
  ];

  double? _highlightedAmount;
  bool _customSelected = false;
  bool _isLoadingChildren = true;

  String? _selectedChildId;
  String? _selectedChildName;
  List<Map<String, dynamic>> _children = [];
  @override
  void initState() {
    super.initState();
    _fetchChildren();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchChildren() async {
    setState(() => _isLoadingChildren = true);

    try {
      final response = await http.get(
        Uri.parse(
          ApiConfig.url(
            'get_linked_children.php?parent_id=${Uri.encodeQueryComponent(widget.userId)}',
          ),
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final mappedChildren = (data['children'] as List)
              .map<Map<String, dynamic>>(
                (child) => {
                  'id': child['student_num'].toString(),
                  'name': child['Fname'].toString(),
                  'is_locked': int.tryParse(
                        child['is_locked'].toString(),
                      ) ??
                      0,
                  'is_frozen': int.tryParse(
                        child['is_frozen'].toString(),
                      ) ??
                      0,
                },
              )
              .toList();

          final ids = <String>{};
          final deduped =
              mappedChildren.where((c) => ids.add(c['id']!)).toList();

          setState(() {
            _children = deduped;
            if (_children.isNotEmpty) {
              _selectedChildId = _children[0]['id'];
              _selectedChildName = _children[0]['name'];
            } else {
              _selectedChildId = null;
              _selectedChildName = null;
            }
            _isLoadingChildren = false;
          });
          return;
        }
      }
    } catch (e) {
      print('Error fetching children: $e');
    }

    setState(() {
      _children = [];
      _selectedChildId = null;
      _selectedChildName = null;
      _isLoadingChildren = false;
    });
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => parent_page.ParentDashboard(
            name: widget.userName,
            id: widget.userId,
          ),
        ),
      );
      return;
    }

    if (index == 1) {
      return;
    }

    if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionHistoryPage(
            userName: widget.userName,
            userId: widget.userId,
          ),
        ),
      );
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

  void _goToWallet(double amount, {bool isCustom = false}) async {
    if (_selectedChildId == null || _selectedChildName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a child')),
      );
      return;
    }

    final selectedChild = _children.firstWhere(
      (child) => child['id'] == _selectedChildId,
    );

    if (selectedChild['is_locked'] == 1 || selectedChild['is_frozen'] == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This account is frozen or locked. Top-up is unavailable.',
          ),
        ),
      );
      return;
    }

    if (_selectedChildId == null || _selectedChildName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a child')),
      );
      return;
    }

    setState(() {
      _highlightedAmount = amount;
      _customSelected = isCustom;
    });

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentMethodPage(
          userName: widget.userName,
          userId: widget.userId,
          amount: amount,
          selectedChildId: _selectedChildId!,
          selectedChildName: _selectedChildName!,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  void _confirmTopUp() {
    if (_selectedChildId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a child')),
      );
      return;
    }

    final selectedChild = _children.firstWhere(
      (child) => child['id'] == _selectedChildId,
    );

    if (selectedChild['is_locked'] == 1 || selectedChild['is_frozen'] == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This account is frozen or locked. Top-up is unavailable.',
          ),
        ),
      );
      return;
    }

    final customText = _amountController.text.trim();

    if (customText.isNotEmpty) {
      final input = double.tryParse(customText);
      if (input == null || input <= 0 || input > 100000) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter an amount between 1 and 100,000'),
          ),
        );
        return;
      }

      _goToWallet(input, isCustom: true);
      return;
    }

    if (_highlightedAmount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter an amount')),
      );
      return;
    }

    _goToWallet(_highlightedAmount!);
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
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.payments_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Top-up',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _topUpOptions.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 2.55,
                                ),
                                itemBuilder: (context, index) {
                                  return _buildAmountOption(
                                      _topUpOptions[index]);
                                },
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Input Amount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildCustomAmountField(),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _confirmTopUp,
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
                                  child: const Text(
                                    'Confirm',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
      bottomNavigationBar: ParentBottomNav(
        selectedIndex: 1,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildChildDropdown() {
    if (_isLoadingChildren) {
      return _buildDropdownShell(
        child: const Text(
          'Loading children...',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (_children.isEmpty) {
      return _buildDropdownShell(
        child: const Text(
          'No linked students',
          style: TextStyle(
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
          items: _children
              .map(
                (child) => DropdownMenuItem<String>(
                  value: child['id'],
                  child: Text(
                    child['name'] ?? 'Student',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedChildId = value;
              _selectedChildName = _children.firstWhere(
                (child) => child['id'] == value,
              )['name'];
            });
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

  Widget _buildAmountOption(double amount) {
    final isSelected = !_customSelected && _highlightedAmount == amount;

    return Material(
      color: isSelected ? const Color(0xFFF0B8AC) : Colors.white,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _goToWallet(amount),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              _formatPresetAmount(amount),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAmountField() {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 54,
        child: TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (value) {
            setState(() {
              _customSelected = value.trim().isNotEmpty;
              if (_customSelected) {
                _highlightedAmount = null;
              }
            });
          },
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
      ),
    );
  }

  String _formatPresetAmount(double amount) {
    final whole = amount.toInt().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
    return '\u20B1$whole';
  }
}
