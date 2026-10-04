import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/receipt_action.dart';

void main() {
  testWidgets('receipt action has an icon and label for a recorded transaction',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ReceiptAction(
                transactionId: 15, viewerRole: 'parent', viewerId: 'P1'))));
    expect(find.text('View Receipt'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
  });
  testWidgets('missing transaction does not offer a broken receipt link',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ReceiptAction(
                transactionId: 0, viewerRole: 'admin', viewerId: 'A1'))));
    expect(find.text('View Receipt'), findsNothing);
  });
}
