

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'receipt_screen.dart';
import 'topup_receipt_navigation.dart';
import 'transaction_notification_service.dart';

enum _FlowStage { selectAmount, pinEntry, result }

class CashierTopUpScreen extends StatefulWidget {
  final String studentNumber;
  final String cashierId;
  final ValueChanged<int>? onNavigate;

  const CashierTopUpScreen({
    super.key,
    required this.studentNumber,
    required this.cashierId,
    this.onNavigate,
  });

  @override
  State<CashierTopUpScreen> createState() => _CashierTopUpScreenState();
}

class _CashierTopUpScreenState extends State<CashierTopUpScreen> {
  static const Color _brandRed = Color(0xFFAC2324);
  static const int _pinLength = 6;
  static const int _maxAmount = 100000;
  static const int _selectedNavIndex = 2;

  final TextEditingController _amountController = TextEditingController();
  final List<List<int>> _topupOptions = const [
    [10, 50, 100],
    [200, 300, 500],
    [1000, 2000, 5000],
    [10000, 20000, 50000],
  ];

  bool _isLoading = false;
  _FlowStage _stage = _FlowStage.selectAmount;
  String _pin = '';
  double? _selectedAmount;
  bool? _isSuccess;
  String _resultMessage = '';
  int _transactionId = 0;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String _formatWholeNumber(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      final reverseIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }

    return buffer.toString();
  }

  String _formatAmountLabel(int amount) =>
      '\u20B1${_formatWholeNumber(amount)}';

  void _startTopUp(double amount) {
    if (amount < 1 || amount > _maxAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an amount between 1 and 100,000'),
        ),
      );
      return;
    }

    setState(() {
      _selectedAmount = amount;
      _stage = _FlowStage.pinEntry;
      _pin = '';
      _transactionId = 0;
    });
  }

  void _handleCustomTopUp() {
    final amount = int.tryParse(_amountController.text);
    if (amount == null || amount < 1 || amount > _maxAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an amount between 1 and 100,000'),
        ),
      );
      return;
    }
    _startTopUp(amount.toDouble());
  }

  void _addPinDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    if (!RegExp(r'^\d$').hasMatch(digit)) return;

    setState(() => _pin += digit);
    if (_pin.length == _pinLength) {
      _submitTopUp();
    }
  }

  void _removePinDigit() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submitTopUp() async {
    if (_selectedAmount == null) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('cashier_topup.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'student_id': widget.studentNumber,
          'cashier_id': widget.cashierId,
          'amount': _selectedAmount.toString(),
          'pin': _pin,
        },
      );
      await AppSessionService.instance.handleResponse(response);
      if (!mounted) return;

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        unawaited(TransactionNotificationService.refreshNow());
        setState(() {
          _isSuccess = true;
          _transactionId = topUpTransactionIdFromResponse(data);
          _resultMessage =
              'Top-up amount: \u20B1${_selectedAmount!.toStringAsFixed(2)}\nStudent new balance: \u20B1${data['data']['new_balance']}\nCashier remaining balance: \u20B1${data['data']['cashier_new_balance']}';
          _stage = _FlowStage.result;
        });
      } else {
        setState(() {
          _isSuccess = false;
          _transactionId = 0;
          _resultMessage = (data['message'] ?? 'Top-up failed').toString();
          _stage = _FlowStage.result;
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _transactionId = 0;
        _resultMessage = 'Connection error: $e';
        _stage = _FlowStage.result;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _titleForStage() {
    switch (_stage) {
      case _FlowStage.selectAmount:
        return null;
      case _FlowStage.pinEntry:
        return 'Enter Cashier PIN';
      case _FlowStage.result:
        return _isSuccess == true ? 'Top-up Successful' : 'Top-up Failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stageTitle = _titleForStage();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F1F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F1F1),
        elevation: 0,
        title: Image.asset('assets/icons/logo-red.png', height: 60),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: Container(
        color: _brandRed,
        child: _buildBottomNav(),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: stageTitle == null ? 18 : 10),
              if (stageTitle != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    stageTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _brandRed,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(42),
                      topRight: Radius.circular(42),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(42),
                      topRight: Radius.circular(42),
                    ),
                    child: _buildStageContent(),
                  ),
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case _FlowStage.selectAmount:
        return _buildTopUpSelection();
      case _FlowStage.pinEntry:
        return _buildPinEntry();
      case _FlowStage.result:
        return _buildResultScreen();
    }
  }

  Widget _buildTopUpSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.layers_outlined, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Top-up',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ..._topupOptions.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: row.map((amount) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: InkWell(
                        onTap: () => _startTopUp(amount.toDouble()),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatAmountLabel(amount),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFF2E2E2E),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          }),
          const SizedBox(height: 10),
          const Text(
            'Input Amount',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              TextInputFormatter.withFunction((oldValue, newValue) {
                final text = newValue.text;
                if (text.isEmpty) return newValue;
                final parsed = int.tryParse(text);
                if (parsed == null || parsed > _maxAmount) {
                  return oldValue;
                }
                return newValue;
              }),
            ],
            decoration: InputDecoration(
              hintText: '\u20B1  1 - 100,000',
              hintStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleCustomTopUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _brandRed,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinEntry() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 20),
      child: Column(
        children: [
          ProfileAvatar(
            role: 'cashier',
            userId: widget.cashierId,
            radius: 38,
            fallbackIcon: Icons.person,
            iconColor: _brandRed,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            'Cashier: ${widget.cashierId}\nEnter your cashier PIN',
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Top-up \u20B1${_selectedAmount?.toStringAsFixed(2) ?? '0.00'}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (index) {
              final isFilled = index < _pin.length;
              return Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isFilled ? Colors.white : Colors.transparent,
                  border: Border.all(color: Colors.white, width: 2),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          _buildNumericKeypad(),
        ],
      ),
    );
  }

  Widget _buildNumericKeypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'DEL'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: keys.expand((row) {
          return row.map((key) {
            final isDelete = key == 'DEL';
            return GestureDetector(
              onTap: () {
                if (isDelete) {
                  _removePinDigit();
                } else {
                  _addPinDigit(key);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD6CCE7), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: isDelete
                      ? const Icon(
                          Icons.backspace_outlined,
                          color: _brandRed,
                          size: 22,
                        )
                      : Text(
                          key,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _brandRed,
                          ),
                        ),
                ),
              ),
            );
          }).toList();
        }).toList(),
      ),
    );
  }

  Widget _buildResultScreen() {
    final success = _isSuccess == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFD6CCE7),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    success ? Icons.check_circle : Icons.cancel,
                    size: 78,
                    color: success ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    success ? 'Top-up Successful' : 'Top-up Failed',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: success ? Colors.green : Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _resultMessage,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF2E2E2E),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (success) {
                  if (_transactionId > 0) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptScreen(
                          transactionId: _transactionId,
                          viewerRole: 'cashier',
                          viewerId: widget.cashierId,
                        ),
                      ),
                    );
                    if (!mounted) return;
                  }
                  Navigator.pop(context, true);
                  return;
                }

                setState(() {
                  _stage = _FlowStage.pinEntry;
                  _pin = '';
                  _transactionId = 0;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _brandRed,
                minimumSize: const Size(double.infinity, 58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                success ? 'Done' : 'Try Again',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 108),
        ],
      ),
    );
  }

  void _handleBottomNavTap(int index) {
    Navigator.pop(context, {'navIndex': index});
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
    final bool isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => _handleBottomNavTap(index),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? _brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(12),
        child: Image.asset(isSelected ? iconWhite : iconRed),
      ),
    );
  }

  Widget _profileNavItem({required int index}) {
    final bool isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => _handleBottomNavTap(index),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isSelected ? _brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.person_outline,
          color: isSelected ? Colors.white : _brandRed,
          size: 28,
        ),
      ),
    );
  }
}
