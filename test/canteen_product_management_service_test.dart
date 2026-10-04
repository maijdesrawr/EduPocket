import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/app_session_service.dart';
import 'package:rawr/canteen_product_management_service.dart';

void main() {
  group('CanteenProductManagementService', () {
    test('loads products with bearer auth and no trusted canteen query',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'products': [
              {
                'product_id': 7,
                'name': 'Chicken Rice',
                'price': '85.50',
                'stock_qty': 12,
                'category': 'Meals',
              },
            ],
            'categories': ['Meals'],
          }),
          200,
        );
      });
      final session = _FakeCanteenSession();
      final service = CanteenProductManagementService(
        client: client,
        sessionService: session,
        apiBaseUrl: 'http://127.0.0.1:8080/edupay',
      );

      final products = await service.fetchProducts(canteenId: 'C4001');

      expect(products, hasLength(1));
      expect(products.single.name, 'Chicken Rice');
      expect(products.single.category, 'Meals');
      expect(captured.method, 'GET');
      expect(captured.url.queryParameters, isEmpty);
      expect(captured.headers['authorization'], 'Bearer test-token');
      expect(session.handledResponses, 1);
    });

    test('adds all required fields and accepts returned product object',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'product': {
              'product_id': 22,
              'name': 'Mango Shake',
              'price': 55,
              'stock_qty': 8,
              'category': 'Drinks',
            },
          }),
          201,
        );
      });
      final service = CanteenProductManagementService(
        client: client,
        sessionService: _FakeCanteenSession(),
        apiBaseUrl: 'http://127.0.0.1:8080/edupay',
      );

      final product = await service.addProduct(
        canteenId: 'C4001',
        input: const CanteenProductInput(
          name: 'Mango Shake',
          price: 55,
          quantity: 8,
          category: 'Drinks',
        ),
      );

      expect(product.productId, 22);
      expect(product.quantity, 8);
      expect(captured.method, 'POST');
      expect(captured.bodyFields, {
        'name': 'Mango Shake',
        'price': '55.00',
        'stock_qty': '8',
        'category': 'Drinks',
      });
      expect(captured.headers['authorization'], 'Bearer test-token');
    });

    test('rejects another account before sending a request', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      });
      final service = CanteenProductManagementService(
        client: client,
        sessionService: _FakeCanteenSession(userId: 'C4002'),
      );

      await expectLater(
        service.fetchProducts(canteenId: 'C4001'),
        throwsA(
          isA<CanteenProductManagementException>().having(
            (error) => error.message,
            'message',
            contains('signed-in canteen'),
          ),
        ),
      );
      expect(requests, 0);
    });

    test('rejects quantity below one without sending a request', () async {
      var requests = 0;
      final service = CanteenProductManagementService(
        client: MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
        sessionService: _FakeCanteenSession(),
      );

      await expectLater(
        service.addProduct(
          canteenId: 'C4001',
          input: const CanteenProductInput(
            name: 'Rice',
            price: 10,
            quantity: 0,
            category: 'Meals',
          ),
        ),
        throwsA(
          isA<CanteenProductManagementException>().having(
            (error) => error.message,
            'message',
            contains('at least 1'),
          ),
        ),
      );
      expect(requests, 0);
    });

    test('routes an invalid API session through AppSessionService', () async {
      final session = _FakeCanteenSession(invalidateResponses: true);
      final service = CanteenProductManagementService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'error',
              'code': 'session_invalid',
              'message': 'Session expired.',
            }),
            401,
          );
        }),
        sessionService: session,
      );

      await expectLater(
        service.fetchProducts(canteenId: 'C4001'),
        throwsA(
          isA<CanteenProductManagementException>().having(
            (error) => error.message,
            'message',
            contains('session is no longer active'),
          ),
        ),
      );
      expect(session.handledResponses, 1);
    });
  });
}

class _FakeCanteenSession extends AppSessionService {
  _FakeCanteenSession({
    this.userId = 'C4001',
    this.invalidateResponses = false,
  }) : super(
          client: MockClient((request) async => http.Response('{}', 200)),
          baseUrl: 'http://127.0.0.1:8080/edupay',
        );

  final String userId;
  final bool invalidateResponses;
  int handledResponses = 0;

  @override
  bool get hasActiveSession => true;

  @override
  String? get currentRole => 'canteen';

  @override
  String? get currentAccountSource => 'canteens';

  @override
  String? get currentUserId => userId;

  @override
  Map<String, String> get authorizationHeaders => const {
        'Authorization': 'Bearer test-token',
      };

  @override
  Future<bool> handleResponse(http.Response response) async {
    handledResponses++;
    return invalidateResponses;
  }
}
