import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';

class CanteenProduct {
  const CanteenProduct({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
  });

  final int productId;
  final String name;
  final double price;
  final int quantity;
  final String category;

  CanteenProduct copyWith({
    String? name,
    double? price,
    int? quantity,
    String? category,
  }) {
    return CanteenProduct(
      productId: productId,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
    );
  }

  factory CanteenProduct.fromJson(Map<String, dynamic> json) {
    final productId = int.tryParse('${json['product_id'] ?? ''}');
    final name = '${json['name'] ?? ''}'.trim();
    final price = double.tryParse('${json['price'] ?? ''}');
    final quantity = int.tryParse(
      '${json['stock_qty'] ?? json['quantity'] ?? ''}',
    );
    final category = '${json['category'] ?? ''}'.trim();

    if (productId == null ||
        productId <= 0 ||
        name.isEmpty ||
        price == null ||
        price <= 0 ||
        quantity == null ||
        quantity < 0) {
      throw const CanteenProductManagementException(
        'The server returned an invalid product.',
      );
    }

    return CanteenProduct(
      productId: productId,
      name: name,
      price: price,
      quantity: quantity,
      category: category.isEmpty ? 'Uncategorized' : category,
    );
  }
}

class CanteenProductInput {
  const CanteenProductInput({
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
  });

  final String name;
  final double price;
  final int quantity;
  final String category;

  Map<String, String> toRequestBody() {
    return {
      'name': name.trim(),
      'price': price.toStringAsFixed(2),
      'stock_qty': quantity.toString(),
      'category': category.trim(),
    };
  }
}

class CanteenProductManagementException implements Exception {
  const CanteenProductManagementException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class CanteenProductRepository {
  Future<List<CanteenProduct>> fetchProducts({required String canteenId});

  Future<CanteenProduct> addProduct({
    required String canteenId,
    required CanteenProductInput input,
  });

  Future<CanteenProduct> updateProduct({
    required String canteenId,
    required CanteenProduct product,
    required CanteenProductInput input,
  });

  Future<void> deleteProduct({
    required String canteenId,
    required int productId,
  });

  void close() {}
}

class CanteenProductManagementService extends CanteenProductRepository {
  CanteenProductManagementService({
    http.Client? client,
    AppSessionService? sessionService,
    String apiBaseUrl = ApiConfig.baseUrl,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _sessionService = sessionService ?? AppSessionService.instance,
        _apiBaseUrl = apiBaseUrl;

  final http.Client _client;
  final bool _ownsClient;
  final AppSessionService _sessionService;
  final String _apiBaseUrl;

  @override
  Future<List<CanteenProduct>> fetchProducts({
    required String canteenId,
  }) async {
    final normalizedCanteenId = _assertCanteenIdentity(canteenId);
    final uri = _endpoint('get_products.php').replace(
      queryParameters: {'canteen_id': normalizedCanteenId},
    );
    final data = await _send(() {
      return _client.get(
        uri,
        headers: _sessionService.authorizationHeaders,
      );
    });

    final rawProducts = data['products'];
    if (rawProducts == null) return const [];
    if (rawProducts is! List) {
      throw const CanteenProductManagementException(
        'The server returned an invalid product list.',
      );
    }

    return rawProducts.map((raw) {
      if (raw is! Map) {
        throw const CanteenProductManagementException(
          'The server returned an invalid product.',
        );
      }
      return CanteenProduct.fromJson(Map<String, dynamic>.from(raw));
    }).toList(growable: false);
  }

  @override
  Future<CanteenProduct> addProduct({
    required String canteenId,
    required CanteenProductInput input,
  }) async {
    final normalizedCanteenId = _assertCanteenIdentity(canteenId);
    _validateInput(input);
    final data = await _send(() {
      return _client.post(
        _endpoint('add_product.php'),
        headers: _formHeaders,
        body: {
          'canteen_id': normalizedCanteenId,
          ...input.toRequestBody(),
        },
      );
    });
    final returnedProduct = _productFromResponse(data);
    if (returnedProduct != null) return returnedProduct;
    final productId = int.tryParse('${data['product_id'] ?? ''}');
    if (productId == null || productId <= 0) {
      throw const CanteenProductManagementException(
        'The product was saved, but the server did not return its ID.',
      );
    }
    return CanteenProduct(
      productId: productId,
      name: input.name.trim(),
      price: input.price,
      quantity: input.quantity,
      category: input.category.trim(),
    );
  }

  @override
  Future<CanteenProduct> updateProduct({
    required String canteenId,
    required CanteenProduct product,
    required CanteenProductInput input,
  }) async {
    final normalizedCanteenId = _assertCanteenIdentity(canteenId);
    _validateInput(input);
    if (product.productId <= 0) {
      throw const CanteenProductManagementException('Invalid product ID.');
    }
    final data = await _send(() {
      return _client.post(
        _endpoint('update_product.php'),
        headers: _formHeaders,
        body: {
          'canteen_id': normalizedCanteenId,
          'product_id': product.productId.toString(),
          ...input.toRequestBody(),
        },
      );
    });
    final returnedProduct = _productFromResponse(data);
    if (returnedProduct != null) return returnedProduct;
    return CanteenProduct(
      productId: product.productId,
      name: input.name.trim(),
      price: input.price,
      quantity: input.quantity,
      category: input.category.trim(),
    );
  }

  @override
  Future<void> deleteProduct({
    required String canteenId,
    required int productId,
  }) async {
    final normalizedCanteenId = _assertCanteenIdentity(canteenId);
    if (productId <= 0) {
      throw const CanteenProductManagementException('Invalid product ID.');
    }
    await _send(() {
      return _client.post(
        _endpoint('delete_product.php'),
        headers: _formHeaders,
        body: {
          'canteen_id': normalizedCanteenId,
          'product_id': productId.toString(),
        },
      );
    });
  }

  Map<String, String> get _formHeaders {
    return {
      ..._sessionService.authorizationHeaders,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  String _assertCanteenIdentity(String canteenId) {
    final normalizedCanteenId = canteenId.trim();
    if (!_sessionService.hasActiveSession) {
      throw const CanteenProductManagementException(
        'Please log in to manage products.',
      );
    }
    final authorized = _sessionService.currentRole == 'canteen' &&
        _sessionService.currentAccountSource == 'canteens' &&
        _sessionService.currentUserId == normalizedCanteenId;
    if (!authorized) {
      throw const CanteenProductManagementException(
        'Only the signed-in canteen account can manage these products.',
      );
    }
    if (normalizedCanteenId.isEmpty) {
      throw const CanteenProductManagementException(
        'The canteen account ID is missing.',
      );
    }
    return normalizedCanteenId;
  }

  void _validateInput(CanteenProductInput input) {
    if (input.name.trim().isEmpty || input.name.trim().length > 100) {
      throw const CanteenProductManagementException(
        'Product name must contain 1 to 100 characters.',
      );
    }
    if (!input.price.isFinite || input.price <= 0) {
      throw const CanteenProductManagementException(
        'Price must be greater than zero.',
      );
    }
    if (input.quantity < 1) {
      throw const CanteenProductManagementException(
        'Quantity must be at least 1.',
      );
    }
    if (input.category.trim().isEmpty || input.category.trim().length > 50) {
      throw const CanteenProductManagementException(
        'Category must contain 1 to 50 characters.',
      );
    }
  }

  CanteenProduct? _productFromResponse(Map<String, dynamic> data) {
    final raw = data['product'];
    if (raw is! Map) return null;
    return CanteenProduct.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    late final http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const CanteenProductManagementException(
        'Could not connect to the server. Please try again.',
      );
    }

    final invalidSession = await _sessionService.handleResponse(response);
    if (invalidSession) {
      throw const CanteenProductManagementException(
        'Your session is no longer active. Please log in again.',
      );
    }

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      data = null;
    }

    if (data == null) {
      throw const CanteenProductManagementException(
        'The server returned an invalid response.',
      );
    }
    final success = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        '${data['status'] ?? ''}'.toLowerCase() == 'success';
    if (!success) {
      final message = '${data['message'] ?? ''}'.trim();
      throw CanteenProductManagementException(
        message.isEmpty ? 'The product request failed.' : message,
      );
    }
    return data;
  }

  Uri _endpoint(String path) {
    final base = _apiBaseUrl.endsWith('/')
        ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
        : _apiBaseUrl;
    return Uri.parse('$base/$path');
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
