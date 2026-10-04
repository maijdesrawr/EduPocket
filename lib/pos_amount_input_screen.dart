import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';
import 'profile_avatar.dart';
import 'profile_service.dart';
import 'receipt_screen.dart';
import 'transaction_notification_service.dart';

const String posAllCategory = 'All';

class Product {
  Product(
    this.productId,
    this.name,
    this.price, {
    required this.category,
    this.qty = 0,
    this.stockQty = 0,
  });

  final int productId;
  final String name;
  final double price;
  final String category;
  int qty;
  int stockQty;
}

@visibleForTesting
String normalizePosCategory(Object? value) {
  final category = value?.toString().trim() ?? '';
  return category.isEmpty ? 'Other' : category;
}

@visibleForTesting
List<String> posProductCategories(
  Iterable<Product> products, [
  Iterable<Object?> serverCategories = const [],
]) {
  final categories = <String, String>{};

  void add(Object? value) {
    final category = normalizePosCategory(value);
    if (category.toLowerCase() == posAllCategory.toLowerCase()) return;
    categories.putIfAbsent(category.toLowerCase(), () => category);
  }

  for (final value in serverCategories) {
    add(value);
  }
  for (final product in products) {
    add(product.category);
  }

  final sorted = categories.values.toList()
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return [posAllCategory, ...sorted];
}

@visibleForTesting
List<Product> filterPosProducts(
  Iterable<Product> products, {
  required String selectedCategory,
  String searchQuery = '',
}) {
  final category = selectedCategory.trim().toLowerCase();
  final query = searchQuery.trim().toLowerCase();
  return products.where((product) {
    final categoryMatches = category.isEmpty ||
        category == posAllCategory.toLowerCase() ||
        product.category.toLowerCase() == category;
    final searchMatches = query.isEmpty ||
        product.name.toLowerCase().contains(query) ||
        product.category.toLowerCase().contains(query);
    return categoryMatches && searchMatches;
  }).toList();
}

@visibleForTesting
double posCartTotal(Iterable<Product> products) => products.fold<double>(
      0,
      (total, product) => total + (product.price * product.qty),
    );

@visibleForTesting
Uri posProductCatalogUri(String baseUrl, {required String canteenId}) {
  final normalizedBase = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return Uri.parse('$normalizedBase/get_products.php').replace(
    queryParameters: {'canteen_id': canteenId.trim()},
  );
}

@visibleForTesting
Map<String, String> buildPosPaymentForm({
  required String studentNumber,
  required String pin,
  required double amount,
  required String cashierId,
  required String canteenId,
  required Iterable<Product> products,
}) {
  final items = products
      .where((product) => product.qty > 0)
      .map(
        (product) => {
          'product_id': product.productId,
          'quantity': product.qty,
        },
      )
      .toList();
  return {
    'student_num': studentNumber,
    'pin': pin,
    'amount': amount.toStringAsFixed(2),
    'description': '',
    'cashier_id': cashierId,
    'canteen_id': canteenId,
    'items': jsonEncode(items),
  };
}

enum _FlowStage {
  productSelection,
  orderSummary,
  pinEntry,
  result,
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.recipientNumber,
    required this.paymentTitle,
    required this.cashierId,
    required this.canteenId,
    this.onNavigate,
    this.apiBaseUrl = ApiConfig.baseUrl,
    this.client,
  });

  final String recipientNumber;
  final String paymentTitle;
  final String cashierId;
  final String canteenId;
  final ValueChanged<int>? onNavigate;
  final String apiBaseUrl;
  final http.Client? client;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const Color _brandRed = Color(0xFFC62828);
  static const Color _darkRed = Color(0xFF9F1D20);
  static const int _pinLength = 6;
  static const double _maxTransactionAmount = 100000;

  late final http.Client _client = widget.client ?? http.Client();
  late final bool _ownsClient = widget.client == null;
  final TextEditingController _searchController = TextEditingController();

  List<Product> _products = [];
  List<String> _categories = const [posAllCategory];
  String _selectedCategory = posAllCategory;
  String _searchQuery = '';
  String _studentName = '';
  String _pin = '';
  _FlowStage _stage = _FlowStage.productSelection;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isProfileLocked = false;
  int _failedPinAttempts = 0;
  bool? _lastPaymentSuccess;
  String _resultMessage = '';
  int? _transactionId;

  Iterable<Product> get _cartItems =>
      _products.where((product) => product.qty > 0);

  double get _total => posCartTotal(_products);

  List<Product> get _visibleProducts => filterPosProducts(
        _products,
        selectedCategory: _selectedCategory,
        searchQuery: _searchQuery,
      );

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'canteen_checkout_opened',
        details: {'student_id': widget.recipientNumber},
      ),
    );
    unawaited(_fetchProducts());
    unawaited(_loadStudentProfile());
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Uri _endpoint(String path) {
    final normalizedBase = widget.apiBaseUrl.endsWith('/')
        ? widget.apiBaseUrl.substring(0, widget.apiBaseUrl.length - 1)
        : widget.apiBaseUrl;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$normalizedBase/$normalizedPath');
  }

  Future<void> _loadStudentProfile() async {
    String resolvedName = '';
    try {
      final profile = await ProfileService.fetchProfile(
        role: 'student',
        id: widget.recipientNumber,
      );
      resolvedName = profile.name.trim();
    } catch (_) {
      try {
        final uri = _endpoint('get_student_info.php').replace(
          queryParameters: {'student_id': widget.recipientNumber},
        );
        final response = await _client
            .get(
              uri,
              headers: AppSessionService.instance.authorizationHeaders,
            )
            .timeout(const Duration(seconds: 12));
        if (await AppSessionService.instance.handleResponse(response)) return;
        final data = _decodeObject(response.body);
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            data?['status']?.toString().toLowerCase() == 'success') {
          resolvedName = data?['name']?.toString().trim() ?? '';
          _failedPinAttempts =
              int.tryParse(data?['failed_attempts']?.toString() ?? '') ?? 0;
          _isProfileLocked = _asBool(data?['is_locked']);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _studentName = resolvedName);
  }

  Future<void> _fetchProducts() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final response = await _client
          .get(
            posProductCatalogUri(
              widget.apiBaseUrl,
              canteenId: widget.canteenId,
            ),
            headers: AppSessionService.instance.authorizationHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (await AppSessionService.instance.handleResponse(response)) return;

      final data = _decodeObject(response.body);
      if (data == null) {
        throw const FormatException(
            'The product server returned invalid data.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['status']?.toString().toLowerCase() != 'success') {
        throw Exception(
          data['message']?.toString().trim().isNotEmpty == true
              ? data['message'].toString()
              : 'Products could not be loaded.',
        );
      }

      final oldQuantities = <int, int>{
        for (final product in _products) product.productId: product.qty,
      };
      final loaded = <Product>[];
      Object? rawProducts = data['products'];
      if (rawProducts is Map) rawProducts = rawProducts.values.toList();
      if (rawProducts is List) {
        for (final value in rawProducts) {
          if (value is! Map) continue;
          final item = Map<String, dynamic>.from(value);
          final id = int.tryParse(item['product_id']?.toString() ?? '');
          final name = item['name']?.toString().trim() ?? '';
          final price = double.tryParse(item['price']?.toString() ?? '');
          final stock = int.tryParse(item['stock_qty']?.toString() ?? '') ?? 0;
          final active =
              item.containsKey('is_active') ? _asBool(item['is_active']) : true;
          if (id == null ||
              id <= 0 ||
              name.isEmpty ||
              price == null ||
              price <= 0 ||
              stock < 1 ||
              !active) {
            continue;
          }
          final requestedQuantity = oldQuantities[id] ?? 0;
          loaded.add(
            Product(
              id,
              name,
              price,
              category: normalizePosCategory(item['category']),
              stockQty: stock,
              qty: requestedQuantity.clamp(0, stock).toInt(),
            ),
          );
        }
      }

      final rawCategories = data['categories'];
      final serverCategories = rawCategories is List
          ? rawCategories.cast<Object?>()
          : const <Object?>[];
      final categories = posProductCategories(loaded, serverCategories);
      if (!mounted) return;
      setState(() {
        _products = loaded;
        _categories = categories;
        if (!categories.contains(_selectedCategory)) {
          _selectedCategory = posAllCategory;
        }
      });
    } on TimeoutException {
      _showSnack('Loading products timed out. Check the connection and retry.');
    } catch (error) {
      _showSnack(_cleanError(error, fallback: 'Products could not be loaded.'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  String _cleanError(Object error, {required String fallback}) {
    final text = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return text.trim().isEmpty ? fallback : text;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeQuantity(Product product, int delta) {
    final next = (product.qty + delta).clamp(0, product.stockQty).toInt();
    if (next == product.qty) {
      if (delta > 0 && product.qty >= product.stockQty) {
        _showSnack('Only ${product.stockQty} ${product.name} available.');
      }
      return;
    }
    setState(() => product.qty = next);
  }

  void _openSummary() {
    if (_cartItems.isEmpty) {
      _showSnack('Select at least one product before continuing.');
      return;
    }
    if (_total > _maxTransactionAmount) {
      _showSnack('The order cannot exceed ${_money(_maxTransactionAmount)}.');
      return;
    }
    setState(() => _stage = _FlowStage.orderSummary);
  }

  void _openPinEntry() {
    if (_isProfileLocked) {
      _showSnack('This student account is locked. Payment cannot continue.');
      return;
    }
    setState(() {
      _pin = '';
      _stage = _FlowStage.pinEntry;
    });
  }

  void _enterPinDigit(String digit) {
    if (_isSubmitting || _pin.length >= _pinLength) return;
    final nextPin = '$_pin$digit';
    setState(() => _pin = nextPin);
    if (nextPin.length == _pinLength) {
      unawaited(_confirmPayment());
    }
  }

  void _removePinDigit() {
    if (_isSubmitting || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _confirmPayment() async {
    if (_isSubmitting) return;
    if (_pin.length != _pinLength) {
      _showSnack('Enter the student\'s 6-digit PIN.');
      return;
    }
    if (_cartItems.isEmpty || _total <= 0) {
      _showSnack('The cart is empty.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await _client
          .post(
            _endpoint('confirm_payment.php'),
            headers: AppSessionService.instance.authorizationHeaders,
            body: buildPosPaymentForm(
              studentNumber: widget.recipientNumber,
              pin: _pin,
              amount: _total,
              cashierId: widget.cashierId,
              canteenId: widget.canteenId,
              products: _cartItems,
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (await AppSessionService.instance.handleResponse(response)) return;

      final data = _decodeObject(response.body);
      if (data == null) {
        throw const FormatException(
            'The payment server returned invalid data.');
      }
      final success = response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['status']?.toString().toLowerCase() == 'success';
      if (success) {
        unawaited(TransactionNotificationService.refreshNow());
        final transactionId =
            int.tryParse(data['transaction_id']?.toString() ?? '');
        if (!mounted) return;
        setState(() {
          _transactionId = transactionId;
          _lastPaymentSuccess = true;
          _resultMessage = transactionId == null
              ? 'The payment was completed, but its receipt number was not returned. Check Transaction History before making another payment.'
              : '${_money(_total)} was paid by ${_displayStudentName()}.';
          _stage = _FlowStage.result;
          _pin = '';
        });
        unawaited(
          AppSessionService.instance.recordActivity(
            'canteen_checkout_completed',
            details: {
              if (transactionId != null) 'transaction_id': transactionId,
              'student_id': widget.recipientNumber,
              'amount': _total.toStringAsFixed(2),
            },
          ),
        );
        return;
      }

      final message = data['message']?.toString().trim();
      final locked = data['status']?.toString().toLowerCase() == 'locked' ||
          _asBool(data['is_locked']) ||
          (data['code']?.toString().toLowerCase() == 'account_locked');
      final failedAttempts = int.tryParse(
        data['failed_attempts']?.toString() ??
            data['attempts']?.toString() ??
            '',
      );
      if (!mounted) return;
      setState(() {
        if (failedAttempts != null) _failedPinAttempts = failedAttempts;
        _isProfileLocked = locked;
        _lastPaymentSuccess = false;
        _resultMessage = message?.isNotEmpty == true
            ? message!
            : 'The payment was not completed. Please check the details and try again.';
        _stage = !locked && _resultMessage.toLowerCase().contains('pin')
            ? _FlowStage.pinEntry
            : _FlowStage.result;
        _pin = '';
      });
      if (_stage == _FlowStage.pinEntry) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_resultMessage)));
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _lastPaymentSuccess = false;
        _resultMessage =
            'The server did not answer in time. Check Transaction History before retrying to avoid charging the student twice.';
        _stage = _FlowStage.result;
        _pin = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastPaymentSuccess = false;
        _resultMessage = _cleanError(
          error,
          fallback: 'The payment could not be completed.',
        );
        _stage = _FlowStage.result;
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _displayStudentName() =>
      _studentName.isEmpty ? widget.recipientNumber : _studentName;

  Future<void> _openCompletedReceipt() async {
    final transactionId = _transactionId;
    if (transactionId == null) {
      _returnToCanteenHome();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptScreen(
          transactionId: transactionId,
          viewerRole: 'canteen',
          viewerId: widget.canteenId,
          showCloseButton: true,
        ),
      ),
    );
    if (mounted) _returnToCanteenHome();
  }

  void _returnToCanteenHome() {
    widget.onNavigate?.call(0);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<bool> _handleBack() async {
    if (_isSubmitting) return false;
    switch (_stage) {
      case _FlowStage.productSelection:
        return true;
      case _FlowStage.orderSummary:
        setState(() => _stage = _FlowStage.productSelection);
        return false;
      case _FlowStage.pinEntry:
        setState(() {
          _pin = '';
          _stage = _FlowStage.orderSummary;
        });
        return false;
      case _FlowStage.result:
        if (_lastPaymentSuccess == true) {
          await _openCompletedReceipt();
        } else {
          setState(() {
            _pin = '';
            _stage = _FlowStage.productSelection;
          });
        }
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usesLegacyPaymentLayout =
        _stage == _FlowStage.pinEntry || _stage == _FlowStage.result;
    return PopScope<Object?>(
      canPop: !_isSubmitting && _stage == _FlowStage.productSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: usesLegacyPaymentLayout
          ? _buildLegacyPaymentScaffold()
          : Scaffold(
              backgroundColor: const Color(0xFFF8F4F4),
              appBar: AppBar(
                backgroundColor: _brandRed,
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text(_stageTitle),
                leading: IconButton(
                  tooltip: 'Back',
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          if (_stage == _FlowStage.productSelection) {
                            Navigator.of(context).pop();
                          } else {
                            unawaited(_handleBack());
                          }
                        },
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              body: SafeArea(child: _buildStage()),
            ),
    );
  }

  Widget _buildLegacyPaymentScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F1F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F1F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        toolbarHeight: 68,
        title: Image.asset('assets/icons/logo-red.png', height: 54),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Text(
                _stageTitle,
                key: const ValueKey('pos-legacy-stage-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _brandRed,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(42),
                      topRight: Radius.circular(42),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _stage == _FlowStage.pinEntry
                      ? _buildPinEntry()
                      : _buildResult(),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildLegacyBottomNav(),
          ),
          if (_isSubmitting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _stageTitle {
    switch (_stage) {
      case _FlowStage.productSelection:
        return 'New Order';
      case _FlowStage.orderSummary:
        return 'Order Summary';
      case _FlowStage.pinEntry:
        return 'Enter PIN';
      case _FlowStage.result:
        return _lastPaymentSuccess == true
            ? 'Payment Successful'
            : 'Payment Failed';
    }
  }

  Widget _buildStage() {
    switch (_stage) {
      case _FlowStage.productSelection:
        return _buildProductSelection();
      case _FlowStage.orderSummary:
        return _buildOrderSummary();
      case _FlowStage.pinEntry:
        return _buildPinEntry();
      case _FlowStage.result:
        return _buildResult();
    }
  }

  Widget _buildProductSelection() {
    return Column(
      children: [
        _buildStudentBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search products',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? _buildEmptyCatalog()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 96, child: _buildCategoryRail()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildProductGrid()),
                      ],
                    ),
        ),
        _buildCartFooter(),
      ],
    );
  }

  Widget _buildStudentBanner() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          ProfileAvatar(
            role: 'student',
            userId: widget.recipientNumber,
            radius: 24,
            backgroundColor: const Color(0xFFFFE2E2),
            iconColor: _brandRed,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PAYING STUDENT',
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _displayStudentName(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.recipientNumber,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified, color: Colors.green),
        ],
      ),
    );
  }

  Widget _buildCategoryRail() {
    return ColoredBox(
      color: const Color(0xFFFFF8F8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 7),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          return Material(
            color: selected ? _brandRed : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              key: ValueKey('pos-category-$category'),
              borderRadius: BorderRadius.circular(13),
              onTap: () => setState(() => _selectedCategory = category),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 14),
                child: Text(
                  category,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : _darkRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    final visible = _visibleProducts;
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No products match this category or search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 480
                ? 3
                : constraints.maxWidth >= 260
                    ? 2
                    : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: .72,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) => _buildProductCard(visible[index]),
        );
      },
    );
  }

  Widget _buildProductCard(Product product) {
    return Card(
      key: ValueKey('pos-product-${product.productId}'),
      elevation: product.qty > 0 ? 3 : 1,
      color: product.qty > 0 ? const Color(0xFFFFF0F0) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: product.qty > 0 ? _brandRed : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE1E1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.fastfood_outlined, color: _brandRed),
            ),
            const SizedBox(height: 8),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const Spacer(),
            Text(
              _money(product.price),
              style: const TextStyle(
                color: _brandRed,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '${product.stockQty} in stock',
              style: const TextStyle(color: Colors.black45, fontSize: 10),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _quantityButton(
                  tooltip: 'Remove one ${product.name}',
                  icon: Icons.remove,
                  enabled: product.qty > 0,
                  onPressed: () => _changeQuantity(product, -1),
                ),
                Text(
                  product.qty.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                _quantityButton(
                  tooltip: 'Add one ${product.name}',
                  icon: Icons.add,
                  enabled: product.qty < product.stockQty,
                  onPressed: () => _changeQuantity(product, 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quantityButton({
    required String tooltip,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: enabled ? _brandRed : Colors.black12,
          foregroundColor: Colors.white,
        ),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 17),
      ),
    );
  }

  Widget _buildEmptyCatalog() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 54, color: Colors.black38),
            const SizedBox(height: 12),
            const Text(
              'No products are available for checkout.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _fetchProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartFooter() {
    final itemCount =
        _cartItems.fold<int>(0, (sum, product) => sum + product.qty);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$itemCount item${itemCount == 1 ? '' : 's'}'),
                Text(
                  _money(_total),
                  style: const TextStyle(
                    color: _brandRed,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('pos-review-order'),
            style: FilledButton.styleFrom(
              backgroundColor: _brandRed,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            onPressed: itemCount == 0 ? null : _openSummary,
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('Review order'),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    final items = _cartItems.toList();
    return Column(
      children: [
        _buildStudentBanner(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(18),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 26),
            itemBuilder: (context, index) {
              final product = items[index];
              return Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFFFE2E2),
                    foregroundColor: _brandRed,
                    child: Text('${product.qty}x'),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${_money(product.price)} each',
                            style: const TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                  Text(
                    _money(product.price * product.qty),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              );
            },
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  Text(
                    _money(_total),
                    style: const TextStyle(
                      color: _brandRed,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('pos-continue-to-pin'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandRed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _openPinEntry,
                  child: const Text('Continue to student PIN'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinEntry() {
    if (_isProfileLocked) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 116),
          child: Text(
            'Profile locked. Payment cannot continue.\nPlease contact an administrator.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 122),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              key: const ValueKey('pos-pin-back'),
              tooltip: 'Back to order summary',
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() {
                        _pin = '';
                        _stage = _FlowStage.orderSummary;
                      }),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 2),
          ProfileAvatar(
            role: 'student',
            userId: widget.recipientNumber,
            radius: 36,
            fallbackIcon: Icons.person,
            iconColor: _brandRed,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 10),
          Text(
            _displayStudentName(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Student: ${widget.recipientNumber}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paying ${_money(_total)}',
            key: const ValueKey('pos-pin-payment-amount'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Semantics(
            label: '${_pin.length} of $_pinLength PIN digits entered',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pinLength,
                (index) => Container(
                  key: ValueKey('pos-pin-circle-$index'),
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        index < _pin.length ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          ),
          if (_failedPinAttempts > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Failed PIN attempts: $_failedPinAttempts',
              style: const TextStyle(
                color: Color(0xFFFFD7D7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildPinKeypad(),
        ],
      ),
    );
  }

  Widget _buildPinKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'DEL'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final keyValue = keys[index];
          final isBackspace = keyValue == 'DEL';
          final isDecimal = keyValue == '.';
          return OutlinedButton(
            key: ValueKey(
              isBackspace
                  ? 'pos-pin-backspace'
                  : isDecimal
                      ? 'pos-pin-decimal'
                      : 'pos-pin-$keyValue',
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _brandRed,
              side: const BorderSide(color: Color(0xFFD6CCE7), width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            onPressed: _isSubmitting
                ? null
                : isBackspace
                    ? _removePinDigit
                    : isDecimal
                        ? () {}
                        : () => _enterPinDigit(keyValue),
            child: isBackspace
                ? const Icon(Icons.backspace_outlined, size: 24)
                : Text(keyValue),
          );
        },
      ),
    );
  }

  Widget _buildResult() {
    final success = _lastPaymentSuccess == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6CCE7), width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    success ? Icons.check_circle : Icons.cancel,
                    size: 78,
                    color: success ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    success ? 'Payment Successful' : 'Payment Failed',
                    key: const ValueKey('pos-result-title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: success ? Colors.green : Colors.red,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _resultMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF2E2E2E),
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const ValueKey('pos-result-primary'),
              onPressed: success
                  ? _openCompletedReceipt
                  : () => setState(() {
                        _pin = '';
                        _stage = _FlowStage.productSelection;
                      }),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _brandRed,
                minimumSize: const Size(double.infinity, 58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                success ? 'Done' : 'Try Again',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 108),
        ],
      ),
    );
  }

  Widget _buildLegacyBottomNav() {
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F1F1),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(46),
          topRight: Radius.circular(46),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _legacyNavImage('assets/icons/home-red.png', 0),
          _legacyNavImage('assets/icons/history-red.png', 1),
          _legacyNavImage('assets/icons/qr-white.png', 2, selected: true),
          _legacyNavIcon(Icons.inventory_2_outlined, 3, tooltip: 'Products'),
          _legacyNavIcon(Icons.person_outline, 4, tooltip: 'Profile'),
        ],
      ),
    );
  }

  Widget _legacyNavImage(
    String asset,
    int index, {
    bool selected = false,
  }) {
    return InkWell(
      onTap: _isSubmitting ? null : () => _leaveCheckoutForTab(index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Image.asset(asset),
      ),
    );
  }

  Widget _legacyNavIcon(
    IconData icon,
    int index, {
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: _isSubmitting ? null : () => _leaveCheckoutForTab(index),
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: _brandRed, size: 28),
        ),
      ),
    );
  }

  void _leaveCheckoutForTab(int index) {
    widget.onNavigate?.call(index);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  String _money(num value) {
    final fixed = value.toStringAsFixed(2).split('.');
    final whole = fixed.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '\u20B1$whole.${fixed.last}';
  }
}
