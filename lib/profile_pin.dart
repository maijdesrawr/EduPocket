import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_pin_service.dart';

const Color _pinRed = Color(0xFFCF302E);
const Color _pinInk = Color(0xFF241F24);

class ProfilePinButton extends StatelessWidget {
  const ProfilePinButton({
    super.key,
    required this.role,
    required this.userId,
    this.foregroundColor = _pinRed,
    this.service,
  });

  final String role;
  final String userId;
  final Color foregroundColor;
  final ProfilePinApi? service;

  Future<void> _open(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfilePinPage(
          role: role,
          userId: userId,
          service: service,
        ),
      ),
    );
    if (!context.mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN settings updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 256,
        height: 44,
        child: ElevatedButton.icon(
          key: const Key('profile-change-pin-button'),
          onPressed: () => _open(context),
          icon: const Icon(Icons.pin_rounded, size: 20),
          label: const Text(
            'Change 6-digit PIN',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: foregroundColor,
            elevation: 7,
            shadowColor: const Color(0x66000000),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePinPage extends StatefulWidget {
  const ProfilePinPage({
    super.key,
    required this.role,
    required this.userId,
    this.service,
  });

  final String role;
  final String userId;
  final ProfilePinApi? service;

  @override
  State<ProfilePinPage> createState() => _ProfilePinPageState();
}

class _ProfilePinPageState extends State<ProfilePinPage> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _currentPin = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();

  late final ProfilePinApi _service;
  ProfilePinStatus? _status;
  bool _hidePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfilePinService();
  }

  @override
  void dispose() {
    _currentPassword.clear();
    _currentPin.clear();
    _newPin.clear();
    _confirmPin.clear();
    _currentPassword.dispose();
    _currentPin.dispose();
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !_passwordFormKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final status = await _service.getStatus(
        role: widget.role,
        userId: widget.userId,
        currentPassword: _currentPassword.text,
      );
      if (!mounted) return;
      setState(() => _status = status);
    } on ProfilePinException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'PIN management could not be started.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _changePin() async {
    FocusScope.of(context).unfocus();
    final status = _status;
    if (_submitting ||
        status == null ||
        !_pinFormKey.currentState!.validate()) {
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            key: const Key('pin-change-confirmation-dialog'),
            icon: const Icon(
              Icons.help_outline_rounded,
              color: _pinRed,
              size: 48,
            ),
            title: Text(status.hasPin ? 'Confirm PIN change' : 'Confirm PIN'),
            content: Text(
              status.hasPin
                  ? 'Are you sure you want to change your 6-digit PIN?'
                  : 'Are you sure you want to create this 6-digit PIN?',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                key: const Key('pin-change-cancel'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('pin-change-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: _pinRed),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _service.changePin(
        role: widget.role,
        userId: widget.userId,
        currentPassword: _currentPassword.text,
        currentPin: status.hasPin ? _currentPin.text : '',
        newPin: _newPin.text,
      );
      _currentPassword.clear();
      _currentPin.clear();
      _newPin.clear();
      _confirmPin.clear();
      if (!mounted) return;
      setState(() => _submitting = false);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF18864B),
            size: 54,
          ),
          title: const Text('PIN updated'),
          content: Text(result.message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: FilledButton.styleFrom(backgroundColor: _pinRed),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ProfilePinException catch (error) {
      _currentPin.clear();
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      _currentPin.clear();
      if (mounted) {
        setState(() => _error = 'Your PIN could not be changed.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validateSixDigits(String? value, String label) {
    if (!RegExp(r'^\d{6}$').hasMatch(value ?? '')) {
      return '$label must be exactly 6 digits';
    }
    return null;
  }

  InputDecoration _decoration({
    required String label,
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _pinRed, width: 2),
      ),
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required TextInputAction textInputAction,
    String? Function(String?)? validator,
    ValueChanged<String>? onSubmitted,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      maxLength: 6,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: _decoration(
        label: label,
        helperText: helperText,
      ).copyWith(counterText: ''),
      validator: validator ?? (value) => _validateSixDigits(value, label),
      onFieldSubmitted: onSubmitted,
    );
  }

  Widget _errorCard() {
    return Container(
      key: const Key('pin-error-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE7E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB4AB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _pinRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFF7A1B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FF),
        foregroundColor: _pinInk,
        elevation: 0,
        title: const Text('Change 6-digit PIN'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
          child: status == null
              ? Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.pin_rounded, color: _pinRed, size: 58),
                      const SizedBox(height: 16),
                      const Text(
                        'Verify your account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _pinInk,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter your current password before creating or changing your payment PIN.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF6F6871),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        key: const Key('pin-current-password-field'),
                        controller: _currentPassword,
                        obscureText: _hidePassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _checkStatus(),
                        decoration: _decoration(
                          label: 'Current Password',
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _hidePassword = !_hidePassword,
                            ),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Enter your current password'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 18),
                        _errorCard(),
                      ],
                      const SizedBox(height: 26),
                      _submitButton(
                        key: const Key('pin-status-submit'),
                        label: 'Continue',
                        onPressed: _checkStatus,
                      ),
                    ],
                  ),
                )
              : Form(
                  key: _pinFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset_rounded,
                          color: _pinRed, size: 58),
                      const SizedBox(height: 16),
                      Text(
                        status.hasPin ? 'Choose a new PIN' : 'Create your PIN',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _pinInk,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status.hasPin
                            ? 'Confirm your current PIN, then enter a new 6-digit PIN.'
                            : 'This account does not have a PIN yet. Create a 6-digit PIN now.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6F6871),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 26),
                      if (status.hasPin) ...[
                        _pinField(
                          controller: _currentPin,
                          label: 'Current PIN',
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _pinField(
                        controller: _newPin,
                        label: 'New PIN',
                        textInputAction: TextInputAction.next,
                        helperText: 'Use 6 numbers; do not repeat one digit.',
                        validator: (value) {
                          final invalid = _validateSixDigits(value, 'New PIN');
                          if (invalid != null) return invalid;
                          if (RegExp(r'^(\d)\1{5}$').hasMatch(value!)) {
                            return 'New PIN cannot repeat one digit';
                          }
                          if (status.hasPin && value == _currentPin.text) {
                            return 'New PIN must be different';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _pinField(
                        controller: _confirmPin,
                        label: 'Confirm New PIN',
                        textInputAction: TextInputAction.done,
                        validator: (value) {
                          final invalid =
                              _validateSixDigits(value, 'Confirmation PIN');
                          if (invalid != null) return invalid;
                          return value == _newPin.text
                              ? null
                              : 'PINs do not match';
                        },
                        onSubmitted: (_) => _changePin(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 18),
                        _errorCard(),
                      ],
                      const SizedBox(height: 26),
                      _submitButton(
                        key: const Key('pin-change-submit'),
                        label: status.hasPin ? 'Change PIN' : 'Create PIN',
                        onPressed: _changePin,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _submitButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      key: key,
      onPressed: _submitting ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _pinRed,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFD6C5C5),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _submitting
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
    );
  }
}
