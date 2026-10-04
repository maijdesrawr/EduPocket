import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/student_dashboard.dart';

void main() {
  test('student transaction labels hide canonical transfer enum values', () {
    expect(studentTransactionDisplayLabel('transfer-out'), 'Fund Transfer');
    expect(studentTransactionDisplayLabel('transfer-in'), 'Fund Received');
    expect(studentTransactionDisplayLabel('payment'), 'Payment');
  });

  test('expense total includes payments and outgoing fund transfers only', () {
    final total = studentExpenseFromTransactions([
      {'type': 'payment', 'amount': 40.0},
      {'type': 'transfer-out', 'amount': 20.0},
      {'type': 'transfer-in', 'amount': 10.0},
      {'type': 'top-up', 'amount': 100.0},
    ]);

    expect(total, 60.0);
  });
}
