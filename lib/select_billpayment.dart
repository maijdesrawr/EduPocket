import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';
import 'app_session_service.dart';
import 'cashier_topup-buttons.dart';
import 'cashier_amount_input_screen.dart';
import 'profile_avatar.dart';
import 'profile_service.dart';

class BillPaymentScreen extends StatefulWidget {
  final http.Client? client;
  final String studentNumber;
  final String cashierId;
  final ValueChanged<int>? onNavigate;

  const BillPaymentScreen({
    super.key,
    this.client,
    required this.studentNumber,
    required this.cashierId,
    this.onNavigate,
  });

  @override
  State<BillPaymentScreen> createState() => _BillPaymentScreenState();
}

class _BillPaymentScreenState extends State<BillPaymentScreen> {
  static const Color _brandRed = Color(0xFFAC2324);

  late final http.Client _client;
  bool _mutating = false;
  List<Map<String, dynamic>> _customPayments = [];
  bool _loading = true;
  String _studentName = '';

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    _fetchCustomPayments();
    _loadStudentProfile();
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _showMessage(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadStudentProfile() async {
    try {
      final profile = await ProfileService.fetchProfile(
        role: 'student',
        id: widget.studentNumber,
      );
      if (!mounted) return;
      setState(() => _studentName = profile.name);
    } catch (_) {}
  }

  Future<void> _fetchCustomPayments() async {
    setState(() => _loading = true);

    try {
      final res = await _client.get(
        Uri.parse(
          ApiConfig.url(
              'get_payment_options.php?cashier_id=${widget.cashierId}'),
        ),
      );

      if (!mounted) return;
      final data = jsonDecode(res.body);

      if (data['status'] == 'success') {
        setState(() {
          _customPayments = List<Map<String, dynamic>>.from(
            data['payments'].map((p) => {
                  'id': int.tryParse(p['id'].toString()) ?? 0,
                  'description': p['description'] ?? '',
                }),
          );
        });
      }
    } catch (e) {
      debugPrint('Error fetching payments: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPayment() async {
    String? description = await showDialog<String>(
      context: context,
      builder: (context) {
        String desc = '';
        return AlertDialog(
          title: const Text('Add New Payment'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter payment description',
            ),
            onChanged: (value) => desc = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, desc),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (description == null || description.trim().isEmpty || !mounted) return;

    try {
      final res = await _client.post(
        Uri.parse(ApiConfig.url('add_payment_option.php')),
        body: {
          'description': description.trim(),
          'cashier_id': widget.cashierId,
        },
      );

      if (!mounted) return;
      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (data['status'] == 'success') {
        setState(() {
          _customPayments.insert(0, {
            'id': int.tryParse(data['payment']['id'].toString()) ?? 0,
            'description': data['payment']['description'] ?? '',
          });
        });
        await _openCashierPayment(
          billPaymentId: int.tryParse(data['payment']['id'].toString()) ?? 0,
          description: data['payment']['description'].toString(),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Error')),
        );
      }
    } catch (e) {
      debugPrint('Error adding payment: $e');
    }
  }

  Future<void> _savePaymentOption(
      String endpoint, Map<String, String> body) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      final response = await _client
          .post(Uri.parse(ApiConfig.url(endpoint)),
              headers: AppSessionService.instance.authorizationHeaders,
              body: body)
          .timeout(const Duration(seconds: 20));
      if (await AppSessionService.instance.handleResponse(response) || !mounted)
        return;
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        await _fetchCustomPayments();
        _showMessage(data['message']?.toString() ?? 'Payment updated.');
      } else {
        _showMessage(data['message']?.toString() ??
            'Unable to update the payment. Please try again.');
      }
    } catch (_) {
      _showMessage('Unable to connect. Please try again.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _editPayment(int id, String currentDesc) async {
    if (_mutating) return;
    String description = currentDesc;
    final updated = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Edit Payment'),
              content: TextFormField(
                  initialValue: currentDesc,
                  autofocus: true,
                  maxLength: 255,
                  decoration: const InputDecoration(labelText: 'Payment name'),
                  onChanged: (value) => description = value),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      if (description.trim().isNotEmpty)
                        Navigator.pop(dialogContext, description.trim());
                    },
                    child: const Text('Save')),
              ],
            ));
    if (updated == null || !mounted) return;
    await _savePaymentOption('edit_payment_option.php',
        {'id': id.toString(), 'description': updated});
  }

  Future<void> _deletePayment(int id) async {
    if (_mutating) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Delete Payment?'),
              content: const Text(
                  'Delete this payment option? Existing transactions and receipts will remain available.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Delete')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    await _savePaymentOption(
        'delete_payment_option.php', {'id': id.toString()});
  }

  Future<void> _openCashierPayment({
    required int billPaymentId,
    required String description,
  }) async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => CashierBillPayScreen(
          recipientNumber: widget.studentNumber,
          cashierId: widget.cashierId,
          billPaymentId: billPaymentId,
          description: description,
          onNavigate: widget.onNavigate,
        ),
      ),
    );

    if (result is Map && result['navIndex'] is int && mounted) {
      widget.onNavigate?.call(result['navIndex'] as int);
      Navigator.pop(context);
      return;
    }

    if (result == true && mounted) {
      widget.onNavigate?.call(0);
      Navigator.pop(context);
    }
  }

  Future<void> _openStudentTopUp() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => CashierTopUpScreen(
          studentNumber: widget.studentNumber,
          cashierId: widget.cashierId,
          onNavigate: widget.onNavigate,
        ),
      ),
    );

    if (result is Map && result['navIndex'] is int && mounted) {
      widget.onNavigate?.call(result['navIndex'] as int);
      Navigator.pop(context);
      return;
    }

    if (result == true && mounted) {
      widget.onNavigate?.call(0);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentName =
        _studentName.trim().isEmpty ? 'Student Name Here' : _studentName.trim();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Stack(
              alignment: Alignment.center,
              children: [
                Center(child: Image.asset('assets/redlogo.png', height: 64)),
                Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back, color: _brandRed),
                      onPressed: () => Navigator.pop(context),
                    )),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Select Bill Payment',
              style: TextStyle(
                color: _brandRed,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _brandRed,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(52),
                    topRight: Radius.circular(52),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(52),
                    topRight: Radius.circular(52),
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                          children: [
                            const SizedBox(height: 4),
                            Center(
                              child: ProfileAvatar(
                                role: 'student',
                                userId: widget.studentNumber,
                                radius: 34,
                                fallbackIcon: Icons.person,
                                iconColor: _brandRed,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              studentName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Student: ${widget.studentNumber}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildOptionButton(
                              context,
                              title: 'Cashier Payment',
                              icon: Icons.school,
                              onTap: () => _openCashierPayment(
                                billPaymentId: 0,
                                description: 'Cashier Payment',
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildOptionButton(
                              context,
                              title: 'Student Top-Up',
                              icon: Icons.account_balance_wallet,
                              onTap: _openStudentTopUp,
                            ),
                            if (_customPayments.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              ..._customPayments.map((payment) {
                                final int billId = payment['id'] ?? 0;
                                final String desc =
                                    payment['description'] ?? 'Unknown';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _buildOptionButton(
                                    context,
                                    title: desc,
                                    icon: Icons.payment_outlined,
                                    onTap: () => _openCashierPayment(
                                      billPaymentId: billId,
                                      description: desc,
                                    ),
                                    onEdit: () => _editPayment(billId, desc),
                                    onDelete: () => _deletePayment(billId),
                                  ),
                                );
                              }),
                            ] else
                              const SizedBox(height: 18),
                            _buildOptionButton(
                              context,
                              title: 'Add New Payment',
                              icon: Icons.add,
                              onTap: _addPayment,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final hasCustomActions = onEdit != null || onDelete != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.only(
                    right: hasCustomActions ? 8 : 0,
                    top: 2,
                    bottom: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: _brandRed, size: 23),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: _brandRed,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: 'Edit payment',
                icon: const Icon(Icons.edit, color: _brandRed),
                onPressed: _mutating ? null : onEdit,
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            if (onDelete != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  tooltip: 'Delete payment',
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _mutating ? null : onDelete,
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: _brandRed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
