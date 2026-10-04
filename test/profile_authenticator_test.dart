import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/profile_authenticator.dart';
import 'package:rawr/profile_authenticator_service.dart';

void main() {
  testWidgets('generic profile button opens without revealing linked status', (
    tester,
  ) async {
    final service = _FakeAuthenticatorApi(isEnrolled: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileAuthenticatorButton(
            role: 'student',
            userId: 'S1001',
            service: service,
          ),
        ),
      ),
    );

    expect(find.text('Google Authenticator'), findsOneWidget);
    expect(find.textContaining('linked'), findsNothing);
    expect(service.statusCalls, 0);

    await tester.tap(find.text('Google Authenticator'));
    await tester.pumpAndSettle();

    expect(find.text('Current Password'), findsOneWidget);
    expect(
      find.textContaining('not currently required when signing in'),
      findsOneWidget,
    );
    expect(service.statusCalls, 0);
  });

  testWidgets('unbound account can enroll by QR or manual key and confirm', (
    tester,
  ) async {
    final service = _FakeAuthenticatorApi(isEnrolled: false);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAuthenticatorPage(
          role: 'parent',
          userId: 'P1001',
          service: service,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('authenticatorCurrentPassword')),
      'Current1!',
    );
    await tester.tap(find.byKey(const Key('authenticatorContinue')));
    await tester.pumpAndSettle();

    expect(service.statusCalls, 1);
    expect(service.requestedAction, AuthenticatorAction.enroll);
    expect(service.statusPassword, 'Current1!');
    expect(service.requestPassword, 'Current1!');
    expect(find.byKey(const Key('authenticatorQrCode')), findsOneWidget);
    expect(find.text('JBSW Y3DP EHPK 3PXP'), findsOneWidget);
    expect(find.text('Copy Key'), findsOneWidget);
    expect(find.text('Open App'), findsOneWidget);
    expect(find.text('Current Password'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('authenticatorCode')),
      '123456',
    );
    await tester.ensureVisible(find.byKey(const Key('authenticatorVerify')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('authenticatorVerify')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.verifiedAction, AuthenticatorAction.enroll);
    expect(service.verifiedCode, '123456');
    expect(find.text('Authenticator linked'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileAuthenticatorPage), findsNothing);
  });

  testWidgets('bound account requires password and current code for removal', (
    tester,
  ) async {
    final service = _FakeAuthenticatorApi(isEnrolled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAuthenticatorPage(
          role: 'admin',
          userId: 'A3001',
          service: service,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('authenticatorCurrentPassword')),
      'Current1!',
    );
    await tester.tap(find.byKey(const Key('authenticatorContinue')));
    await tester.pumpAndSettle();

    expect(service.requestedAction, AuthenticatorAction.remove);
    expect(find.text('Authenticator linked'), findsOneWidget);
    expect(find.text('Verify before removal'), findsOneWidget);
    expect(find.byKey(const Key('authenticatorQrCode')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('authenticatorCode')),
      '654321',
    );
    await tester.ensureVisible(find.byKey(const Key('authenticatorVerify')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('authenticatorVerify')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.verifiedAction, AuthenticatorAction.remove);
    expect(service.verifiedCode, '654321');
    expect(find.text('Authenticator removed'), findsOneWidget);
  });

  testWidgets('server error is shown clearly and management remains usable', (
    tester,
  ) async {
    final service = _FakeAuthenticatorApi(
      isEnrolled: false,
      statusError: const ProfileAuthenticatorException(
        'Current password is incorrect.',
        retryAfter: 10,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileAuthenticatorPage(
          role: 'canteen',
          userId: 'C4001',
          service: service,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('authenticatorCurrentPassword')),
      'wrong',
    );
    await tester.tap(find.byKey(const Key('authenticatorContinue')));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Current password is incorrect.'), findsOneWidget);
    expect(find.textContaining('Try again in 10 seconds.'), findsOneWidget);
    expect(find.byKey(const Key('authenticatorContinue')), findsOneWidget);
  });
}

class _FakeAuthenticatorApi implements ProfileAuthenticatorApi {
  _FakeAuthenticatorApi({required this.isEnrolled, this.statusError});

  final bool isEnrolled;
  final ProfileAuthenticatorException? statusError;
  int statusCalls = 0;
  String? statusPassword;
  String? requestPassword;
  AuthenticatorAction? requestedAction;
  AuthenticatorAction? verifiedAction;
  String? verifiedCode;

  @override
  Future<AuthenticatorStatus> getStatus({
    required String role,
    required String userId,
    required String currentPassword,
  }) async {
    statusCalls++;
    statusPassword = currentPassword;
    final error = statusError;
    if (error != null) throw error;
    return AuthenticatorStatus(isEnrolled: isEnrolled);
  }

  @override
  Future<AuthenticatorManagementChallenge> requestManagement({
    required String role,
    required String userId,
    required AuthenticatorAction action,
    required String currentPassword,
  }) async {
    requestedAction = action;
    requestPassword = currentPassword;
    return AuthenticatorManagementChallenge(
      challengeToken: 'challenge-token',
      action: action,
      expiresIn: 300,
      attemptsRemaining: 5,
      message: action == AuthenticatorAction.enroll
          ? 'Add EduPocket, then enter its current code.'
          : 'Enter the current code to remove this authenticator.',
      setupKey:
          action == AuthenticatorAction.enroll ? 'JBSWY3DPEHPK3PXP' : null,
      otpauthUri: action == AuthenticatorAction.enroll
          ? 'otpauth://totp/EduPocket:P1001?secret=JBSWY3DPEHPK3PXP'
          : null,
    );
  }

  @override
  Future<AuthenticatorManagementResult> verifyManagement({
    required String role,
    required String userId,
    required AuthenticatorAction action,
    required String challengeToken,
    required String authenticatorCode,
  }) async {
    verifiedAction = action;
    verifiedCode = authenticatorCode;
    return AuthenticatorManagementResult(
      isEnrolled: action == AuthenticatorAction.enroll,
      message: action == AuthenticatorAction.enroll
          ? 'Google Authenticator was linked successfully.'
          : 'Google Authenticator was removed successfully.',
    );
  }
}
