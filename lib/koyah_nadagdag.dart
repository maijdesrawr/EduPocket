import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'api_config.dart';

class AddUser extends StatefulWidget {
  final String category;
  const AddUser({super.key, required this.category});

  @override
  State<AddUser> createState() => _AddUserState();
}

class _AddUserState extends State<AddUser> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> controllers = {};

  List<Map<String, dynamic>> parents = [];
  String? selectedParentId;
  bool isLoadingParents = false;

  @override
  void dispose() {
    controllers.forEach((key, controller) {
      controller.dispose();
    });
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    if (widget.category == 'student') {
      controllers['student_first_name'] = TextEditingController();
      controllers['student_middle_name'] = TextEditingController();
      controllers['student_last_name'] = TextEditingController();
      controllers['student_suffix'] = TextEditingController();
      controllers['student_num'] = TextEditingController();

      controllers['parent_first_name'] = TextEditingController();
      controllers['parent_middle_name'] = TextEditingController();
      controllers['parent_last_name'] = TextEditingController();
      controllers['parent_suffix'] = TextEditingController();
    } else if (widget.category == 'child') {
      controllers['parent_id'] = TextEditingController();

      controllers['student_first_name'] = TextEditingController();
      controllers['student_middle_name'] = TextEditingController();
      controllers['student_last_name'] = TextEditingController();
      controllers['student_suffix'] = TextEditingController();
      controllers['student_num'] = TextEditingController();
    } else if (widget.category == 'pos') {
      controllers['name'] = TextEditingController();
      controllers['canteen_id'] = TextEditingController();
      controllers['location'] = TextEditingController();
      controllers['password'] = TextEditingController();
    } else if (widget.category == 'cashier') {
      controllers['name'] = TextEditingController();
      controllers['cashier_id'] = TextEditingController();
      controllers['username'] = TextEditingController();
      controllers['password'] = TextEditingController();
    }

    if (widget.category == 'child') {
      _loadParents();
    }
  }

  Future<void> _loadParents() async {
    if (widget.category != 'child') return;

    setState(() {
      isLoadingParents = true;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('koyah_nadagdag.php')),
        body: {
          'action': 'get_parents',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            parents = List<Map<String, dynamic>>.from(
              data['parents'] ?? [],
            );
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  data['message'] ?? 'Failed to load parents.',
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load existing parents.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading parents: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoadingParents = false;
        });
      }
    }
  }

  String formatLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String? getHelperText(String label) {
    switch (label) {
      case 'student_first_name':
        return 'Example: Juan or Juan Joseph';

      case 'student_middle_name':
        return 'Optional';

      case 'student_last_name':
        return 'Example: Dela Cruz';

      case 'student_suffix':
        return 'Optional (Jr., Sr., III)';

      case 'student_num':
        return '11 Digit Student Number';

      case 'parent_id':
        return 'Existing Parent ID';

      case 'parent_first_name':
        return 'Example: Maria or Maria Sofia';

      case 'parent_middle_name':
        return 'Optional';

      case 'parent_last_name':
        return 'Example: Santos';

      case 'parent_suffix':
        return 'Optional (Jr., Sr., III)';

      case 'name':
        return 'Example: Main Canteen';

      case 'canteen_id':
        return 'Example: CAN001';

      case 'location':
        return 'Example: Building A';

      case 'cashier_id':
        return 'Example: CASH001';

      case 'username':
        return 'Example: cashier01';

      case 'password':
        return 'Enter temporary password';

      default:
        return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final body = {'category': widget.category};

      controllers.forEach((key, controller) {
        if (controller.text.trim().isNotEmpty) {
          body[key] = controller.text.trim();
        }
      });

      final response = await http.post(
        Uri.parse(ApiConfig.url('koyah_nadagdag.php')),
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          if (widget.category == 'pos' || widget.category == 'cashier') {
            if (!mounted) return;
            await showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                      title: const Text('Success'),
                      content: Text(data['message']?.toString() ??
                          'Account created successfully.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Done'))
                      ],
                    ));
            if (mounted) Navigator.pop(context, true);
            return;
          }
          String credentials = "";

          if (widget.category == 'student') {
            credentials = "Student Number: ${data['student_num']}\n"
                "Student Temporary Password: ${data['student_temp_password']}\n"
                "Student Temporary PIN: ${data['student_temp_pin']}\n\n"
                "Parent ID: ${data['parent_id']}\n"
                "Parent Temporary Password: ${data['parent_temp_password']}";
          } else if (widget.category == 'child') {
            credentials = "Student Number: ${data['student_num']}\n"
                "Student Temporary Password: ${data['student_temp_password']}\n"
                "Student Temporary PIN: ${data['student_temp_pin']}\n"
                "Linked Parent ID: ${data['parent_id']}";
          } else {
            credentials = data['message'];
          }

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return AlertDialog(
                title: const Text(
                  "Account Created",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Please save these credentials:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(credentials),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text("Copy Credentials"),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: credentials,
                        ),
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Credentials copied!"),
                        ),
                      );
                    },
                  ),
                  TextButton(
                    child: const Text("Done"),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context, true);
                    },
                  )
                ],
              );
            },
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _buildTextField(String label, {bool required = true}) {
    bool isPassword = (label == 'password');

    bool isNumericOnly = label == 'student_num' ||
        label == 'parent_id' ||
        label == 'linked_student';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controllers[label],
        validator: required
            ? (val) => val == null || val.isEmpty ? 'Required' : null
            : null,
        obscureText: isPassword,
        keyboardType: isNumericOnly ? TextInputType.number : null,
        inputFormatters: isNumericOnly
            ? [
                FilteringTextInputFormatter.digitsOnly,
                if (label == 'student_num' || label == 'parent_id')
                  LengthLimitingTextInputFormatter(11),
              ]
            : null,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: formatLabel(label),
          helperText: getHelperText(label),
          helperStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
          errorStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildParentDropdown() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        value: selectedParentId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Parent ID',
          helperText: isLoadingParents
              ? 'Loading existing parents...'
              : 'Select an existing parent',
          helperStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
          labelStyle: const TextStyle(
            color: Colors.white70,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        dropdownColor: const Color.fromARGB(255, 134, 23, 23),
        hint: const Text(
          'Select Parent',
          style: TextStyle(
            color: Colors.white70,
          ),
        ),
        icon: const Icon(
          Icons.arrow_drop_down,
          color: Colors.white,
        ),
        style: const TextStyle(
          color: Colors.white,
        ),
        items: parents.map((parent) {
          final parentId = parent['parent_id'].toString();

          final firstName = parent['first_name']?.toString() ?? '';
          final middleName = parent['middle_name']?.toString() ?? '';
          final lastName = parent['last_name']?.toString() ?? '';
          final suffix = parent['suffix']?.toString() ?? '';

          final fullName = [
            firstName,
            middleName,
            lastName,
            suffix,
          ].where((name) => name.trim().isNotEmpty).join(' ');

          return DropdownMenuItem<String>(
            value: parentId,
            child: Text(
              '$parentId - $fullName',
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: isLoadingParents
            ? null
            : (value) {
                setState(() {
                  selectedParentId = value;
                  controllers['parent_id']!.text = value ?? '';
                });
              },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select a parent';
          }

          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayCategory =
        '${widget.category[0].toUpperCase()}${widget.category.substring(1)}';

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 251, 251, 251),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            color: const Color.fromARGB(255, 255, 255, 255),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color.fromARGB(255, 199, 42, 42),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Image.asset('assets/redlogo.png', height: 40),
                  const SizedBox(width: 12),
                  Text(
                    'Add $displayCategory',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
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
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    ...controllers.keys.map((key) {
                      if (widget.category == 'child' && key == 'parent_id') {
                        return _buildParentDropdown();
                      }

                      bool isRequired = true;

                      if (key.contains('middle_name') ||
                          key.contains('suffix') ||
                          (widget.category == 'student' &&
                              key == 'parent_id') ||
                          (widget.category == 'parent' &&
                              key == 'linked_student') ||
                          (widget.category == 'pos' && key == 'location') ||
                          (widget.category == 'cashier' &&
                              key == 'canteen_id')) {
                        isRequired = false;
                      }

                      return _buildTextField(
                        key,
                        required: isRequired,
                      );
                    }),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color.fromARGB(255, 134, 23, 23),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Add $displayCategory',
                        style: const TextStyle(
                          color: Color.fromARGB(255, 196, 25, 25),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
