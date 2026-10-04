import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'login_service.dart';

const Color _loginRed = Color(0xFFC9272C);
const Color _loginInk = Color(0xFF242124);

class LoginOtpPage extends StatefulWidget {
  const LoginOtpPage({
    super.key,
    required this.api,
    required this.challenge,
  });

  final LoginApi api;
  final LoginOtpChallenge challenge;

  @override
  State<LoginOtpPage> createState() => _LoginOtpPageState();
}

class _LoginOtpPageState extends State<LoginOtpPage> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();

  late LoginOtpChallenge _challenge;
  late int _sessionRemaining;
  late int _resendRemaining;
  Timer? _timer;
  bool _verifying = false;
  bool _requesting = false;
  String? _error;

  bool get _isEmail => _challenge.method == LoginOtpMethod.email;

  @override
  void initState() {
    super.initState();
    _applyChallenge(widget.challenge);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_sessionRemaining <= 0 && _resendRemaining <= 0) return;
      setState(() {
        if (_sessionRemaining > 0) _sessionRemaining--;
        if (_resendRemaining > 0) _resendRemaining--;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocusNode.requestFocus();
    });
  }

  void _applyChallenge(LoginOtpChallenge challenge) {
    _challenge = challenge;
    _sessionRemaining = challenge.expiresIn;
    _resendRemaining = challenge.resendAfter;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verifying || _requesting) return;
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the complete 6-digit code.');
      _codeFocusNode.requestFocus();
      return;
    }
    if (_sessionRemaining <= 0) {
      setState(() {
        _error =
            'This login verification request expired. Go back and log in again.';
      });
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final user = await widget.api.verifyOtp(
        challengeToken: _challenge.challengeToken,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(user);
    } on LoginException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _verificationError(error);
        _codeController.clear();
      });
      _codeFocusNode.requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Login verification could not be completed. Please try again.';
      });
      _codeFocusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _verificationError(LoginException error) {
    final attempts = error.attemptsRemaining;
    if (attempts == null || attempts <= 0) return error.message;
    final noun = attempts == 1 ? 'attempt' : 'attempts';
    return '${error.message} $attempts $noun remaining.';
  }

  Future<void> _requestMethod(
    LoginOtpMethod method, {
    bool isResend = false,
  }) async {
    if (_requesting || _verifying || _sessionRemaining <= 0) return;
    if (isResend && (_resendRemaining > 0 || !_isEmail)) return;
    if (!isResend && method == _challenge.method) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final updated = await widget.api.requestOtp(
        challenge: _challenge,
        method: method,
      );
      if (!mounted) return;
      setState(() {
        _applyChallenge(updated);
        _codeController.clear();
      });
      _codeFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isResend ? 'A new verification code was sent.' : updated.message,
          ),
        ),
      );
    } on LoginException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        if (error.retryAfter != null) {
          _resendRemaining = error.retryAfter!;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'The verification method could not be updated. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  String _methodTitle(LoginOtpMethod method) {
    return method == LoginOtpMethod.totp
        ? 'Google Authenticator'
        : 'Email code';
  }

  String _methodSubtitle(LoginOtpMethod method) {
    if (method == LoginOtpMethod.totp) {
      return 'Use the current code in your app';
    }
    final destination = _challenge.destinationMasked;
    return destination == null
        ? 'Send a code to your verified email'
        : 'Send a code to $destination';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _sessionRemaining <= 0;
    final destination = _challenge.destinationMasked;
    final instructions = _isEmail
        ? destination == null
            ? 'Enter the code sent to your verified email.'
            : 'Enter the code sent to $destination.'
        : 'Open Google Authenticator and enter the current code for EduPocket.';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAFA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFAFA),
        foregroundColor: _loginInk,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Secure login',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8E8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: _loginRed,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Verify it is you',
                      style: TextStyle(
                        color: _loginInk,
                        fontSize: 29,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      instructions,
                      style: const TextStyle(
                        color: Color(0xFF696267),
                        height: 1.45,
                        fontSize: 15,
                      ),
                    ),
                    if (_challenge.availableMethods.length > 1) ...[
                      const SizedBox(height: 26),
                      const Text(
                        'Verification method',
                        style: TextStyle(
                          color: _loginInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._challenge.availableMethods.map(
                        (method) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _LoginMethodCard(
                            key: Key('login-otp-method-${method.value}'),
                            selected: method == _challenge.method,
                            busy: _requesting,
                            icon: method == LoginOtpMethod.totp
                                ? Icons.phonelink_lock_rounded
                                : Icons.alternate_email_rounded,
                            title: _methodTitle(method),
                            subtitle: _methodSubtitle(method),
                            onTap:
                                expired ? null : () => _requestMethod(method),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 22),
                      _MethodSummary(
                        icon: _isEmail
                            ? Icons.alternate_email_rounded
                            : Icons.phonelink_lock_rounded,
                        title: _methodTitle(_challenge.method),
                      ),
                    ],
                    const SizedBox(height: 24),
                    LoginOtpCodeField(
                      key: const Key('login-otp-code-field'),
                      controller: _codeController,
                      focusNode: _codeFocusNode,
                      enabled: !_verifying && !_requesting && !expired,
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _verify(),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          expired ? Icons.error_outline : Icons.schedule,
                          size: 17,
                          color: expired ? _loginRed : const Color(0xFF756D72),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          expired
                              ? 'Verification request expired'
                              : 'Session expires in ${_formatTime(_sessionRemaining)}',
                          key: const Key('login-otp-expiry-label'),
                          style: TextStyle(
                            color:
                                expired ? _loginRed : const Color(0xFF756D72),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (_isEmail) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        key: const Key('login-otp-resend-button'),
                        onPressed: expired ||
                                _requesting ||
                                _verifying ||
                                _resendRemaining > 0
                            ? null
                            : () => _requestMethod(
                                  LoginOtpMethod.email,
                                  isResend: true,
                                ),
                        icon: _requesting
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 20),
                        label: Text(
                          _resendRemaining > 0
                              ? 'Resend available in ${_resendRemaining}s'
                              : 'Resend email code',
                        ),
                      ),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _error == null
                          ? const SizedBox.shrink()
                          : Container(
                              key: ValueKey(_error),
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE8E8),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: const Color(0xFFFFC8C8),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFF8F1E22),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      key: const Key('login-otp-error'),
                                      style: const TextStyle(
                                        color: Color(0xFF7D1B1F),
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton(
                      key: const Key('login-otp-verify-button'),
                      onPressed:
                          _verifying || _requesting || expired ? null : _verify,
                      style: FilledButton.styleFrom(
                        backgroundColor: _loginRed,
                        disabledBackgroundColor: const Color(0xFFE2B9BA),
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _verifying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Verify and continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                    if (expired) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back to login'),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: Color(0xFF817A7F),
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Never share this verification code with anyone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF817A7F),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginOtpCodeField extends StatelessWidget {
  const LoginOtpCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: _loginInk,
        fontSize: 27,
        fontWeight: FontWeight.w800,
        letterSpacing: 13,
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        hintText: '000000',
        hintStyle: const TextStyle(
          color: Color(0xFFD0C7CA),
          letterSpacing: 13,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD8D0D3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _loginRed, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE4DDDF)),
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class _LoginMethodCard extends StatelessWidget {
  const _LoginMethodCard({
    super.key,
    required this.selected,
    required this.busy,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final bool busy;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFEEEE) : Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? _loginRed : const Color(0xFFE0D9DB),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFFDCDD)
                      : const Color(0xFFF4F0F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: selected ? _loginRed : const Color(0xFF6E676B),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _loginInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF746D71),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy && !selected)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? _loginRed : const Color(0xFF958D91),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodSummary extends StatelessWidget {
  const _MethodSummary({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD2D3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _loginRed, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _loginInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: _loginRed, size: 20),
        ],
      ),
    );
  }
}
