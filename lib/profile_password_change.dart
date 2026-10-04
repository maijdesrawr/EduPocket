import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'app_session_service.dart';
import 'login.dart';

const Color _passwordRed = Color(0xFFCF302E);
const Color _passwordInk = Color(0xFF241F24);

class ProfilePasswordChangeButton extends StatelessWidget {
  final String role;
  final String userId;
  final String userName;
  final Color foregroundColor;

  const ProfilePasswordChangeButton({
    super.key,
    required this.role,
    required this.userId,
    required this.userName,
    this.foregroundColor = _passwordRed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 240,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfilePasswordChangePage(
                  role: role,
                  userId: userId,
                  userName: userName,
                ),
              ),
            );
          },
          icon: const Icon(Icons.lock_reset_rounded),
          label: const Text(
            'Change Password',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: foregroundColor,
            elevation: 4,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePasswordChangePage extends StatefulWidget {
  final String role;
  final String userId;
  final String userName;

  const ProfilePasswordChangePage({
    super.key,
    required this.role,
    required this.userId,
    required this.userName,
  });

  @override
  State<ProfilePasswordChangePage> createState() =>
      _ProfilePasswordChangePageState();
}

class _ProfilePasswordChangePageState extends State<ProfilePasswordChangePage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;
  bool _submitting = false;
  String _method = 'authenticator';
  String? _serverMessage;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  bool _isStrongPassword(String value) {
    return value.length >= 8 &&
        value.length <= 72 &&
        RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[a-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'''[!@#$%^&*(),.?":{}|<>]''').hasMatch(value);
  }

  Future<Map<String, dynamic>> _decodeResponse(http.Response response) async {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {}
    throw const FormatException('The server returned an invalid response');
  }

  Future<void> _requestChange() async {
    FocusScope.of(context).unfocus();
    setState(() => _serverMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('request_password_change.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'role': widget.role,
          'id': widget.userId,
          'current_password': _currentPassword.text,
          'new_password': _newPassword.text,
          'method': _method,
          'email': '',
        },
      ).timeout(const Duration(seconds: 20));
      await AppSessionService.instance.handleResponse(response);
      final data = await _decodeResponse(response);
      if (!mounted) return;

      if (response.statusCode != 200 || data['status'] != 'success') {
        setState(() {
          _serverMessage = data['message']?.toString() ??
              'Unable to start password verification';
        });
        return;
      }

      final token = data['challenge_token']?.toString() ?? '';
      if (token.isEmpty) {
        setState(
            () => _serverMessage = 'The server did not create a challenge');
        return;
      }

      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PasswordOtpVerificationPage(
            challengeToken: token,
            method: data['method']?.toString() ?? _method,
            destination: data['destination']?.toString(),
            expiresIn:
                int.tryParse(data['expires_in']?.toString() ?? '') ?? 300,
            requiresTotpSetup: data['requires_totp_setup'] == true ||
                data['requires_totp_setup']?.toString() == '1',
            totpSetupKey: data['totp_setup_key']?.toString(),
            otpauthUri: data['otpauth_uri']?.toString(),
          ),
        ),
      );
    } on TimeoutException {
      if (mounted) {
        setState(() => _serverMessage = 'The server took too long to respond');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _serverMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _serverMessage = 'Unable to connect to EduPocket');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _passwordDecoration({
    required String label,
    required bool hidden,
    required VoidCallback toggle,
  }) {
    return InputDecoration(
      labelText: label,
      border: const UnderlineInputBorder(),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _passwordRed, width: 2),
      ),
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: toggle,
        icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FF),
        foregroundColor: _passwordInk,
        elevation: 0,
        title: const Text('Change Password'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Create your new password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _passwordInk,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.userName}, verify your current password first. '
                  'Your new password cannot match one you used before.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6F6871), height: 1.4),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _currentPassword,
                  obscureText: _hideCurrent,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: _passwordDecoration(
                    label: 'Current Password',
                    hidden: _hideCurrent,
                    toggle: () => setState(() => _hideCurrent = !_hideCurrent),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Enter your current password'
                      : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _newPassword,
                  obscureText: _hideNew,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: _passwordDecoration(
                    label: 'New Password',
                    hidden: _hideNew,
                    toggle: () => setState(() => _hideNew = !_hideNew),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) return 'Enter a new password';
                    if (password != password.trim()) {
                      return 'Password cannot start or end with spaces';
                    }
                    if (password == _currentPassword.text) {
                      return 'This password has already been used';
                    }
                    if (!_isStrongPassword(password)) {
                      return 'Use 8-72 characters with upper/lowercase, number, and symbol';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: _hideConfirm,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _requestChange(),
                  decoration: _passwordDecoration(
                    label: 'Confirm Password',
                    hidden: _hideConfirm,
                    toggle: () => setState(() => _hideConfirm = !_hideConfirm),
                  ),
                  validator: (value) => value != _newPassword.text
                      ? 'Passwords do not match'
                      : null,
                ),
                const SizedBox(height: 12),
                const _PasswordRequirements(),
                const SizedBox(height: 28),
                const Text(
                  'Confirm through',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _VerificationMethodCard(
                  selected: _method == 'authenticator',
                  icon: Icons.security_rounded,
                  title: 'Google Authenticator',
                  subtitle: 'Use a secure 6-digit code, even when offline',
                  badge: 'Recommended',
                  onTap: () => setState(() {
                    _method = 'authenticator';
                    _serverMessage = null;
                  }),
                ),
                const SizedBox(height: 10),
                _VerificationMethodCard(
                  selected: _method == 'email',
                  icon: Icons.alternate_email_rounded,
                  title: 'Email OTP',
                  subtitle: 'Send a 6-digit code to your verified email',
                  onTap: () => setState(() {
                    _method = 'email';
                    _serverMessage = null;
                  }),
                ),
                if (_method == 'email') ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EDF4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          color: _passwordRed,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The code will be sent only to the verified email saved in your Profile. If you have not verified one yet, return to Profile and choose Add Verified Email.',
                            style: TextStyle(
                              color: Color(0xFF5E565F),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_serverMessage != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE7E7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB4AB)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: _passwordRed),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _serverMessage!,
                            style: const TextStyle(
                              color: Color(0xFF7A1B1B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _submitting ? null : _requestChange,
                  style: FilledButton.styleFrom(
                    backgroundColor: _passwordRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD6C5C5),
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
                      : const Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordOtpVerificationPage extends StatefulWidget {
  final String challengeToken;
  final String method;
  final String? destination;
  final int expiresIn;
  final bool requiresTotpSetup;
  final String? totpSetupKey;
  final String? otpauthUri;

  const PasswordOtpVerificationPage({
    super.key,
    required this.challengeToken,
    required this.method,
    required this.expiresIn,
    this.destination,
    this.requiresTotpSetup = false,
    this.totpSetupKey,
    this.otpauthUri,
  });

  @override
  State<PasswordOtpVerificationPage> createState() =>
      _PasswordOtpVerificationPageState();
}

class _PasswordOtpVerificationPageState
    extends State<PasswordOtpVerificationPage> {
  final _code = TextEditingController();
  Timer? _timer;
  late int _secondsRemaining;
  int _resendRemaining = 60;
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  late String _challengeToken;

  bool get _isEmail => widget.method == 'email';

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.expiresIn;
    _challengeToken = widget.challengeToken;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) _secondsRemaining--;
        if (_resendRemaining > 0) _resendRemaining--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> body,
  ) async {
    final response = await http
        .post(
          Uri.parse(ApiConfig.url(endpoint)),
          headers: AppSessionService.instance.authorizationHeaders,
          body: body,
        )
        .timeout(const Duration(seconds: 20));
    await AppSessionService.instance.handleResponse(response);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {}
    throw const FormatException('The server returned an invalid response');
  }

  String _timeLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  Future<void> _openAuthenticator() async {
    final rawUri = widget.otpauthUri;
    if (rawUri == null || rawUri.isEmpty) return;
    try {
      final opened = await launchUrl(
        Uri.parse(rawUri),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _error =
            'Could not open Google Authenticator. Enter the setup key manually.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not open Google Authenticator. Enter the setup key manually.');
      }
    }
  }

  Future<void> _copySetupKey() async {
    final key = widget.totpSetupKey;
    if (key == null || key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: key.replaceAll(' ', '')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Authenticator setup key copied')),
    );
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = 'Enter the complete 6-digit code');
      return;
    }
    if (_secondsRemaining <= 0) {
      setState(() => _error = 'This verification code has expired');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final data = await _post('verify_password_change.php', {
        'challenge_token': _challengeToken,
        'code': _code.text,
      });
      if (!mounted) return;
      if (data['status'] != 'success') {
        setState(() {
          _error = data['message']?.toString() ?? 'The code is invalid';
          _code.clear();
        });
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF18864B),
            size: 54,
          ),
          title: const Text('Password changed'),
          content: const Text(
            'Your password was updated securely. Please sign in again using your new password.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: FilledButton.styleFrom(backgroundColor: _passwordRed),
              child: const Text('Back to Login'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'The server took too long to respond');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to connect to EduPocket');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (!_isEmail || _resendRemaining > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final data = await _post('resend_password_change_otp.php', {
        'challenge_token': _challengeToken,
      });
      if (!mounted) return;
      if (data['status'] != 'success') {
        setState(() =>
            _error = data['message']?.toString() ?? 'Unable to resend OTP');
        return;
      }
      setState(() {
        final updatedToken = data['challenge_token']?.toString();
        if (updatedToken != null && updatedToken.isNotEmpty) {
          _challengeToken = updatedToken;
        }
        _secondsRemaining =
            int.tryParse(data['expires_in']?.toString() ?? '') ?? 300;
        _resendRemaining = 60;
        _code.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new verification code was sent')),
      );
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'The server took too long to respond');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to resend the code');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    final subtitle = _isEmail
        ? 'We sent a 6-digit code${destination == null || destination.isEmpty ? '' : ' to $destination'}.'
        : widget.requiresTotpSetup
            ? 'Add EduPocket to Google Authenticator, then enter the 6-digit code it generates.'
            : 'Enter the current 6-digit code from Google Authenticator.';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FF),
        foregroundColor: _passwordInk,
        elevation: 0,
        title: const Text('Verification'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Confirm it is you',
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  color: _passwordInk,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF6F6871), height: 1.4),
              ),
              if (widget.requiresTotpSetup) ...[
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE7DDE7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Set up Google Authenticator',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Open Authenticator on this phone. If it does not open, copy and enter this setup key manually:',
                        style:
                            TextStyle(color: Color(0xFF6F6871), height: 1.35),
                      ),
                      if (widget.otpauthUri?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Center(
                            child: Semantics(
                          label: 'Google Authenticator setup QR code',
                          image: true,
                          child: QrImageView(
                            key: const Key('verificationAuthenticatorQrCode'),
                            data: widget.otpauthUri!,
                            version: QrVersions.auto,
                            size: 210,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        )),
                        const Text(
                            'Scan this QR code using Authenticator on another device, or use the options below on this phone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      SelectableText(
                        widget.totpSetupKey ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _copySetupKey,
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('Copy Key'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _openAuthenticator,
                              style: FilledButton.styleFrom(
                                backgroundColor: _passwordRed,
                              ),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Open App'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 30),
              _OtpCodeField(controller: _code, onComplete: _verify),
              const SizedBox(height: 14),
              Text(
                _secondsRemaining > 0
                    ? 'Code expires in ${_timeLabel(_secondsRemaining)}'
                    : 'Code expired',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _secondsRemaining > 0
                      ? const Color(0xFF6F6871)
                      : _passwordRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isEmail) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed:
                      _resendRemaining == 0 && !_resending ? _resend : null,
                  child: _resending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _resendRemaining > 0
                              ? 'Resend OTP in ${_resendRemaining}s'
                              : 'Resend OTP',
                        ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE7E7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7A1B1B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _verifying ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: _passwordRed,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
                        'Verify',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpCodeField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onComplete;

  const _OtpCodeField({required this.controller, required this.onComplete});

  @override
  State<_OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<_OtpCodeField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return Semantics(
      textField: true,
      label: 'Six digit verification code',
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        child: SizedBox(
          height: 58,
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final width = (constraints.maxWidth - gap * 5) / 6;
                    return Row(
                      children: List.generate(6, (index) {
                        final active = value.length == index ||
                            (value.length == 6 && index == 5);
                        return Padding(
                          padding: EdgeInsets.only(right: index == 5 ? 0 : gap),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: width,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: active
                                    ? _passwordRed
                                    : const Color(0xFFD7CDD7),
                                width: active ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              index < value.length ? value[index] : '',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0.01,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onSubmitted: (_) => widget.onComplete(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationMethodCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _VerificationMethodCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFECEB) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _passwordRed : const Color(0xFFE3D9E3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? _passwordRed : const Color(0xFF6F6871)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _passwordRed,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF6F6871),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _passwordRed : const Color(0xFF8C838C),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordRequirements extends StatelessWidget {
  const _PasswordRequirements();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Use 8-72 characters with an uppercase letter, lowercase letter, number, and special symbol.',
      style: TextStyle(color: Color(0xFF6F6871), fontSize: 12, height: 1.35),
    );
  }
}
