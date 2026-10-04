import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

import 'pos_order_summary.dart';

class PosCartProduct {
  final int productId;
  String name;
  double price;
  int qty;

  PosCartProduct({
    required this.productId,
    required this.name,
    required this.price,
    this.qty = 0,
  });
}

class PosCartScreen extends StatefulWidget {
  final String canteenId;
  final VoidCallback? onCheckout;
  final String apiBaseUrl;

  const PosCartScreen({
    super.key,
    required this.canteenId,
    this.onCheckout,
    this.apiBaseUrl = ApiConfig.baseUrl,
  });

  @override
  State<PosCartScreen> createState() => _PosCartScreenState();
}

class _PosCartScreenState extends State<PosCartScreen> {
  static const Color _brandRed = Color(0xFFC62828);

  final List<PosCartProduct> _products = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse(
        '${widget.apiBaseUrl}/get_products.php?canteen_id=${widget.canteenId}',
      );
      final response = await http.get(uri);
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        data = null;
      }

      if (data == null) {
        final preview = response.body.length > 200
            ? '${response.body.substring(0, 200)}...'
            : response.body;
        _showSnack('Invalid server response: $preview');
        return;
      }

      if (data['status'] == 'success') {
        final loaded = <PosCartProduct>[];
        var productsData = data['products'];

        if (productsData is Map) {
          productsData = productsData.values.toList();
        } else if (productsData is! List) {
          productsData = [];
        }

        for (final raw in productsData) {
          loaded.add(
            PosCartProduct(
              productId: int.parse(raw['product_id'].toString()),
              name: raw['name'].toString(),
              price: double.parse(raw['price'].toString()),
            ),
          );
        }

        setState(() {
          _products
            ..clear()
            ..addAll(loaded);
        });
      } else {
        _showSnack(data['message']?.toString() ?? 'Failed to load products');
      }
    } catch (e) {
      _showSnack('Error connecting to server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _changeQty(PosCartProduct product, bool increment) {
    setState(() {
      if (increment) {
        product.qty += 1;
      } else if (product.qty > 0) {
        product.qty -= 1;
      }
    });
  }

  double _total() {
    var sum = 0.0;
    for (final p in _products) {
      sum += p.price * p.qty;
    }
    return sum;
  }

  List<PosOrderSummaryItem> _selectedSummaryItems() {
    return _products
        .where((p) => p.qty > 0)
        .map(
          (p) => PosOrderSummaryItem(
            name: p.name,
            qty: p.qty,
            unitPrice: p.price,
          ),
        )
        .toList();
  }

  Future<void> _deleteProduct(PosCartProduct product) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${widget.apiBaseUrl}/delete_product.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'product_id': product.productId.toString()},
      );
      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        setState(() {
          _products.removeWhere((p) => p.productId == product.productId);
        });
      } else {
        _showSnack(data['message']?.toString() ?? 'Failed to delete product');
      }
    } catch (e) {
      _showSnack('Error connecting to server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEditProductDialog(PosCartProduct product) {
    final nameController = TextEditingController(text: product.name);
    final priceController =
        TextEditingController(text: product.price.toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Product'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Price is required';
                  }
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Price must be greater than 0';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context);
              await _updateProduct(
                product: product,
                name: nameController.text.trim(),
                price: priceController.text.trim(),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProduct({
    required PosCartProduct product,
    required String name,
    required String price,
  }) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${widget.apiBaseUrl}/update_product.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'product_id': product.productId.toString(),
          'name': name,
          'price': price,
        },
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          product.name = name;
          product.price = double.parse(price);
        });
      } else {
        _showSnack(data['message']?.toString() ?? 'Failed to update product');
      }
    } catch (e) {
      _showSnack('Error connecting to server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Product'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Price is required';
                  }
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Price must be greater than 0';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context);
              await _addProduct(
                name: nameController.text.trim(),
                price: priceController.text.trim(),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct({required String name, required String price}) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${widget.apiBaseUrl}/add_product.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'canteen_id': widget.canteenId.trim(),
          'name': name,
          'price': price,
        },
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        final id = int.parse(data['product_id'].toString());
        setState(() {
          _products.add(
            PosCartProduct(
              productId: id,
              name: name,
              price: double.parse(price),
            ),
          );
        });
      } else {
        _showSnack(data['message']?.toString() ?? 'Failed to add product');
      }
    } catch (e) {
      _showSnack('Error connecting to server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openOrderSummary() {
    final selected = _selectedSummaryItems();
    if (selected.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PosOrderSummaryScreen(
          items: selected,
          canteenId: widget.canteenId,
          apiBaseUrl: widget.apiBaseUrl,
          onConfirmPayment: widget.onCheckout,
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F1F1),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(46),
          topRight: Radius.circular(46),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navIcon('assets/icons/home-red.png', false),
          _navIcon('assets/icons/history-red.png', false),
          _navIcon('assets/icons/qr-white.png', true),
        ],
      ),
    );
  }

  Widget _navIcon(String iconPath, bool selected) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? _brandRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(12),
        child: Image.asset(iconPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _total();
    final hasSavedProducts = _products.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F1F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F1F1),
        elevation: 0,
        centerTitle: true,
        title: Image.asset('assets/icons/logo-red.png', height: 58),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 6),
              const Text(
                "What's On Your Cart?",
                style: TextStyle(
                  color: _brandRed,
                  fontSize: 32 / 1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(48),
                      topRight: Radius.circular(48),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            'Products',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30 / 1.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: hasSavedProducts
                              ? GridView.count(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                  children: [
                                    ..._products.map(_buildProductCard),
                                    _buildAddNewItemCard(),
                                  ],
                                )
                              : Align(
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: 132,
                                    height: 82,
                                    child: _buildAddNewItemCard(),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFE6E6E6),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      color: Color(0xFF4A4A4A),
                                      fontSize: 26 / 1.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '\u20B1${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFF4A4A4A),
                                      fontSize: 26 / 1.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (total <= 0) {
                                      _showSnack('Please select at least 1 item');
                                      return;
                                    }
                                    _openOrderSummary();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: const Color(0xFF36C35C),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  child: const Text(
                                    'Go to Checkout',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(alignment: Alignment.bottomCenter, child: _buildBottomNav()),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(PosCartProduct product) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9D9D9), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF3F3F3F),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _iconTap(
                icon: Icons.edit_outlined,
                onTap: () => _showEditProductDialog(product),
              ),
              const SizedBox(width: 8),
              _iconTap(
                icon: Icons.delete_outline,
                onTap: () => _deleteProduct(product),
              ),
            ],
          ),
          const Text(
            '1pc',
            style: TextStyle(
              color: Color(0xFF8A8A8A),
              fontSize: 10,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '\u20B1${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF3F3F3F),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _qtyButton(
                icon: Icons.remove,
                color: const Color(0xFFB5B5B5),
                onTap: () => _changeQty(product, false),
              ),
              const SizedBox(width: 8),
              Text(
                '${product.qty}',
                style: const TextStyle(
                  color: Color(0xFF4A4A4A),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              _qtyButton(
                icon: Icons.add,
                color: const Color(0xFFFF5A5A),
                onTap: () => _changeQty(product, true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _iconTap({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Icon(
        icon,
        size: 14,
        color: const Color(0xFFFF5A5A),
      ),
    );
  }

  Widget _buildAddNewItemCard() {
    return InkWell(
      onTap: _showAddProductDialog,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD9D9D9), width: 1.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Add New Item',
              style: TextStyle(
                color: Color(0xFF4A4A4A),
                fontSize: 13 / 1.2,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationThickness: 1.2,
              ),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.add_circle,
              size: 16,
              color: Color(0xFFFF4D57),
            ),
          ],
        ),
      ),
    );
  }
}

