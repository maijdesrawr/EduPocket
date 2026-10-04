import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/student_transfer.dart';
import 'package:rawr/student_transfer_service.dart';

void main() {
  group('StudentTransferService', () {
    test('sends the idempotent transfer contract and parses confirmation',
        () async {
      late http.Request captured;
      final service = StudentTransferService(
        baseUrl: 'https://example.test/edupay',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Funds transferred successfully.',
              'transfer_id': 81,
              'sender_transaction_id': 91,
              'recipient_transaction_id': 92,
              'recipient_name': 'Maria Student',
              'new_balance': '125.50',
            }),
            200,
          );
        }),
      );

      final result = await service.transfer(
        senderId: 'S1001',
        recipientId: 'S1002',
        amount: '24.50',
        pin: '123456',
        clientRequestId: 'c09cf703-35d6-4e26-834c-01f37f304da1',
      );

      expect(captured.url.path, '/edupay/student_transfer.php');
      expect(captured.bodyFields, {
        'sender_id': 'S1001',
        'recipient_id': 'S1002',
        'amount': '24.50',
        'pin': '123456',
        'client_request_id': 'c09cf703-35d6-4e26-834c-01f37f304da1',
      });
      expect(result.transferId, 81);
      expect(result.newBalance, 125.50);
      expect(result.senderTransactionId, 91);
      expect(result.recipientTransactionId, 92);
    });

    test('preserves server validation messages', () async {
      final service = StudentTransferService(
        baseUrl: 'https://example.test/edupay',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'status': 'error',
                'message': 'Insufficient wallet balance.',
              }),
              422,
            )),
      );

      await expectLater(
        service.transfer(
          senderId: 'S1001',
          recipientId: 'S1002',
          amount: '999.00',
          pin: '123456',
          clientRequestId: 'c09cf703-35d6-4e26-834c-01f37f304da1',
        ),
        throwsA(
          isA<StudentTransferException>().having(
            (error) => error.message,
            'message',
            'Insufficient wallet balance.',
          ),
        ),
      );
    });

    test('rejects plain HTTP outside the ADB loopback tunnel', () async {
      var requests = 0;
      final service = StudentTransferService(
        baseUrl: 'http://192.168.1.5/edupay',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.fetchBalance(studentId: 'S1001'),
        throwsA(
          isA<StudentTransferException>().having(
            (error) => error.message,
            'message',
            contains('require HTTPS'),
          ),
        ),
      );
      expect(requests, 0);
    });
  });

  testWidgets('confirmation can cancel or complete a student transfer',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeStudentTransferApi();

    await tester.pumpWidget(
      MaterialApp(
        home: StudentTransferScreen(
          name: 'Juan Dela Cruz',
          id: 'S1001',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('student-transfer-recipient')),
      'S1002',
    );
    await tester.enterText(
      find.byKey(const Key('student-transfer-amount')),
      '25.50',
    );
    await tester.enterText(
      find.byKey(const Key('student-transfer-pin')),
      '123456',
    );
    await tester.ensureVisible(
      find.byKey(const Key('student-transfer-submit')),
    );
    await tester.tap(find.byKey(const Key('student-transfer-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('student-transfer-confirmation-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('student-transfer-cancel')));
    await tester.pumpAndSettle();
    expect(service.transferCalls, 0);

    await tester.tap(find.byKey(const Key('student-transfer-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('student-transfer-confirm')));
    await tester.pumpAndSettle();

    expect(service.transferCalls, 1);
    expect(service.senderId, 'S1001');
    expect(service.recipientId, 'S1002');
    expect(service.amount, '25.50');
    expect(service.pin, '123456');
    expect(
      find.byKey(const Key('student-transfer-success-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('shows the welcome greeting and rejects zero or negative amounts',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeStudentTransferApi();

    await tester.pumpWidget(
      MaterialApp(
        home: StudentTransferScreen(
          name: 'Maria Santos',
          id: 'S1001',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Transfer Funds'), findsNothing);
    expect(find.text('Minimum transfer amount: ₱1.00'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('student-transfer-recipient')),
      'S1002',
    );
    await tester.enterText(
      find.byKey(const Key('student-transfer-pin')),
      '123456',
    );

    final amountField = find.byKey(const Key('student-transfer-amount'));
    const minimumError =
        'Amount must be at least ₱1.00. Zero and negative amounts are not allowed.';

    await tester.enterText(amountField, '0');
    await tester.pump();
    expect(find.text(minimumError), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('student-transfer-submit')),
    );
    await tester.tap(find.byKey(const Key('student-transfer-submit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('student-transfer-confirmation-dialog')),
      findsNothing,
    );
    expect(service.transferCalls, 0);

    await tester.enterText(amountField, '-1');
    await tester.pump();
    expect(find.text(minimumError), findsOneWidget);
    await tester.tap(find.byKey(const Key('student-transfer-submit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('student-transfer-confirmation-dialog')),
      findsNothing,
    );
    expect(service.transferCalls, 0);

    await tester.enterText(amountField, '1');
    await tester.pump();
    final amountEditor = tester.widget<EditableText>(
      find.descendant(of: amountField, matching: find.byType(EditableText)),
    );
    expect(amountEditor.controller.text, '1');
    await tester.tap(find.byKey(const Key('student-transfer-submit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('student-transfer-confirmation-dialog')),
      findsOneWidget,
    );
  });
}

class _FakeStudentTransferApi implements StudentTransferApi {
  int transferCalls = 0;
  String? senderId;
  String? recipientId;
  String? amount;
  String? pin;

  @override
  Future<double> fetchBalance({required String studentId}) async => 250;

  @override
  Future<StudentTransferResult> transfer({
    required String senderId,
    required String recipientId,
    required String amount,
    required String pin,
    required String clientRequestId,
  }) async {
    transferCalls++;
    this.senderId = senderId;
    this.recipientId = recipientId;
    this.amount = amount;
    this.pin = pin;
    return const StudentTransferResult(
      message: 'Funds transferred successfully.',
      transferId: 81,
      senderTransactionId: 91,
      recipientTransactionId: 92,
      recipientName: 'Maria Student',
      newBalance: 224.50,
    );
  }
}
