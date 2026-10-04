import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/canteen_product_management_screen.dart';
import 'package:rawr/canteen_product_management_service.dart';

void main() {
  testWidgets('searches and filters the canteen product list', (tester) async {
    final repository = _FakeProductRepository(
      products: const [
        CanteenProduct(
          productId: 1,
          name: 'Chicken Rice',
          price: 80,
          quantity: 10,
          category: 'Meals',
        ),
        CanteenProduct(
          productId: 2,
          name: 'Iced Coffee',
          price: 45,
          quantity: 7,
          category: 'Drinks',
        ),
        CanteenProduct(
          productId: 3,
          name: 'Burger',
          price: 60,
          quantity: 5,
          category: 'Snacks',
        ),
      ],
    );
    await _pumpScreen(tester, repository);

    expect(find.text('Chicken Rice'), findsOneWidget);
    expect(find.text('Iced Coffee'), findsOneWidget);
    expect(find.text('Burger'), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-category-Drinks')));
    await tester.pump();
    expect(find.text('Iced Coffee'), findsOneWidget);
    expect(find.text('Chicken Rice'), findsNothing);

    await tester.tap(find.byKey(const Key('product-category-All')));
    await tester.enterText(
      find.byKey(const Key('product-search-field')),
      'rice',
    );
    await tester.pump();
    expect(find.text('Chicken Rice'), findsOneWidget);
    expect(find.text('Iced Coffee'), findsNothing);
  });

  testWidgets('adds, edits, and confirms deletion of a product',
      (tester) async {
    final repository = _FakeProductRepository(products: const []);
    await _pumpScreen(tester, repository);
    expect(find.text('No products yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-product-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('product-name-input')),
      'Banana Cue',
    );
    await tester.enterText(
      find.byKey(const Key('product-price-input')),
      '25',
    );
    await tester.enterText(
      find.byKey(const Key('product-quantity-input')),
      '9',
    );
    await tester.enterText(
      find.byKey(const Key('product-category-input')),
      'Snacks',
    );
    final saveButton = find.byKey(const Key('save-product-button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.addedInput?.name, 'Banana Cue');
    expect(repository.addedInput?.quantity, 9);
    expect(find.text('Banana Cue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-product-50')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('product-name-input')),
      'Sweet Banana Cue',
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.updatedInput?.name, 'Sweet Banana Cue');
    expect(find.text('Sweet Banana Cue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-product-50')));
    await tester.pumpAndSettle();
    expect(find.text('Delete product?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-product')));
    await tester.pumpAndSettle();

    expect(repository.deletedProductId, 50);
    expect(find.text('No products yet'), findsOneWidget);
  });

  testWidgets('shows API failure and retries into an empty state',
      (tester) async {
    final repository = _FakeProductRepository(
      products: const [],
      fetchError: const CanteenProductManagementException('Server offline.'),
    );
    await _pumpScreen(tester, repository);

    expect(find.text('Products could not be loaded'), findsOneWidget);
    expect(find.text('Server offline.'), findsOneWidget);

    repository.fetchError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repository.fetchCalls, 2);
    expect(find.text('No products yet'), findsOneWidget);
  });

  testWidgets('embedded mode omits its own app bar', (tester) async {
    await _pumpScreen(
      tester,
      _FakeProductRepository(products: const []),
      showAppBar: false,
    );

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Your Products'), findsOneWidget);
    expect(find.byKey(const Key('add-product-button')), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CanteenProductRepository repository, {
  bool showAppBar = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CanteenProductManagementScreen(
        canteenId: 'C4001',
        service: repository,
        showAppBar: showAppBar,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeProductRepository extends CanteenProductRepository {
  _FakeProductRepository({
    required List<CanteenProduct> products,
    this.fetchError,
  }) : products = [...products];

  List<CanteenProduct> products;
  Object? fetchError;
  int fetchCalls = 0;
  CanteenProductInput? addedInput;
  CanteenProductInput? updatedInput;
  int? deletedProductId;

  @override
  Future<List<CanteenProduct>> fetchProducts({
    required String canteenId,
  }) async {
    fetchCalls++;
    final error = fetchError;
    if (error != null) throw error;
    return [...products];
  }

  @override
  Future<CanteenProduct> addProduct({
    required String canteenId,
    required CanteenProductInput input,
  }) async {
    addedInput = input;
    final product = CanteenProduct(
      productId: 50,
      name: input.name,
      price: input.price,
      quantity: input.quantity,
      category: input.category,
    );
    products.add(product);
    return product;
  }

  @override
  Future<CanteenProduct> updateProduct({
    required String canteenId,
    required CanteenProduct product,
    required CanteenProductInput input,
  }) async {
    updatedInput = input;
    final updated = CanteenProduct(
      productId: product.productId,
      name: input.name,
      price: input.price,
      quantity: input.quantity,
      category: input.category,
    );
    products = products
        .map((entry) => entry.productId == product.productId ? updated : entry)
        .toList();
    return updated;
  }

  @override
  Future<void> deleteProduct({
    required String canteenId,
    required int productId,
  }) async {
    deletedProductId = productId;
    products.removeWhere((product) => product.productId == productId);
  }
}
