import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/login_service.dart';

Future<String> _testDeviceId() async =>
    'edupocket-11111111-2222-4333-8444-555555555555';

void main() {
  test('login parses an authenticator challenge without authenticating',
      () async {
    late http.Request captured;
    final service = LoginService(
      baseUrl: 'https://example.test/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'otp_required',
            'challenge_token': 'login-challenge',
            'method': 'totp',
            'available_methods': ['totp', 'email'],
            'expires_in': 300,
            'resend_after': 0,
          }),
          200,
        );
      }),
    );

    final attempt = await service.login(
      id: 'S1001',
      password: 'Current1!',
    );

    expect(attempt, isA<LoginOtpRequired>());
    final challenge = (attempt as LoginOtpRequired).challenge;
    expect(challenge.challengeToken, 'login-challenge');
    expect(challenge.method, LoginOtpMethod.totp);
    expect(
      challenge.availableMethods,
      [LoginOtpMethod.totp, LoginOtpMethod.email],
    );
    expect(captured.url.path, '/edupay/login.php');
    expect(captured.bodyFields, {
      'id': 'S1001',
      'password': 'Current1!',
      'device_id': await _testDeviceId(),
    });
  });

  test('legacy success parses forced-password-change state', () async {
    final service = LoginService(
      baseUrl: 'https://example.test/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'role': 'student',
            'account_source': 'students',
            'id': 'S1001',
            'name': 'Jamie Student',
            'password_changed': 0,
            'session_token': 'secure-session-token-for-student-account-0001',
            'session_expires_in': 3600,
          }),
          200,
        );
      }),
    );

    final attempt = await service.login(id: 'S1001', password: 'Temporary1!');
    final user = (attempt as LoginAuthenticated).user;

    expect(user.role, 'student');
    expect(user.passwordChanged, isFalse);
  });

  test('method switch sends the challenge token and keeps it when not rotated',
      () async {
    late http.Request captured;
    final service = LoginService(
      baseUrl: 'https://example.test/edupay/',
      deviceIdProvider: _testDeviceId,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'method': 'email',
            'available_methods': ['totp', 'email'],
            'destination_masked': 'j***@example.edu',
            'expires_in': 300,
            'resend_after': 60,
          }),
          200,
        );
      }),
    );
    const challenge = LoginOtpChallenge(
      challengeToken: 'login-challenge',
      method: LoginOtpMethod.totp,
      availableMethods: [LoginOtpMethod.totp, LoginOtpMethod.email],
      expiresIn: 300,
      resendAfter: 0,
      message: 'Enter your code.',
    );

    final updated = await service.requestOtp(
      challenge: challenge,
      method: LoginOtpMethod.email,
    );

    expect(captured.url.path, '/edupay/request_login_otp.php');
    expect(captured.bodyFields, {
      'challenge_token': 'login-challenge',
      'method': 'email',
      'device_id': await _testDeviceId(),
    });
    expect(updated.challengeToken, 'login-challenge');
    expect(updated.destinationMasked, 'j***@example.edu');
    expect(updated.resendAfter, 60);
  });

  test('OTP verification returns the same authenticated user payload',
      () async {
    late http.Request captured;
    final service = LoginService(
      baseUrl: 'https://example.test/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'role': 'cashier',
            'account_source': 'cashiers',
            'id': 'K1001',
            'name': 'Casey Cashier',
            'password_changed': true,
            'session_token': 'secure-session-token-for-cashier-account-0001',
            'session_expires_in': 3600,
          }),
          200,
        );
      }),
    );

    final user = await service.verifyOtp(
      challengeToken: 'login-challenge',
      code: '123456',
    );

    expect(captured.url.path, '/edupay/verify_login_otp.php');
    expect(captured.bodyFields, {
      'challenge_token': 'login-challenge',
      'code': '123456',
      'device_id': await _testDeviceId(),
    });
    expect(user.role, 'cashier');
    expect(user.id, 'K1001');
  });

  test('verification errors preserve remaining attempts', () async {
    final service = LoginService(
      baseUrl: 'https://example.test/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Incorrect or expired verification code.',
            'remaining_attempts': 3,
          }),
          200,
        );
      }),
    );

    await expectLater(
      service.verifyOtp(
        challengeToken: 'login-challenge',
        code: '111111',
      ),
      throwsA(
        isA<LoginException>()
            .having(
              (error) => error.message,
              'message',
              'Incorrect or expired verification code.',
            )
            .having((error) => error.attemptsRemaining, 'attempts', 3),
      ),
    );
  });

  test('resend errors preserve server cooldown', () async {
    final service = LoginService(
      baseUrl: 'https://example.test/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Please wait before requesting another email code.',
            'retry_after': 19,
          }),
          200,
        );
      }),
    );
    const challenge = LoginOtpChallenge(
      challengeToken: 'login-challenge',
      method: LoginOtpMethod.email,
      availableMethods: [LoginOtpMethod.email],
      expiresIn: 300,
      resendAfter: 0,
      message: 'Enter your code.',
    );

    await expectLater(
      service.requestOtp(
        challenge: challenge,
        method: LoginOtpMethod.email,
      ),
      throwsA(
        isA<LoginException>().having(
          (error) => error.retryAfter,
          'retryAfter',
          19,
        ),
      ),
    );
  });

  test('plain HTTP LAN transport is rejected before sending credentials',
      () async {
    var requests = 0;
    final service = LoginService(
      baseUrl: 'http://192.168.1.20/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.login(id: 'S1001', password: 'Current1!'),
      throwsA(
        isA<LoginException>().having(
          (error) => error.message,
          'message',
          contains('requires HTTPS'),
        ),
      ),
    );
    expect(requests, 0);
  });

  test('loopback HTTP is allowed for an ADB reverse tunnel', () async {
    final service = LoginService(
      baseUrl: 'http://127.0.0.1:8080/edupay',
      deviceIdProvider: _testDeviceId,
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'role': 'admin',
            'account_source': 'admins',
            'id': 'A1001',
            'name': 'Alex Admin',
            'password_changed': true,
            'session_token': 'secure-session-token-for-admin-account-000001',
            'session_expires_in': 3600,
          }),
          200,
        );
      }),
    );

    final attempt = await service.login(id: 'A1001', password: 'Current1!');

    expect(attempt, isA<LoginAuthenticated>());
  });
}
