import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/profile_email_service.dart';
import 'package:rawr/profile_verified_email.dart';

void main() {
  test('email service parses verified status and a rotated second step',
      () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('get_verified_email.php')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'verified': true,
            'email_masked': 'n***@example.com',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'status': 'success',
          'verification_complete': false,
          'next_step': 'verify_new_email',
          'message': 'Verify the new address.',
          'challenge_token': 'rotated-token',
          'destination': 'c***@example.com',
          'expires_in': 300,
          'resend_after': 45,
        }),
        200,
      );
    });
    final service = ProfileEmailService(client: client);

    final status = await service.getStatus(role: 'student', id: 'S1001');
    expect(status.verified, isTrue);
    expect(status.emailMasked, 'n***@example.com');

    final result = await service.verify(
      challengeToken: 'first-token',
      code: '123456',
    );
    expect(result.verificationComplete, isFalse);
    expect(result.nextStep, 'verify_new_email');
    expect(result.nextChallenge?.challengeToken, 'rotated-token');
    expect(result.nextChallenge?.destination, 'c***@example.com');
  });

  test('email request accepts an already-verified response without a token',
      () async {
    final service = ProfileEmailService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'already_verified': true,
              'verification_complete': true,
              'email_masked': 'n***@example.com',
              'message': 'This email is already verified.',
            }),
            200,
          )),
    );

    final result = await service.requestVerification(
      role: 'admin',
      id: 'A3001',
      currentPassword: 'Current!123',
      email: 'nica@example.com',
    );

    expect(result.verificationComplete, isTrue);
    expect(result.alreadyVerified, isTrue);
    expect(result.challenge, isNull);
    expect(result.emailMasked, 'n***@example.com');
  });

  test('email service preserves attempts and retry cooldown from errors',
      () async {
    final service = ProfileEmailService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'error',
              'message': 'Incorrect code.',
              'attempts_remaining': 2,
              'retry_after': 17,
            }),
            429,
          )),
    );

    try {
      await service.verify(challengeToken: 'token', code: '123456');
      fail('Expected ProfileEmailException');
    } on ProfileEmailException catch (error) {
      expect(error.message, 'Incorrect code.');
      expect(error.attemptsRemaining, 2);
      expect(error.retryAfter, 17);
    }
  });

  testWidgets('profile action shows the masked verified address', (
    tester,
  ) async {
    final service = _FakeEmailApi(
      status: const VerifiedEmailStatus(
        verified: true,
        emailMasked: 'n***@example.com',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red,
          body: ProfileVerifiedEmailButton(
            role: 'admin',
            userId: 'A3001',
            userName: 'Admin One',
            service: service,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Change Verified Email'), findsOneWidget);
    expect(find.text('Verified: n***@example.com'), findsOneWidget);
  });

  testWidgets('email enrollment requests a code after local validation', (
    tester,
  ) async {
    final service = _FakeEmailApi(
      status: const VerifiedEmailStatus(verified: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileVerifiedEmailPage(
          role: 'parent',
          userId: 'P2001',
          userName: 'Parent One',
          service: service,
          initialStatus: service.status,
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Password'),
      'Current!123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'parent@example.com',
    );
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    expect(service.requestCount, 1);
    expect(find.text('Enter verification code'), findsOneWidget);
    expect(
      find.text('We sent a 6-digit code to p***@example.com.'),
      findsOneWidget,
    );
  });

  testWidgets('already verified request closes without opening an OTP page', (
    tester,
  ) async {
    final service = _FakeEmailApi(
      status: const VerifiedEmailStatus(
        verified: true,
        emailMasked: 'p***@example.com',
      ),
      immediateCompletion: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: _EmailPageLauncher(service: service)),
    );
    await tester.tap(find.text('Open email settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Password'),
      'Current!123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New Email Address'),
      'parent@example.com',
    );
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    expect(service.requestCount, 1);
    expect(find.text('Enter verification code'), findsNothing);
    expect(find.text('Open email settings'), findsOneWidget);
  });

  testWidgets('enrollment displays server attempts and request cooldown', (
    tester,
  ) async {
    final service = _FakeEmailApi(
      status: const VerifiedEmailStatus(verified: false),
      requestError: const ProfileEmailException(
        'Too many requests.',
        attemptsRemaining: 3,
        retryAfter: 5,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileVerifiedEmailPage(
          role: 'student',
          userId: 'S1001',
          userName: 'Student One',
          service: service,
          initialStatus: service.status,
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current Password'),
      'Current!123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'student@example.com',
    );
    await tester.tap(find.text('Send Verification Code'));
    await tester.pump();

    expect(find.text('Attempts remaining: 3'), findsOneWidget);
    expect(find.text('Try again in 5 s'), findsWidgets);
  });

  testWidgets('OTP displays server attempts and verification cooldown', (
    tester,
  ) async {
    final service = _FakeEmailApi(
      status: const VerifiedEmailStatus(verified: false),
      verifyError: const ProfileEmailException(
        'Incorrect code.',
        attemptsRemaining: 2,
        retryAfter: 4,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEmailOtpPage(
          service: service,
          challenge: const EmailVerificationChallenge(
            challengeToken: 'challenge',
            destination: 's***@example.com',
            expiresIn: 300,
            attemptsRemaining: 5,
            resendAfter: 0,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '111111');
    await tester.tap(find.text('Verify Email'));
    await tester.pump();

    expect(find.text('Attempts remaining: 2'), findsOneWidget);
    expect(find.text('Try verification again in 4 s'), findsOneWidget);
    expect(find.text('Try again in 4 s'), findsOneWidget);
  });
}

class _FakeEmailApi implements ProfileEmailApi {
  final VerifiedEmailStatus status;
  final bool immediateCompletion;
  final ProfileEmailException? requestError;
  final ProfileEmailException? verifyError;
  int requestCount = 0;

  _FakeEmailApi({
    required this.status,
    this.immediateCompletion = false,
    this.requestError,
    this.verifyError,
  });

  @override
  Future<VerifiedEmailStatus> getStatus({
    required String role,
    required String id,
  }) async =>
      status;

  @override
  Future<EmailVerificationRequestResult> requestVerification({
    required String role,
    required String id,
    required String currentPassword,
    required String email,
  }) async {
    requestCount++;
    if (requestError != null) throw requestError!;
    if (immediateCompletion) {
      return const EmailVerificationRequestResult(
        verificationComplete: true,
        alreadyVerified: true,
        message: 'This email is already verified.',
        emailMasked: 'p***@example.com',
      );
    }
    return const EmailVerificationRequestResult(
      verificationComplete: false,
      alreadyVerified: false,
      message: 'Code sent.',
      challenge: EmailVerificationChallenge(
        challengeToken: 'challenge-token',
        destination: 'p***@example.com',
        expiresIn: 300,
        attemptsRemaining: 5,
        resendAfter: 60,
      ),
    );
  }

  @override
  Future<EmailVerificationChallenge> resend({
    required String challengeToken,
  }) async {
    return const EmailVerificationChallenge(
      challengeToken: 'rotated-token',
      destination: 'p***@example.com',
      expiresIn: 300,
      attemptsRemaining: 5,
      resendAfter: 60,
    );
  }

  @override
  Future<EmailVerificationResult> verify({
    required String challengeToken,
    required String code,
  }) async {
    if (verifyError != null) throw verifyError!;
    return const EmailVerificationResult(
      message: 'Email verified.',
      emailMasked: 'p***@example.com',
    );
  }
}

class _EmailPageLauncher extends StatelessWidget {
  final ProfileEmailApi service;

  const _EmailPageLauncher({required this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ProfileVerifiedEmailPage(
                role: 'parent',
                userId: 'P2001',
                userName: 'Parent One',
                service: service,
                initialStatus: const VerifiedEmailStatus(
                  verified: true,
                  emailMasked: 'p***@example.com',
                ),
              ),
            ),
          ),
          child: const Text('Open email settings'),
        ),
      ),
    );
  }
}
