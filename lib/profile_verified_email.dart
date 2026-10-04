import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_email_service.dart';

const Color _emailRed = Color(0xFFCF302E);
const Color _emailInk = Color(0xFF241F24);

class ProfileVerifiedEmailButton extends StatefulWidget {
  final String role;
  final String userId;
  final String userName;
  final Color foregroundColor;
  final Color statusColor;
  final ProfileEmailApi? service;

  const ProfileVerifiedEmailButton({
    super.key,
    required this.role,
    required this.userId,
    required this.userName,
    this.foregroundColor = _emailRed,
    this.statusColor = Colors.white,
    this.service,
  });

  @override
  State<ProfileVerifiedEmailButton> createState() =>
      _ProfileVerifiedEmailButtonState();
}

class _ProfileVerifiedEmailButtonState
    extends State<ProfileVerifiedEmailButton> {
  late ProfileEmailApi _service;
  VerifiedEmailStatus? _status;
  bool _loading = true;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileEmailService();
    _loadStatus();
  }

  @override
  void didUpdateWidget(covariant ProfileVerifiedEmailButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _service = widget.service ?? ProfileEmailService();
    }
    if (oldWidget.role != widget.role ||
        oldWidget.userId != widget.userId ||
        oldWidget.service != widget.service) {
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    final generation = ++_requestGeneration;
    if (mounted) setState(() => _loading = true);
    try {
      final status = await _service.getStatus(
        role: widget.role,
        id: widget.userId,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openEmailPage() async {
    if (_loading) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileVerifiedEmailPage(
          role: widget.role,
          userId: widget.userId,
          userName: widget.userName,
          service: _service,
          initialStatus: _status,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verified email updated successfully')),
      );
    }
    await _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final verified = _status?.verified == true;
    final label = _loading
        ? 'Checking Email'
        : verified
            ? 'Change Verified Email'
            : 'Add Verified Email';
    final masked = _status?.emailMasked;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 240,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _openEmailPage,
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.foregroundColor,
                      ),
                    )
                  : Icon(verified
                      ? Icons.mark_email_read_rounded
                      : Icons.alternate_email_rounded),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: widget.foregroundColor,
                disabledBackgroundColor: const Color(0xFFF2EAEA),
                disabledForegroundColor: widget.foregroundColor,
                elevation: 4,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (verified && masked != null) ...[
            const SizedBox(height: 6),
            Text(
              'Verified: $masked',
              style: TextStyle(
                color: widget.statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileVerifiedEmailPage extends StatefulWidget {
  final String role;
  final String userId;
  final String userName;
  final ProfileEmailApi? service;
  final VerifiedEmailStatus? initialStatus;

  const ProfileVerifiedEmailPage({
    super.key,
    required this.role,
    required this.userId,
    required this.userName,
    this.service,
    this.initialStatus,
  });

  @override
  State<ProfileVerifiedEmailPage> createState() =>
      _ProfileVerifiedEmailPageState();
}

class _ProfileVerifiedEmailPageState extends State<ProfileVerifiedEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _email = TextEditingController();

  late final ProfileEmailApi _service;
  Timer? _requestRetryTimer;
  VerifiedEmailStatus? _status;
  bool _loadingStatus = false;
  bool _submitting = false;
  bool _hidePassword = true;
  String? _message;
  int? _attemptsRemaining;
  int _requestRetryRemaining = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileEmailService();
    _status = widget.initialStatus;
    if (_status == null) _loadStatus();
  }

  @override
  void dispose() {
    _requestRetryTimer?.cancel();
    _currentPassword.dispose();
    _email.dispose();
    super.dispose();
  }

  void _applyRequestError(ProfileEmailException error) {
    _requestRetryTimer?.cancel();
    final retryAfter = error.retryAfter ?? 0;
    setState(() {
      _message = error.message;
      if (error.attemptsRemaining != null) {
        _attemptsRemaining = error.attemptsRemaining;
      }
      _requestRetryRemaining = retryAfter;
    });

    if (retryAfter <= 0) return;
    _requestRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_requestRetryRemaining <= 1) {
        timer.cancel();
        setState(() => _requestRetryRemaining = 0);
        return;
      }
      setState(() => _requestRetryRemaining--);
    });
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _message = null;
    });
    try {
      final status = await _service.getStatus(
        role: widget.role,
        id: widget.userId,
      );
      if (!mounted) return;
      setState(() => _status = status);
    } on ProfileEmailException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Unable to load email status.');
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _requestCode() async {
    FocusScope.of(context).unfocus();
    if (_submitting || _requestRetryRemaining > 0) return;
    setState(() {
      _message = null;
      _attemptsRemaining = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final request = await _service.requestVerification(
        role: widget.role,
        id: widget.userId,
        currentPassword: _currentPassword.text,
        email: _email.text.trim(),
      );
      if (!mounted) return;
      _currentPassword.clear();

      if (request.verificationComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(request.message)),
        );
        Navigator.of(context).pop(true);
        return;
      }

      final challenge = request.challenge;
      if (challenge == null) {
        setState(() {
          _message = 'The server did not create a verification request.';
        });
        return;
      }

      final result = await Navigator.of(context).push<EmailVerificationResult>(
        MaterialPageRoute(
          builder: (_) => ProfileEmailOtpPage(
            challenge: challenge,
            service: _service,
          ),
        ),
      );
      if (!mounted || result == null) return;
      Navigator.of(context).pop(true);
    } on ProfileEmailException catch (error) {
      if (mounted) _applyRequestError(error);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to request a verification code.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChanging = _status?.verified == true;
    final masked = _status?.emailMasked;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FF),
        foregroundColor: _emailInk,
        elevation: 0,
        title: Text(isChanging ? 'Change Email' : 'Add Email'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  isChanging
                      ? Icons.mark_email_read_rounded
                      : Icons.alternate_email_rounded,
                  size: 52,
                  color: _emailRed,
                ),
                const SizedBox(height: 14),
                Text(
                  isChanging ? 'Change verified email' : 'Verify your email',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _emailInk,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isChanging && masked != null
                      ? 'Your current verified email is $masked. Enter a new address and confirm the code we send.'
                      : '${widget.userName}, add an email address for secure account verification and password changes.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6F6871),
                    height: 1.4,
                  ),
                ),
                if (_loadingStatus) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(color: _emailRed),
                ],
                const SizedBox(height: 30),
                TextFormField(
                  controller: _currentPassword,
                  obscureText: _hidePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip:
                          _hidePassword ? 'Show password' : 'Hide password',
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                      icon: Icon(_hidePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Enter your current password'
                      : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _requestCode(),
                  decoration: InputDecoration(
                    labelText:
                        isChanging ? 'New Email Address' : 'Email Address',
                    hintText: 'name@example.com',
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = (value ?? '').trim();
                    if (email.isEmpty) return 'Enter your email address';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                const _EmailSecurityNote(),
                if (_message != null) ...[
                  const SizedBox(height: 18),
                  _EmailMessage(message: _message!),
                ],
                if (_attemptsRemaining != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Attempts remaining: $_attemptsRemaining',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6F6871),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_requestRetryRemaining > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Try again in $_requestRetryRemaining s',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _emailRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _submitting ||
                          _loadingStatus ||
                          _requestRetryRemaining > 0
                      ? null
                      : _requestCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: _emailRed,
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
                      : Text(
                          _requestRetryRemaining > 0
                              ? 'Try again in $_requestRetryRemaining s'
                              : 'Send Verification Code',
                          style: const TextStyle(
                            fontSize: 16,
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

class ProfileEmailOtpPage extends StatefulWidget {
  final EmailVerificationChallenge challenge;
  final ProfileEmailApi service;

  const ProfileEmailOtpPage({
    super.key,
    required this.challenge,
    required this.service,
  });

  @override
  State<ProfileEmailOtpPage> createState() => _ProfileEmailOtpPageState();
}

class _ProfileEmailOtpPageState extends State<ProfileEmailOtpPage> {
  final _code = TextEditingController();
  Timer? _timer;
  late String _challengeToken;
  String? _destination;
  late int _secondsRemaining;
  late int _resendRemaining;
  int _verifyRetryRemaining = 0;
  int? _attemptsRemaining;
  bool _verifying = false;
  bool _resending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _applyChallenge(widget.challenge);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining > 0 ||
          _resendRemaining > 0 ||
          _verifyRetryRemaining > 0) {
        setState(() {
          if (_secondsRemaining > 0) _secondsRemaining--;
          if (_resendRemaining > 0) _resendRemaining--;
          if (_verifyRetryRemaining > 0) _verifyRetryRemaining--;
        });
      }
    });
  }

  void _applyChallenge(EmailVerificationChallenge challenge) {
    _challengeToken = challenge.challengeToken;
    _destination = challenge.destination;
    _secondsRemaining = challenge.expiresIn;
    _resendRemaining = challenge.resendAfter;
    _verifyRetryRemaining = 0;
    _attemptsRemaining = challenge.attemptsRemaining;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_verifying ||
        _secondsRemaining <= 0 ||
        _verifyRetryRemaining > 0 ||
        _attemptsRemaining == 0) {
      return;
    }
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _message = 'Enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _verifying = true;
      _message = null;
    });
    try {
      final result = await widget.service.verify(
        challengeToken: _challengeToken,
        code: code,
      );
      if (!mounted) return;
      if (result.verificationComplete) {
        Navigator.of(context).pop(result);
        return;
      }

      final nextChallenge = result.nextChallenge;
      if (nextChallenge == null) {
        setState(() {
          _message = 'The server did not create the next verification step.';
        });
        return;
      }
      setState(() {
        _applyChallenge(nextChallenge);
        _code.clear();
        _message = result.message;
      });
    } on ProfileEmailException catch (error) {
      if (!mounted) return;
      _code.clear();
      setState(() {
        _message = error.message;
        if (error.attemptsRemaining != null) {
          _attemptsRemaining = error.attemptsRemaining;
        }
        if (error.retryAfter != null) {
          _verifyRetryRemaining = error.retryAfter!;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Unable to verify the code.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendRemaining > 0) return;
    setState(() {
      _resending = true;
      _message = null;
    });
    try {
      final replacement = await widget.service.resend(
        challengeToken: _challengeToken,
      );
      if (!mounted) return;
      setState(() {
        _applyChallenge(replacement);
        _code.clear();
        _message = 'A new verification code was sent.';
      });
    } on ProfileEmailException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          if (error.attemptsRemaining != null) {
            _attemptsRemaining = error.attemptsRemaining;
          }
          if (error.retryAfter != null) {
            _resendRemaining = error.retryAfter!;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Unable to resend the code.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString();
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _secondsRemaining <= 0;
    final lockedOut = _attemptsRemaining == 0;
    final destination = _destination ?? 'your email address';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8FF),
        foregroundColor: _emailInk,
        elevation: 0,
        title: const Text('Verification'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.mark_email_unread_outlined,
                color: _emailRed,
                size: 58,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter verification code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _emailInk,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent a 6-digit code to $destination.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6F6871),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 34),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 13,
                ),
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  counterText: '',
                  hintText: '000000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _emailRed, width: 2),
                  ),
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 12),
              Text(
                expired
                    ? 'This code has expired. Request a new one.'
                    : 'Code expires in ${_formatTime(_secondsRemaining)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: expired ? _emailRed : const Color(0xFF6F6871),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_attemptsRemaining != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Attempts remaining: $_attemptsRemaining',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6F6871)),
                ),
              ],
              if (_verifyRetryRemaining > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Try verification again in $_verifyRetryRemaining s',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _emailRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 18),
                _EmailMessage(message: _message!),
              ],
              const SizedBox(height: 26),
              FilledButton(
                onPressed: _verifying ||
                        expired ||
                        lockedOut ||
                        _verifyRetryRemaining > 0
                    ? null
                    : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: _emailRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD6C5C5),
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
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _verifyRetryRemaining > 0
                            ? 'Try again in $_verifyRetryRemaining s'
                            : lockedOut
                                ? 'No attempts remaining'
                                : 'Verify Email',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _resending || _resendRemaining > 0 ? null : _resend,
                child: _resending
                    ? const Text('Sending...')
                    : Text(_resendRemaining > 0
                        ? 'Resend code in $_resendRemaining s'
                        : 'Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailSecurityNote extends StatelessWidget {
  const _EmailSecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: _emailRed, size: 21),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'For your security, your current password is required and the email is saved only after the correct OTP is entered.',
              style: TextStyle(color: Color(0xFF5E565F), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailMessage extends StatelessWidget {
  final String message;

  const _EmailMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE7E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB4AB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _emailRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
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
}
