import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_config.dart';
import 'canteen_product_management_service.dart';

class CanteenProductManagementScreen extends StatefulWidget {
  const CanteenProductManagementScreen({
    required this.canteenId,
    this.apiBaseUrl = ApiConfig.baseUrl,
    this.service,
    this.showAppBar = true,
    super.key,
  });

  final String canteenId;
  final String apiBaseUrl;
  final CanteenProductRepository? service;
  final bool showAppBar;

  @override
  State<CanteenProductManagementScreen> createState() =>
      _CanteenProductManagementScreenState();
}

class _CanteenProductManagementScreenState
    extends State<CanteenProductManagementScreen> {
  static const _brandRed = Color(0xFFC62828);
  static const _surface = Color(0xFFF8F4F4);

  final _searchController = TextEditingController();
  late final CanteenProductRepository _service;
  late final bool _ownsService;

  List<CanteenProduct> _products = const [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  bool _isMutating = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ??
        CanteenProductManagementService(apiBaseUrl: widget.apiBaseUrl);
    _searchController.addListener(_refreshSearch);
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    if (_ownsService) _service.close();
    super.dispose();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final products = await _service.fetchProducts(
        canteenId: widget.canteenId,
      );
      if (!mounted) return;
      setState(() {
        _products = _sorted(products);
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = 'All';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<CanteenProduct> _sorted(Iterable<CanteenProduct> products) {
    final sorted = products.toList(growable: false);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  List<String> get _categories {
    final categories = _products
        .map((product) => product.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...categories];
  }

  List<CanteenProduct> get _visibleProducts {
    final query = _searchController.text.trim().toLowerCase();
    return _products.where((product) {
      final inCategory =
          _selectedCategory == 'All' || product.category == _selectedCategory;
      final matchesSearch = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
      return inCategory && matchesSearch;
    }).toList(growable: false);
  }

  Future<void> _openProductForm([CanteenProduct? product]) async {
    if (_isMutating) return;
    final input = await showModalBottomSheet<CanteenProductInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProductFormSheet(
        product: product,
        knownCategories: _categories.where((value) => value != 'All').toList(),
      ),
    );
    if (input == null || !mounted) return;

    setState(() => _isMutating = true);
    try {
      if (product == null) {
        final added = await _service.addProduct(
          canteenId: widget.canteenId,
          input: input,
        );
        if (!mounted) return;
        setState(() => _products = _sorted([..._products, added]));
        _showMessage('Product added successfully.');
      } else {
        final updated = await _service.updateProduct(
          canteenId: widget.canteenId,
          product: product,
          input: input,
        );
        if (!mounted) return;
        setState(() {
          _products = _sorted(
            _products.map(
              (entry) => entry.productId == updated.productId ? updated : entry,
            ),
          );
          if (!_categories.contains(_selectedCategory)) {
            _selectedCategory = 'All';
          }
        });
        _showMessage('Product updated successfully.');
      }
    } catch (error) {
      _showMessage(_messageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _confirmDelete(CanteenProduct product) async {
    if (_isMutating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          'Remove "${product.name}" from your product list? This product will '
          'no longer be available for new orders.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-delete-product'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-product'),
            style: FilledButton.styleFrom(backgroundColor: _brandRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMutating = true);
    try {
      await _service.deleteProduct(
        canteenId: widget.canteenId,
        productId: product.productId,
      );
      if (!mounted) return;
      setState(() {
        _products = _products
            .where((entry) => entry.productId != product.productId)
            .toList(growable: false);
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = 'All';
        }
      });
      _showMessage('Product deleted.');
    } catch (error) {
      _showMessage(_messageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  String _messageFor(Object error) {
    if (error is CanteenProductManagementException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? Colors.red.shade800 : Colors.green.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        _buildBody(),
        if (_isMutating)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: CircularProgressIndicator(color: _brandRed),
              ),
            ),
          ),
      ],
    );

    if (!widget.showAppBar) {
      return Material(
        color: _surface,
        child: SafeArea(top: false, child: body),
      );
    }
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _brandRed,
        elevation: 0,
        title: const Text(
          'Product Management',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(22, widget.showAppBar ? 4 : 20, 22, 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE6E6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: _brandRed),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Products',
                      style: TextStyle(
                        color: _brandRed,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Add items and keep prices and stock up to date.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('add-product-button'),
                onPressed: _isMutating ? null : _openProductForm,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandRed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
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
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('product-search-field'),
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search products or categories',
                    prefixIcon: const Icon(Icons.search, color: _brandRed),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final selected = category == _selectedCategory;
                      return ChoiceChip(
                        key: Key('product-category-$category'),
                        label: Text(category),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: Colors.white,
                        backgroundColor: const Color(0xFFFFB5B5),
                        labelStyle: TextStyle(
                          color: selected ? _brandRed : Colors.red.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                        side: BorderSide.none,
                        onSelected: (_) {
                          setState(() => _selectedCategory = category);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildProductContent()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_loadError != null) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Products could not be loaded',
        message: _loadError!,
        actionLabel: 'Try again',
        onAction: _loadProducts,
      );
    }
    if (_products.isEmpty) {
      return _MessageState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message: 'Add your first product to make it available after a QR scan.',
        actionLabel: 'Add product',
        onAction: _openProductForm,
      );
    }
    final visible = _visibleProducts;
    if (visible.isEmpty) {
      return const _MessageState(
        icon: Icons.search_off,
        title: 'No matching products',
        message: 'Try another search or category.',
      );
    }
    return RefreshIndicator(
      color: _brandRed,
      onRefresh: _loadProducts,
      child: ListView.separated(
        key: const Key('product-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _productCard(visible[index]),
      ),
    );
  }

  Widget _productCard(CanteenProduct product) {
    return Container(
      key: Key('product-card-${product.productId}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECEC),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.fastfood_outlined, color: _brandRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.category}  •  ${product.quantity} in stock',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Text(
                  '\u20B1${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: _brandRed,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('edit-product-${product.productId}'),
            tooltip: 'Edit ${product.name}',
            onPressed: _isMutating ? null : () => _openProductForm(product),
            icon: const Icon(Icons.edit_outlined, color: _brandRed),
          ),
          IconButton(
            key: Key('delete-product-${product.productId}'),
            tooltip: 'Delete ${product.name}',
            onPressed: _isMutating ? null : () => _confirmDelete(product),
            icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
          ),
        ],
      ),
    );
  }
}

class _ProductFormSheet extends StatefulWidget {
  const _ProductFormSheet({
    required this.product,
    required this.knownCategories,
  });

  final CanteenProduct? product;
  final List<String> knownCategories;

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  static const _brandRed = Color(0xFFC62828);
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _quantityController;
  late final TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _priceController = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    _quantityController = TextEditingController(
      text: product?.quantity.toString() ?? '',
    );
    _categoryController = TextEditingController(text: product?.category ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        18,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  editing ? 'Edit Product' : 'Add Product',
                  style: const TextStyle(
                    color: _brandRed,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('product-name-input'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 100,
                  decoration: _decoration('Product name', Icons.fastfood),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'Product name is required.';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('product-price-input'),
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            _decoration('Price', Icons.payments_outlined),
                        validator: (value) {
                          final price = double.tryParse(value?.trim() ?? '');
                          if (price == null || !price.isFinite || price <= 0) {
                            return 'Enter a price above 0.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('product-quantity-input'),
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _decoration(
                          'Quantity',
                          Icons.inventory_outlined,
                        ),
                        validator: (value) {
                          final quantity = int.tryParse(value?.trim() ?? '');
                          if (quantity == null || quantity < 1) {
                            return 'Minimum is 1.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('product-category-input'),
                  controller: _categoryController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 50,
                  decoration: _decoration(
                    'Category',
                    Icons.category_outlined,
                  ).copyWith(
                    helperText: 'Type an existing or new category.',
                  ),
                  validator: (value) {
                    if ((value?.trim() ?? '').isEmpty) {
                      return 'Category is required.';
                    }
                    return null;
                  },
                ),
                if (widget.knownCategories.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    children: widget.knownCategories.map((category) {
                      return ActionChip(
                        label: Text(category),
                        onPressed: () {
                          _categoryController.text = category;
                          _categoryController.selection =
                              TextSelection.collapsed(
                            offset: category.length,
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brandRed,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('save-product-button'),
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandRed,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: Text(editing ? 'Save changes' : 'Add product'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _brandRed),
      filled: true,
      fillColor: const Color(0xFFF8F4F4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _brandRed, width: 1.5),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CanteenProductInput(
        name: _nameController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        quantity: int.parse(_quantityController.text.trim()),
        category: _categoryController.text.trim(),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB8B8),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: const Color(0xFFC62828)),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
