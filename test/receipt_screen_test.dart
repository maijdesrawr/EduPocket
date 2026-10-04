import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/receipt_screen.dart';

void main() {
  test('receipt title covers every transaction type', () {
    expect(officialReceiptSubtitle, 'OFFICIAL TRANSACTION RECEIPT');
  });

  test('authenticated receipt data URL never carries viewer identity', () {
    final uri = receiptDataUri(
      77,
      baseUrl: 'https://api.example.test/edupay',
    );

    expect(uri.path, '/edupay/get_receipt.php');
    expect(uri.queryParameters, {'transaction_id': '77'});
    expect(uri.queryParameters, isNot(contains('viewer_role')));
    expect(uri.queryParameters, isNot(contains('viewer_id')));
  });

  test('printable receipt URL contains only its one-time token', () {
    const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';
    final uri = printableReceiptUri(
      token,
      baseUrl: 'https://api.example.test/edupay/',
    );

    expect(uri.path, '/edupay/official_receipt.php');
    expect(uri.queryParameters, {'print_token': token});
    expect(uri.queryParameters, isNot(contains('transaction_id')));
    expect(uri.queryParameters, isNot(contains('viewer_role')));
    expect(uri.queryParameters, isNot(contains('viewer_id')));
  });

  group('resolveReceiptProcessedBy', () {
    test('uses the backend processed_by value first', () {
      expect(
        resolveReceiptProcessedBy({
          'processed_by': {'name': 'Ana Reyes', 'role': 'cashier'},
          'cashier': {'name': 'Legacy Cashier'},
          'canteen': {'name': 'Legacy Canteen'},
        }),
        'Ana Reyes',
      );
      expect(
        resolveReceiptProcessedBy({'processed_by': 'Marco Santos'}),
        'Marco Santos',
      );
    });

    test('falls back to legacy cashier then canteen names', () {
      expect(
        resolveReceiptProcessedBy({
          'cashier': {'name': 'Casey Cashier'},
          'canteen': {'name': 'Main Canteen'},
        }),
        'Casey Cashier',
      );
      expect(
        resolveReceiptProcessedBy({
          'cashier': {'name': ''},
          'canteen': {'Fname': 'Main Canteen'},
        }),
        'Main Canteen',
      );
    });

    test('shows N/A when no processor name is available', () {
      expect(resolveReceiptProcessedBy({}), 'N/A');
    });
  });
}
