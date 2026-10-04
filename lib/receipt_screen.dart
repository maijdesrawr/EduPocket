import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'app_session_service.dart';

@visibleForTesting
const String officialReceiptSubtitle = 'OFFICIAL TRANSACTION RECEIPT';

@visibleForTesting
Uri receiptDataUri(int transactionId, {String? baseUrl}) {
  final base = baseUrl ?? ApiConfig.baseUrl;
  final normalizedBase =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return Uri.parse('$normalizedBase/get_receipt.php').replace(
    queryParameters: {'transaction_id': transactionId.toString()},
  );
}

@visibleForTesting
Uri printableReceiptUri(String printToken, {String? baseUrl}) {
  final base = baseUrl ?? ApiConfig.baseUrl;
  final normalizedBase =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return Uri.parse('$normalizedBase/official_receipt.php').replace(
    queryParameters: {'print_token': printToken},
  );
}

@visibleForTesting
String resolveReceiptProcessedBy(Map<String, dynamic> receipt) {
  String usableName(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty ||
        normalized.toLowerCase() == 'n/a' ||
        normalized.toLowerCase() == 'null') {
      return '';
    }
    return normalized;
  }

  String nameFrom(dynamic value) {
    if (value is Map) {
      for (final key in const ['name', 'Fname', 'fname', 'display_name']) {
        final name = usableName(value[key]);
        if (name.isNotEmpty) return name;
      }
      return '';
    }
    return usableName(value);
  }

  final processedBy = nameFrom(receipt['processed_by']);
  if (processedBy.isNotEmpty) return processedBy;

  final processedByName = usableName(receipt['processed_by_name']);
  if (processedByName.isNotEmpty) return processedByName;

  final cashierName = nameFrom(receipt['cashier']);
  if (cashierName.isNotEmpty) return cashierName;

  final canteenName = nameFrom(receipt['canteen']);
  return canteenName.isNotEmpty ? canteenName : 'N/A';
}

class ReceiptScreen extends StatefulWidget {
  final int transactionId;
  final String viewerRole;
  final String viewerId;
  final bool showCloseButton;
  final VoidCallback? onClose;

  const ReceiptScreen({
    super.key,
    required this.transactionId,
    required this.viewerRole,
    required this.viewerId,
    this.showCloseButton = false,
    this.onClose,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  static const Color _receiptRed = Color(0xFFC62828);

  Map<String, dynamic>? _receipt;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isIssuingPrintToken = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSessionService.instance.recordActivity(
        'receipt_view',
        details: {'transaction_id': widget.transactionId},
      ),
    );
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await http
          .get(
            receiptDataUri(widget.transactionId),
            headers: AppSessionService.instance.authorizationHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (await AppSessionService.instance.handleResponse(response)) {
        _showLoadError(
            'Your session is no longer active. Please log in again.');
        return;
      }
      if (response.statusCode != 200) {
        final error = _decodeObject(response.body);
        throw FormatException(
          _text(
            error?['message'],
            fallback: 'The receipt service is unavailable.',
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The receipt response was invalid.');
      }
      if (decoded['status'] != 'success' || decoded['receipt'] is! Map) {
        throw FormatException(
          (decoded['message'] ?? 'This receipt is unavailable.').toString(),
        );
      }

      if (!mounted) return;
      setState(() {
        _receipt = Map<String, dynamic>.from(decoded['receipt'] as Map);
        _isLoading = false;
      });
    } on TimeoutException {
      _showLoadError('The receipt request timed out. Please try again.');
    } on FormatException catch (error) {
      _showLoadError(error.message);
    } catch (_) {
      _showLoadError(
        'The receipt could not be loaded. Check your connection and try again.',
      );
    }
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _receipt = null;
      _errorMessage = message;
      _isLoading = false;
    });
  }

  Future<void> _openPrintableReceipt() async {
    if (_isIssuingPrintToken) return;
    if (mounted) {
      setState(() => _isIssuingPrintToken = true);
    }
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('issue_receipt_print_token.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {'transaction_id': widget.transactionId.toString()},
      ).timeout(const Duration(seconds: 15));
      if (await AppSessionService.instance.handleResponse(response)) {
        _showMessage('Your session is no longer active. Please log in again.');
        return;
      }
      final decoded = _decodeObject(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded?['status'] != 'success') {
        throw FormatException(
          _text(
            decoded?['message'],
            fallback: 'The printable receipt link could not be created.',
          ),
        );
      }
      final printToken = _text(decoded?['print_token']);
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(printToken)) {
        throw const FormatException(
          'The receipt service returned an invalid print link.',
        );
      }
      final opened = await launchUrl(
        printableReceiptUri(printToken),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _showMessage('No browser is available to print this receipt.');
      }
    } on TimeoutException {
      _showMessage(
          'The printable receipt request timed out. Please try again.');
    } on FormatException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('The printable receipt could not be opened.');
    } finally {
      if (mounted) {
        setState(() => _isIssuingPrintToken = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: _receiptRed,
        foregroundColor: Colors.white,
        title: const Text(
          'Official Receipt',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: widget.showCloseButton
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: OutlinedButton.icon(
                  key: const ValueKey('receipt-close-button'),
                  onPressed:
                      widget.onClose ?? () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _receiptRed,
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: _receiptRed, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _receiptRed),
      );
    }

    final receipt = _receipt;
    if (receipt == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: Colors.black38,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'This receipt is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadReceipt,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(backgroundColor: _receiptRed),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _receiptRed,
      onRefresh: _loadReceipt,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildReceipt(receipt),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isIssuingPrintToken ? null : _openPrintableReceipt,
            icon: _isIssuingPrintToken
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print_outlined),
            label: Text(
              _isIssuingPrintToken
                  ? 'Preparing secure receipt...'
                  : 'Print or save receipt',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _receiptRed,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceipt(Map<String, dynamic> receipt) {
    final student = _asMap(receipt['student']);
    final items = _receiptItems(receipt);
    final processedBy = resolveReceiptProcessedBy(receipt);

    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EduPocket',
                        style: TextStyle(
                          color: _receiptRed,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        officialReceiptSubtitle,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'PAID',
                    style: TextStyle(
                      color: Color(0xFF16803A),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: _receiptRed, thickness: 2),
            const SizedBox(height: 10),
            Text(
              _text(receipt['receipt_number'], fallback: 'Receipt'),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _formatTimestamp(_text(receipt['date_time'])),
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                _detail(
                  'Student',
                  _text(student['name'], fallback: 'N/A'),
                ),
                _detail(
                  'Student ID',
                  _text(student['id'], fallback: 'N/A'),
                ),
                _detail('Processed by:', processedBy),
                _detail(
                  'Transaction',
                  '#${_text(receipt['transaction_id'], fallback: widget.transactionId.toString())}',
                ),
                _detail('Status', 'Paid'),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Transaction details',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ...items.map(_buildItem),
            const Divider(height: 1),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  _money(receipt['amount']),
                  style: const TextStyle(
                    color: _receiptRed,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'This computer-generated official receipt is valid without a signature.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    final width = (MediaQuery.sizeOf(context).width - 92) / 2;
    return SizedBox(
      width: width.clamp(120.0, 300.0).toDouble(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black45, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final quantity = int.tryParse(_text(item['quantity'])) ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(item['name'], fallback: 'Payment'),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$quantity x ${_money(item['unit_price'])}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _money(item['line_total']),
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _receiptItems(Map<String, dynamic> receipt) {
    final rawItems = receipt['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final description = _text(
      receipt['description'],
      fallback:
          _titleCase(_text(receipt['transaction_type'], fallback: 'Payment')),
    );
    return [
      {
        'name': description,
        'quantity': 1,
        'unit_price': receipt['amount'],
        'line_total': receipt['amount'],
      },
    ];
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Map<String, dynamic>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  String _text(dynamic value, {String fallback = ''}) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  String _money(dynamic value) {
    final normalized = _text(value).replaceAll(',', '');
    final amount = double.tryParse(normalized) ?? 0;
    final fixed = amount.toStringAsFixed(2).split('.');
    final whole = fixed.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '\u20B1$whole.${fixed.last}';
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return 'Date unavailable';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final date =
        '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    final hour = parsed.hour > 12
        ? parsed.hour - 12
        : (parsed.hour == 0 ? 12 : parsed.hour);
    final minute = parsed.minute.toString().padLeft(2, '0');
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    return '$date \u2022 $hour:$minute $period';
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'[-_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
