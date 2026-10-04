import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/profile_authenticator_service.dart';

void main() {
  test('status uses protected endpoint fields and parses enrollment', () async {
    late http.Request captured;
    final service = ProfileAuthenticatorService(
      baseUrl: 'https://example.test/edupay',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'status': 'success', 'enrolled': true}),
          200,
        );
      }),
    );

    final result = await service.getStatus(
      role: 'student',
      userId: 'S1001',
      currentPassword: 'Current1!',
    );

    expect(result.isEnrolled, isTrue);
    expect(captured.url.path, '/edupay/authenticator_status.php');
    expect(captured.bodyFields, {
      'role': 'student',
      'user_id': 'S1001',
      'current_password': 'Current1!',
    });
  });

  test('enrollment request parses QR URI and setup key', () async {
    late http.Request captured;
    final service = ProfileAuthenticatorService(
      baseUrl: 'https://example.test/edupay/',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'action': 'enroll',
            'challenge_token': 'challenge-token',
            'expires_in': 300,
            'attempts_remaining': 5,
            'setup_key': 'JBSWY3DPEHPK3PXP',
            'otpauth_uri':
                'otpauth://totp/EduPocket:S1001?secret=JBSWY3DPEHPK3PXP',
          }),
          200,
        );
      }),
    );

    final result = await service.requestManagement(
      role: 'parent',
      userId: 'P1001',
      action: AuthenticatorAction.enroll,
      currentPassword: 'Current1!',
    );

    expect(result.setupKey, 'JBSWY3DPEHPK3PXP');
    expect(result.otpauthUri, startsWith('otpauth://totp/'));
    expect(result.attemptsRemaining, 5);
    expect(captured.url.path, '/edupay/request_authenticator_management.php');
    expect(captured.bodyFields, {
      'role': 'parent',
      'user_id': 'P1001',
      'action': 'enroll',
      'current_password': 'Current1!',
    });
  });

  test('verification sends exact removal contract', () async {
    late http.Request captured;
    final service = ProfileAuthenticatorService(
      baseUrl: 'https://example.test/edupay',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'action': 'remove',
            'enrolled': false,
            'message': 'Authenticator removed.',
          }),
          200,
        );
      }),
    );

    final result = await service.verifyManagement(
      role: 'cashier',
      userId: 'K5001',
      action: AuthenticatorAction.remove,
      challengeToken: 'challenge-token',
      authenticatorCode: '123456',
    );

    expect(result.isEnrolled, isFalse);
    expect(captured.url.path, '/edupay/verify_authenticator_management.php');
    expect(captured.bodyFields, {
      'role': 'cashier',
      'user_id': 'K5001',
      'action': 'remove',
      'challenge_token': 'challenge-token',
      'authenticator_code': '123456',
    });
  });

  test('server errors preserve message and retry details', () async {
    final service = ProfileAuthenticatorService(
      baseUrl: 'https://example.test/edupay',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Incorrect authenticator code.',
            'attempts_remaining': 3,
            'retry_after': 15,
          }),
          200,
        );
      }),
    );

    await expectLater(
      service.verifyManagement(
        role: 'admin',
        userId: 'A3001',
        action: AuthenticatorAction.remove,
        challengeToken: 'challenge-token',
        authenticatorCode: '111111',
      ),
      throwsA(
        isA<ProfileAuthenticatorException>()
            .having((error) => error.message, 'message',
                'Incorrect authenticator code.')
            .having((error) => error.attemptsRemaining, 'attemptsRemaining', 3)
            .having((error) => error.retryAfter, 'retryAfter', 15),
      ),
    );
  });

  test('plain HTTP LAN transport is rejected before sending credentials',
      () async {
    var requests = 0;
    final service = ProfileAuthenticatorService(
      baseUrl: 'http://192.168.1.20/edupay',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.getStatus(
        role: 'student',
        userId: 'S1001',
        currentPassword: 'Current1!',
      ),
      throwsA(
        isA<ProfileAuthenticatorException>().having(
          (error) => error.message,
          'message',
          contains('requires HTTPS'),
        ),
      ),
    );
    expect(requests, 0);
  });

  test('loopback HTTP is allowed for an ADB reverse tunnel', () async {
    final service = ProfileAuthenticatorService(
      baseUrl: 'http://127.0.0.1/edupay',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({'status': 'success', 'enrolled': false}),
          200,
        );
      }),
    );

    final result = await service.getStatus(
      role: 'canteen',
      userId: 'C4001',
      currentPassword: 'Current1!',
    );
    expect(result.isEnrolled, isFalse);
  });
}
