import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'student_dashboard.dart';
import 'student_graphs.dart' as graphs;
import 'student_profile.dart';
import 'student_topups.dart';
import 'student_transfer_service.dart';

class StudentTransferScreen extends StatefulWidget {
  const StudentTransferScreen({
    super.key,
    required this.name,
    required this.id,
    this.service,
  });

  final String name;
  final String id;
  final StudentTransferApi? service;

  @override
  State<StudentTransferScreen> createState() => _StudentTransferScreenState();
}

class _StudentTransferScreenState extends State<StudentTransferScreen> {
  static const _primaryRed = Color(0xFFC62828);
  static const _deepRed = Color(0xFFB71C1C);
  static const _fieldPink = Color(0xFFF4C0B7);
  static const _successGreen = Color(0xFF129D37);
  static const _minAmount = 1.0;
  static const _maxAmount = 50000.0;

  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _pinController = TextEditingController();
  late final StudentTransferApi _service;

  double? _balance;
  bool _loadingBalance = true;
  bool _submitting = false;
  bool _hidePin = true;
  String? _pendingRequestId;
  String? _pendingFingerprint;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StudentTransferService();
    for (final controller in [
      _recipientController,
      _amountController,
      _pinController,
    ]) {
      controller.addListener(_invalidateChangedRequest);
    }
    unawaited(
      AppSessionService.instance.recordActivity(
        'fund_transfer_view',
        details: const {'screen': 'student_transfer'},
      ),
    );
    _loadBalance();
  }

  @override
  void dispose() {
    for (final controller in [
      _recipientController,
      _amountController,
      _pinController,
    ]) {
      controller.removeListener(_invalidateChangedRequest);
      controller.dispose();
    }
    super.dispose();
  }

  String get _formFingerprint => [
        _recipientController.text.trim().toUpperCase(),
        _amountController.text.trim(),
      ].join('\u0000');

  void _invalidateChangedRequest() {
    if (_pendingFingerprint != null &&
        _pendingFingerprint != _formFingerprint) {
      _pendingFingerprint = null;
      _pendingRequestId = null;
    }
  }

  Future<void> _loadBalance() async {
    if (mounted) setState(() => _loadingBalance = true);
    try {
      final balance = await _service.fetchBalance(studentId: widget.id);
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _loadingBalance = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBalance = false);
    }
  }

  Future<void> _confirmTransfer() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;

    final recipient = _recipientController.text.trim();
    final amount = double.parse(_amountController.text.trim());
    unawaited(
      AppSessionService.instance.recordActivity(
        'fund_transfer_confirmation_view',
        details: {
          'recipient_id': recipient,
          'amount': amount.toStringAsFixed(2),
        },
      ),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('student-transfer-confirmation-dialog'),
        title: const Text('Confirm fund transfer'),
        content: Text(
          'Send ${_formatCurrency(amount)} to student $recipient?',
        ),
        actions: [
          TextButton(
            key: const Key('student-transfer-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('student-transfer-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (confirmed != true) {
      unawaited(
        AppSessionService.instance.recordActivity(
          'fund_transfer_cancelled',
          details: {'stage': 'confirmation'},
        ),
      );
      return;
    }
    await _submitTransfer(recipient, amount);
  }

  Future<void> _submitTransfer(String recipient, double amount) async {
    final fingerprint = _formFingerprint;
    if (_pendingFingerprint != fingerprint || _pendingRequestId == null) {
      _pendingFingerprint = fingerprint;
      _pendingRequestId = const Uuid().v4();
    }
    final requestId = _pendingRequestId!;

    setState(() => _submitting = true);
    try {
      final result = await _service.transfer(
        senderId: widget.id,
        recipientId: recipient,
        amount: amount.toStringAsFixed(2),
        pin: _pinController.text,
        clientRequestId: requestId,
      );
      if (!mounted) return;

      setState(() {
        _balance = result.newBalance;
        _submitting = false;
      });
      _recipientController.clear();
      _amountController.clear();
      _pinController.clear();
      _pendingFingerprint = null;
      _pendingRequestId = null;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          key: const Key('student-transfer-success-dialog'),
          icon: const Icon(
            Icons.check_circle_rounded,
            color: _successGreen,
            size: 54,
          ),
          title: const Text('Transfer successful'),
          content: Text(
            '${result.message}\n\nReference: ${result.transferId}\nNew balance: ${_formatCurrency(result.newBalance)}',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              key: const Key('student-transfer-done'),
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on StudentTransferException catch (error) {
      if (!error.outcomeUnknown) {
        _pendingFingerprint = null;
        _pendingRequestId = null;
      }
      _pinController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      _pinController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The transfer could not be completed. Try again.'),
        ),
      );
    } finally {
      if (mounted && _submitting) setState(() => _submitting = false);
    }
  }

  void _onNavTap(int index) {
    if (index == 3) return;
    late final Widget destination;
    switch (index) {
      case 0:
        destination = StudentDashboard(name: widget.name, id: widget.id);
        break;
      case 1:
        destination = graphs.StudentGraphs(name: widget.name, id: widget.id);
        break;
      case 2:
        destination = StudentTopUps(name: widget.name, id: widget.id);
        break;
      case 4:
        destination = StudentProfile(id: widget.id, name: widget.name);
        break;
      default:
        return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Image.asset('assets/redlogo.png', height: 74),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _deepRed,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ProfileAvatar(
                    role: 'student',
                    userId: widget.id,
                    radius: 36,
                    fallbackIcon: Icons.person,
                    iconColor: _primaryRed,
                    backgroundColor: const Color(0xFFE7F0FF),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildBalanceCard(),
            const SizedBox(height: 14),
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
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Send to another student',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Enter the recipient, at least ₱1.00, and your '
                          '6-digit PIN.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          key: const Key('student-transfer-recipient'),
                          controller: _recipientController,
                          label: 'Recipient student number',
                          icon: Icons.person_search_outlined,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9._-]'),
                            ),
                            LengthLimitingTextInputFormatter(20),
                          ],
                          validator: (value) {
                            final recipient = value?.trim() ?? '';
                            if (recipient.isEmpty) {
                              return 'Recipient student number is required.';
                            }
                            if (recipient.toUpperCase() ==
                                widget.id.trim().toUpperCase()) {
                              return 'You cannot transfer funds to yourself.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          key: const Key('student-transfer-amount'),
                          controller: _amountController,
                          label: 'Amount',
                          icon: Icons.payments_outlined,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d{0,6}(?:\.\d{0,2})?'),
                            ),
                          ],
                          helperText: 'Minimum transfer amount: ₱1.00',
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            final input = value?.trim() ?? '';
                            if (input.isEmpty) {
                              return 'Amount is required.';
                            }
                            final amount = double.tryParse(input);
                            if (amount == null ||
                                !amount.isFinite ||
                                amount < _minAmount) {
                              return 'Amount must be at least ₱1.00. Zero and '
                                  'negative amounts are not allowed.';
                            }
                            if (amount > _maxAmount) {
                              return 'The maximum transfer is ₱50,000.00.';
                            }
                            final balance = _balance;
                            if (balance != null && amount > balance) {
                              return 'Insufficient wallet balance.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          key: const Key('student-transfer-pin'),
                          controller: _pinController,
                          label: '6-digit PIN',
                          icon: Icons.lock_outline_rounded,
                          keyboardType: TextInputType.number,
                          obscureText: _hidePin,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          suffixIcon: IconButton(
                            tooltip: _hidePin ? 'Show PIN' : 'Hide PIN',
                            onPressed: () =>
                                setState(() => _hidePin = !_hidePin),
                            icon: Icon(
                              _hidePin
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: _primaryRed,
                            ),
                          ),
                          validator: (value) =>
                              RegExp(r'^\d{6}$').hasMatch(value ?? '')
                                  ? null
                                  : 'Enter your 6-digit PIN.',
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            key: const Key('student-transfer-submit'),
                            onPressed: _submitting ? null : _confirmTransfer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _primaryRed,
                              disabledBackgroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: _primaryRed,
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _StudentBottomNav(
        selectedIndex: 3,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _fieldPink),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: _primaryRed),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Available balance',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _loadingBalance
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primaryRed,
                  ),
                )
              : Text(
                  _balance == null ? 'Unavailable' : _formatCurrency(_balance!),
                  style: const TextStyle(
                    color: _successGreen,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? helperText,
    AutovalidateMode? autovalidateMode,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      validator: validator,
      autovalidateMode: autovalidateMode,
      enabled: !_submitting,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: _primaryRed),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        errorMaxLines: 2,
        errorStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _fieldPink, width: 2),
        ),
      ),
    );
  }

  static String _formatCurrency(double value) {
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '₱$whole.${parts.last}';
  }
}

class _StudentBottomNav extends StatelessWidget {
  static const _primaryRed = Color(0xFFC62828);
  static const _deepRed = Color(0xFFB71C1C);

  const _StudentBottomNav({
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.home_outlined,
      Icons.bar_chart_rounded,
      Icons.account_balance_wallet_outlined,
      Icons.swap_horiz_rounded,
      Icons.person_outline_rounded,
    ];
    return Container(
      color: _primaryRed,
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
          children: List.generate(icons.length, (index) {
            final selected = selectedIndex == index;
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: selected ? _deepRed : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icons[index],
                  color: selected ? Colors.white : _primaryRed,
                  size: 25,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
