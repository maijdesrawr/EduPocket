import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/admin_report.dart';
import 'package:rawr/student_topups.dart';
import 'package:rawr/topup_receipt_navigation.dart';

void main() {
  test('student top-up mapping preserves the receipt transaction ID', () {
    final mapped = mapStudentTopUpForHistory(
      {
        'transaction_id': '321',
        'amount': '125.50',
        'description': 'GCash Wallet Top-up',
        'method': 'GCash Wallet Top-up',
        'status': 'Completed',
        'date_time': '2026-08-22 09:10:11',
      },
      studentName: 'Juan Dela Cruz',
    );

    expect(mapped['transaction_id'], 321);
    expect(mapped['amount'], 125.50);
    expect(mapped['name'], 'Juan Dela Cruz');
  });

  test('student top-up mapping disables receipts for an invalid ID', () {
    final mapped = mapStudentTopUpForHistory(
      {'transaction_id': 'not-an-id', 'amount': '25.00'},
      studentName: 'Student',
    );

    expect(mapped['transaction_id'], 0);
  });

  test('admin report accepts canonical and compatibility ID fields', () {
    expect(adminReportTransactionId({'transaction_id': 91, 'id': 90}), 91);
    expect(adminReportTransactionId({'id': '92'}), 92);
    expect(adminReportTransactionId({'id': ''}), 0);
  });

  test('top-up responses expose receipt IDs in both writer contracts', () {
    expect(topUpTransactionIdFromResponse({'transaction_id': 501}), 501);
    expect(
      topUpTransactionIdFromResponse({
        'data': {'transaction_id': '502'},
      }),
      502,
    );
    expect(topUpTransactionIdFromResponse({'data': {}}), 0);
  });
}
