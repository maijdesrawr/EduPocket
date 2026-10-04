import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rawr/payment_method.dart';
import 'package:rawr/profile_password_change.dart';
import 'package:rawr/select_billpayment.dart';

void main() {
  testWidgets('failed checkout shows result and retry restores payment choices',
      (tester) async {
    final client = MockClient((request) async => http.Response(
        jsonEncode(request.url.path.endsWith('checkout_status.php')
            ? {'status': 'failed', 'message': 'The test payment was declined.'}
            : {
                'status': 'success',
                'checkout_id': 'cs_test12345678',
                'checkout_url': 'https://checkout.paymongo.com/test'
              }),
        200));
    await tester.pumpWidget(MaterialApp(
        home: PaymentMethodPage(
            userName: 'Parent',
            userId: 'P1',
            selectedChildId: 'S1',
            selectedChildName: 'Child',
            amount: 50,
            client: client,
            launchCheckout: (_) async => true)));
    await tester.tap(find.text('GCash'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Payment Failed'), findsWidgets);
    expect(find.text('The test payment was declined.'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Payment Method'), findsOneWidget);
    expect(find.text('Payment Failed'), findsNothing);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'GCash'))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Maya'))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cashier custom option can be edited and deleted using its icons',
      (tester) async {
    var name = 'Test fee';
    var exists = true;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('edit_payment_option.php')) {
        name = request.bodyFields['description']!;
        return http.Response(
            '{"status":"success","message":"Payment updated."}', 200);
      }
      if (request.url.path.endsWith('delete_payment_option.php')) {
        exists = false;
        return http.Response(
            '{"status":"success","message":"Payment deleted."}', 200);
      }
      return http.Response(
          jsonEncode({
            'status': 'success',
            'payments': exists
                ? [
                    {'id': 7, 'description': name}
                  ]
                : []
          }),
          200);
    });
    await tester.pumpWidget(MaterialApp(
        home: BillPaymentScreen(
            studentNumber: 'S1', cashierId: 'K1', client: client)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Edit payment'));
    await tester.tap(find.byTooltip('Edit payment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Updated fee');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Updated fee'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Delete payment'));
    await tester.tap(find.byTooltip('Delete payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Updated fee'), findsNothing);
    expect(exists, isFalse);
  });

  testWidgets('verification setup shows QR alongside setup options',
      (tester) async {
    const uri =
        'otpauth://totp/EduPocket:test?secret=JBSWY3DPEHPK3PXP&issuer=EduPocket';
    await tester.pumpWidget(const MaterialApp(
        home: PasswordOtpVerificationPage(
            challengeToken: 'fixture-token',
            method: 'totp',
            expiresIn: 300,
            requiresTotpSetup: true,
            totpSetupKey: 'JBSWY3DPEHPK3PXP',
            otpauthUri: uri)));
    final qr = tester.widget<QrImageView>(
        find.byKey(const Key('verificationAuthenticatorQrCode')));
    expect(qr.size, 210);
    expect(find.text('Copy Key'), findsOneWidget);
    expect(find.text('Open App'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

