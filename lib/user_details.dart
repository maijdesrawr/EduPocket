import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';
import 'app_session_service.dart';

class UserDetails extends StatelessWidget {
  final Map<String, dynamic> user;
  final String category;

  const UserDetails({super.key, required this.user, required this.category});

  Icon _getIcon(String label) {
    switch (label.toLowerCase()) {
      case 'name':
        return const Icon(Icons.person, color: Colors.white);
      case 'student number':
      case 'parent id':
      case 'canteen id':
      case 'cashier id':
        return const Icon(Icons.badge, color: Colors.white);
      case 'linked parent':
      case 'linked student':
        return const Icon(Icons.link, color: Colors.white);
      case 'balance':
        return const Icon(Icons.account_balance_wallet, color: Colors.white);
      case 'location':
        return const Icon(Icons.location_on, color: Colors.white);
      case 'canteen name':
        return const Icon(Icons.store, color: Colors.white);
      case 'username':
        return const Icon(Icons.account_circle, color: Colors.white);
      default:
        return const Icon(Icons.info, color: Colors.white);
    }
  }

  Widget _buildDetailCard(String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black26.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _getIcon(label),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editUser(BuildContext context) async {
    final nameController = TextEditingController(text: user['name'] ?? '');
    final locationController =
        TextEditingController(text: user['location'] ?? '');
    final linkedController = TextEditingController(
        text: category == 'student'
            ? (user['parent_id'] ?? '')
            : (user['student_nums'] ?? user['student_num'] ?? ''));
    final usernameController =
        TextEditingController(text: user['username'] ?? '');
    final canteenController =
        TextEditingController(text: user['canteen_id'] ?? '');

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Edit User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  readOnly: false,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    filled: true,
                    fillColor: Colors.black12,
                  ),
                ),
                if (category == 'pos')
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(labelText: 'Location'),
                  ),
                if (category == 'student' || category == 'parent')
                  TextField(
                    controller: linkedController,
                    decoration: InputDecoration(
                      labelText: category == 'student'
                          ? 'Linked Parent ID'
                          : 'Linked Student IDs (comma separated)',
                    ),
                  ),
                if (category == 'cashier')
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name is required')),
                  );
                  return;
                }

                if (category == 'student') {
                  final studentNum = user['student_num'] ?? '';

                  if (studentNum.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Student Number is required')),
                    );
                    return;
                  }

                  if (!RegExp(r'^[A-Za-z0-9_-]{1,20}$')
                      .hasMatch(user['student_num'] ?? '')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid student number')),
                    );
                    return;
                  }
                }

                final id = category == 'student'
                    ? user['student_num']
                    : category == 'parent'
                        ? user['parent_id']
                        : category == 'pos'
                            ? user['canteen_id']
                            : user['cashier_id'];

                final body = {
                  'category': category,
                  'id': id,
                  'Fname': nameController.text,
                  'location': locationController.text,
                  'username':
                      category == 'cashier' ? usernameController.text : '',
                  'canteen_id':
                      category == 'cashier' ? canteenController.text : '',
                };

                if (category == 'student' || category == 'parent') {
                  body['linked_id'] = linkedController.text.trim();
                }
                try {
                  final response = await http.post(
                    Uri.parse(ApiConfig.url('koyah_nabago.php')),
                    headers: AppSessionService.instance.authorizationHeaders,
                    body: body,
                  );

                  if (!context.mounted) return;
                  if (response.statusCode == 200) {
                    final data = jsonDecode(response.body);
                    final status = data['status'] ?? 'error';
                    final message = data['message'] ?? 'Unknown error';

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );

                    if (status == 'success') {
                      Navigator.pop(context);
                      Navigator.pop(context, true);
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('HTTP Error: ${response.statusCode}')),
                    );
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteUser(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text(
            'Delete this account permanently? The account will be removed, and its transaction history and receipts will be retained. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final id = category == 'student'
          ? user['student_num']
          : category == 'parent'
              ? user['parent_id']
              : category == 'pos'
                  ? user['canteen_id']
                  : user['cashier_id'];

      final response = await http.post(
        Uri.parse(ApiConfig.url('account_delete.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'category': category,
          'id': id,
        },
      );
      if (!context.mounted) return;

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (data['message'] ?? 'User deleted successfully!').toString(),
            ),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (data['message'] ?? 'The user could not be deleted.').toString(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> details = [];

    if (category == 'student') {
      details = [
        _buildDetailCard('Name', user['name'] ?? ''),
        _buildDetailCard('Student Number', user['student_num'] ?? ''),
        _buildDetailCard('Linked Parent', user['parent_name'] ?? 'None'),
        _buildDetailCard(
          'Balance',
          user['balance'] != null
              ? '\u20B1${double.tryParse(user['balance'].toString())?.toStringAsFixed(2) ?? '0.00'}'
              : '\u20B10.00',
        ),
      ];
    } else if (category == 'parent') {
      details = [
        _buildDetailCard('Name', user['name'] ?? ''),
        _buildDetailCard('Parent ID', user['parent_id'] ?? ''),
        _buildDetailCard('Linked Students', user['student_name'] ?? 'None'),
      ];
    } else if (category == 'pos') {
      details = [
        _buildDetailCard('Canteen Name', user['name'] ?? ''),
        _buildDetailCard('Canteen ID', user['canteen_id'] ?? ''),
        _buildDetailCard('Location', user['location'] ?? 'Not set'),
      ];
    } else if (category == 'cashier') {
      details = [
        _buildDetailCard('Name', user['name'] ?? ''),
        _buildDetailCard('Cashier ID', user['cashier_id'] ?? ''),
        _buildDetailCard('Username', user['username'] ?? ''),
      ];
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 251, 251, 251),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Color.fromARGB(255, 134, 23, 23)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  Image.asset('assets/redlogo.png', height: 40),
                  const SizedBox(width: 12),
                  const Text(
                    'User Details',
                    style: TextStyle(
                        color: Color.fromARGB(255, 134, 23, 23),
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 196, 25, 25),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                children: [
                  ...details,
                  if (category == 'parent')
                    TextButton.icon(
                        onPressed: () => _editUser(context),
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: const Text('Link another student',
                            style: TextStyle(color: Colors.white))),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                          context, Icons.edit, 'Edit', _editUser),
                      _buildActionButton(
                          context, Icons.delete, 'Delete', _deleteUser),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    IconData icon,
    String label,
    void Function(BuildContext) onTap,
  ) {
    return GestureDetector(
      onTap: () => onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black26.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color.fromARGB(255, 134, 23, 23)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                  color: Color.fromARGB(255, 134, 23, 23),
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
