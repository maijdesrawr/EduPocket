import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/profile_pin.dart';
import 'package:rawr/profile_pin_service.dart';

void main() {
  group('ProfilePinService', () {
    test('status authenticates the canonical role and account ID', () async {
      late http.Request captured;
      final service = ProfilePinService(
        baseUrl: 'https://example.test/edupay',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({'status': 'success', 'has_pin': true}),
            200,
          );
        }),
      );

      final status = await service.getStatus(
        role: 'cashier',
        userId: 'K5001',
        currentPassword: 'Current1!',
      );

      expect(status.hasPin, isTrue);
      expect(captured.url.path, '/edupay/pin_status.php');
      expect(captured.bodyFields, {
        'role': 'cashier',
        'user_id': 'K5001',
        'current_password': 'Current1!',
      });
    });

    test('change sends password, optional current PIN, and new PIN', () async {
      late http.Request captured;
      final service = ProfilePinService(
        baseUrl: 'https://example.test/edupay/',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Your 6-digit PIN was changed successfully.',
            }),
            200,
          );
        }),
      );

      final result = await service.changePin(
        role: 'parent',
        userId: 'P1001',
        currentPassword: 'Current1!',
        currentPin: '123456',
        newPin: '654321',
      );

      expect(result.message, contains('changed successfully'));
      expect(captured.url.path, '/edupay/change_pin.php');
      expect(captured.bodyFields, {
        'role': 'parent',
        'user_id': 'P1001',
        'current_password': 'Current1!',
        'current_pin': '123456',
        'new_pin': '654321',
      });
    });

    test('server error message is preserved', () async {
      final service = ProfilePinService(
        baseUrl: 'https://example.test/edupay',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'status': 'error',
                'message': 'Current PIN is incorrect.',
              }),
              200,
            )),
      );

      await expectLater(
        service.changePin(
          role: 'student',
          userId: 'S1001',
          currentPassword: 'Current1!',
          currentPin: '111222',
          newPin: '654321',
        ),
        throwsA(
          isA<ProfilePinException>().having(
            (error) => error.message,
            'message',
            'Current PIN is incorrect.',
          ),
        ),
      );
    });

    test('plain HTTP LAN transport is rejected before credentials are sent',
        () async {
      var requests = 0;
      final service = ProfilePinService(
        baseUrl: 'http://192.168.1.20/edupay',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.getStatus(
          role: 'admin',
          userId: 'A3001',
          currentPassword: 'Current1!',
        ),
        throwsA(
          isA<ProfilePinException>().having(
            (error) => error.message,
            'message',
            contains('requires HTTPS'),
          ),
        ),
      );
      expect(requests, 0);
    });
  });

  group('ProfilePinPage', () {
    testWidgets('requires current PIN when one is already set', (tester) async {
      final service = _FakePinApi(hasPin: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePinPage(
            role: 'student',
            userId: 'S1001',
            service: service,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('pin-current-password-field')),
        'Current1!',
      );
      await tester.tap(find.byKey(const Key('pin-status-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Current PIN'), findsOneWidget);
      expect(find.text('New PIN'), findsOneWidget);
      expect(find.text('Confirm New PIN'), findsOneWidget);

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '654321');
      await tester.enterText(fields.at(2), '654321');
      await tester.tap(find.byKey(const Key('pin-change-submit')));
      await tester.pumpAndSettle();

      expect(service.changed, isFalse);
      expect(
        find.byKey(const Key('pin-change-confirmation-dialog')),
        findsOneWidget,
      );
      expect(find.text('Use a different password'), findsNothing);

      await tester.tap(find.byKey(const Key('pin-change-confirm')));
      await tester.pumpAndSettle();

      expect(service.changed, isTrue);
      expect(service.currentPassword, 'Current1!');
      expect(service.currentPin, '123456');
      expect(service.newPin, '654321');
      expect(find.text('PIN updated'), findsOneWidget);
    });

    testWidgets('allows PIN creation without a current PIN', (tester) async {
      final service = _FakePinApi(hasPin: false);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePinPage(
            role: 'canteen',
            userId: 'C4001',
            service: service,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('pin-current-password-field')),
        'Current1!',
      );
      await tester.tap(find.byKey(const Key('pin-status-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Create your PIN'), findsOneWidget);
      expect(find.text('Current PIN'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Create PIN'), findsOneWidget);
    });

    testWidgets('cancel keeps the PIN form open without calling the API',
        (tester) async {
      final service = _FakePinApi(hasPin: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePinPage(
            role: 'student',
            userId: 'S1001',
            service: service,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('pin-current-password-field')),
        'Current1!',
      );
      await tester.tap(find.byKey(const Key('pin-status-submit')));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '654321');
      await tester.enterText(fields.at(2), '654321');
      await tester.tap(find.byKey(const Key('pin-change-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pin-change-cancel')));
      await tester.pumpAndSettle();

      expect(service.changed, isFalse);
      expect(
        find.byKey(const Key('pin-change-confirmation-dialog')),
        findsNothing,
      );
      expect(find.text('Choose a new PIN'), findsOneWidget);
      expect(find.text('Use a different password'), findsNothing);
    });
  });
}

class _FakePinApi implements ProfilePinApi {
  _FakePinApi({required this.hasPin});

  final bool hasPin;
  bool changed = false;
  String? currentPassword;
  String? currentPin;
  String? newPin;

  @override
  Future<ProfilePinStatus> getStatus({
    required String role,
    required String userId,
    required String currentPassword,
  }) async {
    return ProfilePinStatus(hasPin: hasPin);
  }

  @override
  Future<ProfilePinChangeResult> changePin({
    required String role,
    required String userId,
    required String currentPassword,
    required String currentPin,
    required String newPin,
  }) async {
    changed = true;
    this.currentPassword = currentPassword;
    this.currentPin = currentPin;
    this.newPin = newPin;
    return const ProfilePinChangeResult(
      message: 'Your 6-digit PIN was changed successfully.',
    );
  }
}
