import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/login_otp_page.dart';
import 'package:rawr/login_service.dart';

void main() {
  testWidgets('shows both enrolled methods and switches to email',
      (tester) async {
    final api = _FakeLoginApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginOtpPage(
          api: api,
          challenge: _totpChallenge,
        ),
      ),
    );

    expect(find.text('Verify it is you'), findsOneWidget);
    expect(find.text('Google Authenticator'), findsOneWidget);
    expect(find.text('Email code'), findsOneWidget);

    final emailMethod = find.byKey(const Key('login-otp-method-email'));
    await tester.ensureVisible(emailMethod);
    await tester.tap(emailMethod);
    await tester.pump();

    expect(api.requestedMethods, [LoginOtpMethod.email]);
    expect(find.textContaining('j***@example.edu'), findsWidgets);
    expect(find.text('Resend available in 60s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('validates six digits before calling the server', (tester) async {
    final api = _FakeLoginApi();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginOtpPage(
          api: api,
          challenge: _totpChallenge,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '123');
    final verify = find.byKey(const Key('login-otp-verify-button'));
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    await tester.pump();

    expect(find.text('Enter the complete 6-digit code.'), findsOneWidget);
    expect(api.verifyCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows server verification errors and attempts remaining',
      (tester) async {
    final api = _FakeLoginApi(
      verifyError: const LoginException(
        'Incorrect or expired verification code.',
        attemptsRemaining: 2,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginOtpPage(
          api: api,
          challenge: _totpChallenge,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '123456');
    final verify = find.byKey(const Key('login-otp-verify-button'));
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    await tester.pump();

    expect(api.verifyCalls, 1);
    expect(
      find.text(
        'Incorrect or expired verification code. 2 attempts remaining.',
      ),
      findsOneWidget,
    );
    expect(find.text('123456'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _totpChallenge = LoginOtpChallenge(
  challengeToken: 'login-challenge',
  method: LoginOtpMethod.totp,
  availableMethods: [LoginOtpMethod.totp, LoginOtpMethod.email],
  expiresIn: 300,
  resendAfter: 0,
  message: 'Enter the current code from Google Authenticator.',
);

class _FakeLoginApi implements LoginApi {
  _FakeLoginApi({this.verifyError});

  final LoginException? verifyError;
  final List<LoginOtpMethod> requestedMethods = [];
  int verifyCalls = 0;

  @override
  Future<LoginAttempt> login({required String id, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<LoginOtpChallenge> requestOtp({
    required LoginOtpChallenge challenge,
    required LoginOtpMethod method,
  }) async {
    requestedMethods.add(method);
    return LoginOtpChallenge(
      challengeToken: challenge.challengeToken,
      method: method,
      availableMethods: challenge.availableMethods,
      destinationMasked:
          method == LoginOtpMethod.email ? 'j***@example.edu' : null,
      expiresIn: 300,
      resendAfter: method == LoginOtpMethod.email ? 60 : 0,
      message: method == LoginOtpMethod.email
          ? 'A new code was sent.'
          : 'Enter the current authenticator code.',
    );
  }

  @override
  Future<LoginUser> verifyOtp({
    required String challengeToken,
    required String code,
  }) async {
    verifyCalls++;
    final error = verifyError;
    if (error != null) throw error;
    return const LoginUser(
      role: 'student',
      accountSource: 'students',
      id: 'S1001',
      name: 'Jamie Student',
      passwordChanged: true,
      sessionToken: 'secure-session-token-for-student-account-0001',
      sessionExpiresAtEpochSeconds: 4102444800,
    );
  }
}
