import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_home.dart';
import 'app_session_service.dart';
import 'audit_trail_service.dart';
import 'cashier_dashboard_screen.dart';
import 'change_password.dart';
import 'login_otp_page.dart';
import 'login_service.dart';
import 'parent.dart';
import 'pos_dashboard_screen.dart';
import 'student_dashboard.dart';
import 'transaction_notification_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final AuditNavigatorObserver _auditNavigatorObserver =
      AuditNavigatorObserver();
  bool _routingToLogin = false;

  @override
  void initState() {
    super.initState();
    AppSessionService.instance.setInvalidSessionCallback(_showLogin);
  }

  @override
  void dispose() {
    AppSessionService.instance.setInvalidSessionCallback(null);
    super.dispose();
  }

  Future<void> _showLogin(String message) async {
    if (_routingToLogin) return;
    _routingToLogin = true;
    TransactionNotificationService.deactivate();
    await WidgetsBinding.instance.endOfFrame;
    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(initialError: message),
        ),
        (_) => false,
      );
    }
    _routingToLogin = false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      navigatorObservers: [_auditNavigatorObserver],
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final baseScale = media.textScaler.scale(1.0);
        final clampedScale = baseScale.clamp(0.9, 1.1).toDouble();
        return AppSessionActivityListener(
          child: MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(clampedScale)),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.api, this.initialError});

  final LoginApi? api;
  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();

  late final LoginApi _api;
  late final bool _ownsApi;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  late final Future<void> _loginPreparation;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LoginService();
    _error = widget.initialError;
    TransactionNotificationService.deactivate();
    _loginPreparation = AppSessionService.instance.endSession(
      reason: 'login_page_opened',
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    if (_ownsApi && _api is LoginService) {
      (_api as LoginService).close();
    }
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    final id = _idController.text.trim();
    final password = _passwordController.text;
    if (id.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter both your user ID and password.');
      if (id.isNotEmpty) _passwordFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _loginPreparation;
      final attempt = await _api.login(id: id, password: password);
      if (!mounted) return;

      if (attempt is LoginAuthenticated) {
        await _routeAuthenticated(
          attempt.user,
          currentPassword: password,
        );
        return;
      }
      if (attempt is LoginOtpRequired) {
        final user = await Navigator.of(context).push<LoginUser>(
          MaterialPageRoute(
            builder: (_) => LoginOtpPage(
              api: _api,
              challenge: attempt.challenge,
            ),
          ),
        );
        if (!mounted || user == null) return;
        await _routeAuthenticated(user, currentPassword: password);
        return;
      }

      setState(
          () => _error = 'Login could not be completed. Please try again.');
    } on LoginException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on AppSessionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Login could not be completed. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeAuthenticated(
    LoginUser user, {
    required String currentPassword,
  }) async {
    if (!mounted) return;
    final destination = _authenticatedDestination(
      user,
      currentPassword: currentPassword,
    );
    if (destination == null) {
      setState(() => _error = 'This account has an unsupported role.');
      return;
    }

    await AppSessionService.instance.activate(
      token: user.sessionToken,
      role: user.role,
      accountSource: user.accountSource,
      userId: user.id,
      expiresAtEpochSeconds: user.sessionExpiresAtEpochSeconds,
    );
    if (!mounted) return;
    unawaited(
      TransactionNotificationService.activate(
        role: user.role,
        accountSource: user.accountSource,
        userId: user.id,
      ),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  Widget? _authenticatedDestination(
    LoginUser user, {
    required String currentPassword,
  }) {
    if ((user.role == 'student' || user.role == 'parent') &&
        !user.passwordChanged) {
      return ChangePasswordPage(
        id: user.id,
        role: user.role,
        currentPassword: currentPassword,
      );
    }

    switch (user.role) {
      case 'student':
        return StudentDashboard(name: user.name, id: user.id);
      case 'parent':
        return ParentDashboard(name: user.name, id: user.id);
      case 'admin':
        return AdminHome(name: user.name, id: user.id);
      case 'canteen':
        return DashboardScreen(name: user.name, id: user.id);
      case 'cashier':
        return CashierDashboardScreen(name: user.name, id: user.id);
      default:
        return null;
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/BG.png', fit: BoxFit.cover),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final viewportHeight =
                  constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewportHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const SizedBox(height: 80),
                        Image.asset(
                          'assets/logo.png',
                          height: 120,
                          semanticLabel: 'EduPocket',
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'Tap into the future of payments',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'Arial',
                          ),
                        ),
                        const SizedBox(height: 40),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(25),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(25),
                                topRight: Radius.circular(25),
                              ),
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 480),
                                child: AutofillGroup(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Login',
                                        key: Key('login-heading'),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 25),
                                      TextField(
                                        key: const Key('login-id-field'),
                                        controller: _idController,
                                        enabled: !_isLoading,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.username,
                                        ],
                                        decoration: _fieldDecoration(
                                          label: 'User ID',
                                          icon: Icons.person_outline,
                                        ),
                                        onSubmitted: (_) {
                                          _passwordFocusNode.requestFocus();
                                        },
                                        onChanged: (_) {
                                          if (_error != null) {
                                            setState(() => _error = null);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 15),
                                      TextField(
                                        key: const Key('login-password-field'),
                                        controller: _passwordController,
                                        focusNode: _passwordFocusNode,
                                        enabled: !_isLoading,
                                        obscureText: _obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        decoration: _fieldDecoration(
                                          label: 'Password',
                                          icon: Icons.lock_outline,
                                          suffixIcon: IconButton(
                                            tooltip: _obscurePassword
                                                ? 'Show password'
                                                : 'Hide password',
                                            onPressed: _isLoading
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _obscurePassword =
                                                          !_obscurePassword;
                                                    });
                                                  },
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                            ),
                                          ),
                                        ),
                                        onSubmitted: (_) => _login(),
                                        onChanged: (_) {
                                          if (_error != null) {
                                            setState(() => _error = null);
                                          }
                                        },
                                      ),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        child: _error == null
                                            ? const SizedBox(height: 10)
                                            : Container(
                                                key: ValueKey(_error),
                                                width: double.infinity,
                                                margin: const EdgeInsets.only(
                                                  top: 10,
                                                ),
                                                padding:
                                                    const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFFFE8E8),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: Text(
                                                  _error!,
                                                  key: const Key(
                                                    'login-error-message',
                                                  ),
                                                  style: const TextStyle(
                                                    color: Color(0xFF7D1B1F),
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: ElevatedButton(
                                          key: const Key(
                                            'login-submit-button',
                                          ),
                                          onPressed: _isLoading ? null : _login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFFE53935),
                                            disabledBackgroundColor:
                                                const Color(0xFFE2B9BA),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(50),
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2.5,
                                                  ),
                                                )
                                              : const Text(
                                                  'Login',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
