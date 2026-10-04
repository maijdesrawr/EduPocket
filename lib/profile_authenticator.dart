import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_authenticator_service.dart';

const Color _authenticatorRed = Color(0xFFCF302E);
const Color _authenticatorInk = Color(0xFF241F24);

class ProfileAuthenticatorButton extends StatelessWidget {
  const ProfileAuthenticatorButton({
    super.key,
    required this.role,
    required this.userId,
    this.foregroundColor = _authenticatorRed,
    this.service,
  });

  final String role;
  final String userId;
  final Color foregroundColor;
  final ProfileAuthenticatorApi? service;

  Future<void> _open(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileAuthenticatorPage(
          role: role,
          userId: userId,
          service: service,
        ),
      ),
    );
    if (!context.mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Authenticator settings updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 256,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.phonelink_lock_rounded, size: 20),
          label: const Text(
            'Google Authenticator',
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

class ProfileAuthenticatorPage extends StatefulWidget {
  const ProfileAuthenticatorPage({
    super.key,
    required this.role,
    required this.userId,
    this.service,
  });

  final String role;
  final String userId;
  final ProfileAuthenticatorApi? service;

  @override
  State<ProfileAuthenticatorPage> createState() =>
      _ProfileAuthenticatorPageState();
}

class _ProfileAuthenticatorPageState extends State<ProfileAuthenticatorPage> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _authenticatorCode = TextEditingController();

  late final ProfileAuthenticatorApi _service;
  AuthenticatorManagementChallenge? _challenge;
  Timer? _expiryTimer;
  int _secondsRemaining = 0;
  bool _hidePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileAuthenticatorService();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _currentPassword.clear();
    _authenticatorCode.clear();
    _currentPassword.dispose();
    _authenticatorCode.dispose();
    super.dispose();
  }

  Future<void> _authenticateAndStart() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !_passwordFormKey.currentState!.validate()) return;

    var transientPassword = _currentPassword.text;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final status = await _service.getStatus(
        role: widget.role,
        userId: widget.userId,
        currentPassword: transientPassword,
      );
      if (!mounted) return;

      final action = status.isEnrolled
          ? AuthenticatorAction.remove
          : AuthenticatorAction.enroll;
      final challenge = await _service.requestManagement(
        role: widget.role,
        userId: widget.userId,
        action: action,
        currentPassword: transientPassword,
      );
      if (!mounted) return;
      _showChallenge(challenge);
    } on ProfileAuthenticatorException catch (error) {
      if (mounted) _showApiError(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Authenticator management could not be started.';
        });
      }
    } finally {
      transientPassword = '';
      _currentPassword.clear();
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showChallenge(AuthenticatorManagementChallenge challenge) {
    _expiryTimer?.cancel();
    _authenticatorCode.clear();
    setState(() {
      _challenge = challenge;
      _secondsRemaining = challenge.expiresIn;
      _error = null;
    });
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final challenge = _challenge;
    if (_submitting ||
        challenge == null ||
        !_codeFormKey.currentState!.validate()) {
      return;
    }
    if (_secondsRemaining <= 0) {
      setState(() {
        _error = 'This authenticator request expired. Go back and start again.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _service.verifyManagement(
        role: widget.role,
        userId: widget.userId,
        action: challenge.action,
        challengeToken: challenge.challengeToken,
        authenticatorCode: _authenticatorCode.text,
      );
      _authenticatorCode.clear();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF18864B),
            size: 54,
          ),
          title: Text(
            result.isEnrolled
                ? 'Authenticator linked'
                : 'Authenticator removed',
          ),
          content: Text(result.message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: FilledButton.styleFrom(
                backgroundColor: _authenticatorRed,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ProfileAuthenticatorException catch (error) {
      _authenticatorCode.clear();
      if (mounted) _showApiError(error);
    } catch (_) {
      _authenticatorCode.clear();
      if (mounted) {
        setState(() {
          _error = 'The authenticator code could not be verified.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showApiError(ProfileAuthenticatorException error) {
    final details = <String>[error.message];
    if (error.attemptsRemaining != null) {
      details.add(
        '${error.attemptsRemaining} verification attempts remaining.',
      );
    }
    if (error.retryAfter != null && error.retryAfter! > 0) {
      details.add('Try again in ${error.retryAfter} seconds.');
    }
    setState(() => _error = details.join(' '));
  }

  Future<void> _copySetupKey() async {
    final rawKey = _challenge?.setupKey;
    if (rawKey == null || rawKey.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: rawKey.replaceAll(RegExp(r'\s+'), '')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Setup key copied. Keep it private.'),
      ),
    );
  }

  Future<void> _openAuthenticator() async {
    final rawUri = _challenge?.otpauthUri;
    if (rawUri == null || rawUri.isEmpty) return;
    try {
      final uri = Uri.parse(rawUri);
      if (uri.scheme != 'otpauth') throw const FormatException();
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw const FormatException();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open an authenticator app. Scan the QR code or enter the setup key manually.',
          ),
        ),
      );
    }
  }

  String _groupSetupKey(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final groups = <String>[];
    for (var index = 0; index < normalized.length; index += 4) {
      final end = (index + 4).clamp(0, normalized.length);
      groups.add(normalized.substring(index, end));
    }
    return groups.join(' ');
  }

  String _timeLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FF),
        foregroundColor: _authenticatorInk,
        elevation: 0,
        title: Text(
          challenge == null
              ? 'Google Authenticator'
              : challenge.action == AuthenticatorAction.enroll
                  ? 'Set Up Authenticator'
                  : 'Remove Authenticator',
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 40),
          child: challenge == null
              ? _buildPasswordStep()
              : _buildChallengeStep(challenge),
        ),
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.phonelink_lock_rounded,
            size: 58,
            color: _authenticatorRed,
          ),
          const SizedBox(height: 14),
          const Text(
            'Manage Google Authenticator',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _authenticatorInk,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Authenticator codes protect password changes and other sensitive account actions. They are not currently required when signing in.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6F6871), height: 1.4),
          ),
          const SizedBox(height: 28),
          TextFormField(
            key: const Key('authenticatorCurrentPassword'),
            controller: _currentPassword,
            obscureText: _hidePassword,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _authenticateAndStart(),
            decoration: InputDecoration(
              labelText: 'Current Password',
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: _authenticatorRed, width: 2),
              ),
              suffixIcon: IconButton(
                tooltip: _hidePassword ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() => _hidePassword = !_hidePassword);
                },
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            validator: (value) => value == null || value.isEmpty
                ? 'Enter your current password'
                : null,
          ),
          const SizedBox(height: 14),
          const Text(
            'Your password is checked by the server and is not saved on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6F6871), fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _errorCard(),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('authenticatorContinue'),
            onPressed: _submitting ? null : _authenticateAndStart,
            style: FilledButton.styleFrom(
              backgroundColor: _authenticatorRed,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeStep(AuthenticatorManagementChallenge challenge) {
    final isEnrollment = challenge.action == AuthenticatorAction.enroll;
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isEnrollment
                ? Icons.qr_code_2_rounded
                : Icons.phonelink_erase_rounded,
            size: 54,
            color: _authenticatorRed,
          ),
          const SizedBox(height: 12),
          Text(
            isEnrollment
                ? 'Set up Google Authenticator'
                : 'Verify before removal',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _authenticatorInk,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            challenge.message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6F6871), height: 1.4),
          ),
          if (isEnrollment) ...[
            const SizedBox(height: 22),
            Center(
              child: Semantics(
                label: 'Google Authenticator setup QR code',
                image: true,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7DDE7)),
                  ),
                  child: QrImageView(
                    key: const Key('authenticatorQrCode'),
                    data: challenge.otpauthUri!,
                    version: QrVersions.auto,
                    size: 210,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Cannot scan the QR code?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Choose Enter a setup key in Google Authenticator and enter this key:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6F6871), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE7DDE7)),
              ),
              child: SelectableText(
                _groupSetupKey(challenge.setupKey!),
                key: const Key('authenticatorSetupKey'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
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
                      backgroundColor: _authenticatorRed,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open App'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Never share this QR code or setup key. EduPocket will not show it again after setup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8C2727),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE5F5EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF18864B),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Authenticator linked',
                    style: TextStyle(
                      color: Color(0xFF155F38),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7E7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Removing the authenticator disables this verification method. Enter a current code to confirm removal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF7A1B1B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextFormField(
            key: const Key('authenticatorCode'),
            controller: _authenticatorCode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onFieldSubmitted: (_) => _verify(),
            decoration: const InputDecoration(
              labelText: '6-digit authenticator code',
              hintText: '000000',
              counterText: '',
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _authenticatorRed, width: 2),
              ),
            ),
            maxLength: 6,
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : 'Enter the complete 6-digit code',
          ),
          const SizedBox(height: 12),
          Text(
            _secondsRemaining > 0
                ? 'Request expires in ${_timeLabel(_secondsRemaining)}'
                : 'Request expired',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _secondsRemaining > 0
                  ? const Color(0xFF6F6871)
                  : _authenticatorRed,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorCard(),
          ],
          const SizedBox(height: 22),
          FilledButton(
            key: const Key('authenticatorVerify'),
            onPressed: _submitting ? null : _verify,
            style: FilledButton.styleFrom(
              backgroundColor: _authenticatorRed,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    isEnrollment
                        ? 'Link Authenticator'
                        : 'Remove Authenticator',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
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
    );
  }
}
