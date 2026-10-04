import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'profile_service.dart';
import 'transaction_notification_service.dart';

enum _FlowStage { amountEntry, pinEntry, result }

class CashierBillPayScreen extends StatefulWidget {
  final String recipientNumber;
  final String cashierId;
  final int billPaymentId;
  final String? description;
  final ValueChanged<int>? onNavigate;

  const CashierBillPayScreen({
    super.key,
    required this.recipientNumber,
    required this.cashierId,
    required this.billPaymentId,
    this.description,
    this.onNavigate,
  });

  @override
  State<CashierBillPayScreen> createState() => _CashierBillPayScreenState();
}

class _CashierBillPayScreenState extends State<CashierBillPayScreen> {
  static const Color _brandRed = Color(0xFFAC2324);
  static const int _pinLength = 6;
  static const int _maxAmount = 100000;
  static const int _selectedNavIndex = 2;

  _FlowStage _stage = _FlowStage.amountEntry;
  String _amountInput = '';
  String _pin = '';
  String _studentName = '';

  bool _isLoading = false;
  bool? _isSuccess;
  String _resultMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStudentProfile();
  }

  Future<void> _loadStudentProfile() async {
    try {
      final profile = await ProfileService.fetchProfile(
        role: 'student',
        id: widget.recipientNumber,
      );
      if (!mounted) return;
      setState(() => _studentName = profile.name);
    } catch (_) {}
  }

  bool _isValidAmountInput(String value) {
    final parsed = double.tryParse(value);
    return parsed != null && parsed >= 1 && parsed <= _maxAmount;
  }

  void _addAmountDigit(String digit) {
    if (!RegExp(r'^[\d.]$').hasMatch(digit)) return;

    if (digit == '.' && _amountInput.contains('.')) return;

    final current = _amountInput == '0' ? '' : _amountInput;
    final proposed = current.isEmpty ? digit : '$current$digit';

    final parsed = double.tryParse(proposed);
    if (parsed == null || parsed > _maxAmount) return;

    setState(() => _amountInput = proposed);
  }

  void _removeAmountDigit() {
    if (_amountInput.isEmpty) return;
    setState(
      () => _amountInput = _amountInput.substring(0, _amountInput.length - 1),
    );
  }

  void _handleAmountConfirm() {
    if (_isValidAmountInput(_amountInput)) {
      setState(() => _stage = _FlowStage.pinEntry);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enter an amount between 1 and 100,000.'),
      ),
    );
  }

  void _addPinDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    if (!RegExp(r'^\d$').hasMatch(digit)) return;

    setState(() => _pin += digit);

    if (_pin.length == _pinLength) {
      _submitPayment();
    }
  }

  void _removePinDigit() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submitPayment() async {
    final parsedAmount = double.tryParse(_amountInput);
    if (parsedAmount == null || parsedAmount < 1 || parsedAmount > _maxAmount) {
      return;
    }

    final amount = parsedAmount;

    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        Uri.parse(ApiConfig.url('cashier_confirm_payment.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'student_num': widget.recipientNumber,
          'pin': _pin,
          'amount': amount.toStringAsFixed(2),
          'bill_payment_id': widget.billPaymentId.toString(),
          'cashier_id': widget.cashierId,
          'description': (widget.description ?? '').trim(),
        },
      );
      await AppSessionService.instance.handleResponse(res);
      if (!mounted) return;

      final data = jsonDecode(res.body);

      if (data['status'] == 'success') {
        unawaited(TransactionNotificationService.refreshNow());
        setState(() {
          _isSuccess = true;
          _resultMessage =
              '\u20B1${amount.toStringAsFixed(2)} deducted.\nNew Balance: \u20B1${data['new_balance']}';
          _stage = _FlowStage.result;
        });
      } else if (data['status'] == 'locked') {
        setState(() {
          _isSuccess = false;
          _resultMessage = data['message'] ?? 'Account locked. Contact admin.';
          _stage = _FlowStage.result;
        });
      } else if (data['status'] == 'failed') {
        final int remaining = data['remaining_attempts'] ?? 0;
        final message = data['message']?.toString().trim();

        setState(() {
          _isSuccess = false;
          _resultMessage =
              '${(message == null || message.isEmpty) ? 'Invalid PIN' : message}\nAttempts left: $remaining';
          _stage = _FlowStage.result;
        });
      } else {
        setState(() {
          _isSuccess = false;
          _resultMessage = data['message'] ?? 'Payment failed';
          _stage = _FlowStage.result;
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _resultMessage = 'Connection error: $e';
        _stage = _FlowStage.result;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stageTitle = _stage == _FlowStage.amountEntry
        ? 'Enter Amount'
        : _stage == _FlowStage.pinEntry
            ? 'Student: enter your PIN'
            : _isSuccess == true
                ? 'Payment Successful'
                : 'Payment Failed';

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
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: _stage == _FlowStage.amountEntry
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: Text(
                    stageTitle,
                    textAlign: _stage == _FlowStage.amountEntry
                        ? TextAlign.left
                        : TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _brandRed,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
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
      case _FlowStage.amountEntry:
        return _buildAmountEntry();
      case _FlowStage.pinEntry:
        return _buildPinEntry();
      case _FlowStage.result:
        return _buildResult();
    }
  }

  Widget _buildAmountEntry() {
    final studentName =
        _studentName.trim().isEmpty ? 'Student Name Here' : _studentName.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account Information',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                ProfileAvatar(
                  role: 'student',
                  userId: widget.recipientNumber,
                  radius: 16,
                  fallbackIcon: Icons.person_outline,
                  iconColor: _brandRed,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studentName,
                        style: const TextStyle(
                          color: _brandRed,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.recipientNumber,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Amount To Pay',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              '\u20B1${_amountInput.isEmpty ? "0" : _amountInput}',
              style: const TextStyle(
                color: _brandRed,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildKeypad(
            onDigit: _addAmountDigit,
            onBack: _removeAmountDigit,
            horizontalPadding: 0,
            childAspectRatio: 1.8,
            keyFontSize: 18,
            useBackspaceIcon: true,
            keyBorderRadius: 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            keys: const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['.', '0', 'DEL'],
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleAmountConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _brandRed,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
            role: 'student',
            userId: widget.recipientNumber,
            radius: 38,
            fallbackIcon: Icons.person,
            iconColor: _brandRed,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            _studentName.isEmpty ? 'Student' : _studentName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Paying \u20B1${_amountInput.isEmpty ? "0" : _amountInput}',
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (i) {
              return Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: i < _pin.length ? Colors.white : Colors.transparent,
                  border: Border.all(color: Colors.white, width: 2),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          _buildKeypad(
            onDigit: _addPinDigit,
            onBack: _removePinDigit,
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
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
                    success ? 'Payment Successful' : 'Payment Failed',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: success ? Colors.green : Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
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
              onPressed: () {
                if (success) {
                  Navigator.pop(context, true);
                  return;
                }

                if (_resultMessage.toLowerCase().contains('locked')) {
                  Navigator.pop(context);
                  return;
                }

                setState(() {
                  _stage = _FlowStage.pinEntry;
                  _pin = '';
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
          const SizedBox(height: 88),
        ],
      ),
    );
  }

  Widget _buildKeypad({
    required Function(String) onDigit,
    VoidCallback? onBack,
    List<List<String>>? keys,
    double horizontalPadding = 12,
    double childAspectRatio = 1.5,
    double keyFontSize = 24,
    double keyBorderRadius = 8,
    double mainAxisSpacing = 12,
    double crossAxisSpacing = 12,
    bool useBackspaceIcon = false,
  }) {
    const defaultKeys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'DEL'],
    ];
    final keypadKeys = keys ?? defaultKeys;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
        children: keypadKeys.expand((row) {
          return row.map((key) {
            final isDelete = key == 'DEL';

            return GestureDetector(
              onTap: () {
                if (isDelete) {
                  onBack?.call();
                } else {
                  onDigit(key);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: const Color(0xFFD6CCE7),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(keyBorderRadius),
                ),
                child: Center(
                  child: isDelete && useBackspaceIcon
                      ? const Icon(
                          Icons.backspace_outlined,
                          color: _brandRed,
                          size: 22,
                        )
                      : Text(
                          key,
                          style: TextStyle(
                            fontSize: keyFontSize,
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
