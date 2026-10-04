import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/pos_amount_input_screen.dart';
import 'package:rawr/receipt_screen.dart';

void main() {
  group('canteen POS catalog helpers', () {
    final products = [
      Product(1, 'Chicken Meal', 75, category: 'Meals', qty: 2, stockQty: 8),
      Product(2, 'Mango Juice', 25, category: 'Drinks', qty: 1, stockQty: 5),
      Product(3, 'Banana Cue', 20, category: 'Snacks', stockQty: 10),
    ];

    test('All is first and categories are merged without case duplicates', () {
      expect(
        posProductCategories(products, const ['drinks', 'Meals']),
        const ['All', 'drinks', 'Meals', 'Snacks'],
      );
    });

    test('category and search filters can be combined', () {
      expect(
        filterPosProducts(
          products,
          selectedCategory: 'Drinks',
          searchQuery: 'mango',
        ).map((product) => product.productId),
        [2],
      );
      expect(
        filterPosProducts(
          products,
          selectedCategory: posAllCategory,
          searchQuery: 'meal',
        ).map((product) => product.productId),
        [1],
      );
    });

    test('running total includes only selected quantities', () {
      expect(posCartTotal(products), 175);
    });
  });

  test('product catalog URL carries the selected canteen filter', () {
    final uri = posProductCatalogUri('https://example.test/edupay/',
        canteenId: 'CANTEEN-7');
    expect(uri.path, '/edupay/get_products.php');
    expect(uri.queryParameters, {'canteen_id': 'CANTEEN-7'});
  });

  test('payment contract remains form fields with items encoded as JSON', () {
    final form = buildPosPaymentForm(
      studentNumber: 'S1001',
      pin: '123456',
      amount: 125.5,
      cashierId: 'CANTEEN-7',
      canteenId: 'CANTEEN-7',
      products: [
        Product(10, 'Rice Meal', 100, category: 'Meals', qty: 1, stockQty: 4),
        Product(11, 'Water', 25.5, category: 'Drinks', qty: 1, stockQty: 6),
        Product(12, 'Unselected', 5, category: 'Snacks', stockQty: 2),
      ],
    );

    expect(form['student_num'], 'S1001');
    expect(form['pin'], '123456');
    expect(form['amount'], '125.50');
    expect(form['cashier_id'], 'CANTEEN-7');
    expect(form['canteen_id'], 'CANTEEN-7');
    expect(
      form['description'],
      isEmpty,
      reason: 'An empty description lets confirm_payment.php persist the '
          'validated Product xQuantity summary used by transaction history.',
    );
    expect(
      jsonDecode(form['items']!),
      [
        {'product_id': 10, 'quantity': 1},
        {'product_id': 11, 'quantity': 1},
      ],
    );
  });

  test('receipt close control stays opt-in for existing callers', () {
    const existing = ReceiptScreen(
      transactionId: 1,
      viewerRole: 'student',
      viewerId: 'S1001',
    );
    const canteenCheckout = ReceiptScreen(
      transactionId: 2,
      viewerRole: 'canteen',
      viewerId: 'CANTEEN-7',
      showCloseButton: true,
    );

    expect(existing.showCloseButton, isFalse);
    expect(canteenCheckout.showCloseButton, isTrue);
  });
}
