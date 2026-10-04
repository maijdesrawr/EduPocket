import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'app_session_service.dart';
import 'login.dart';
import 'package:flutter/services.dart';

class ChangePasswordPage extends StatefulWidget {
  final String id;
  final String role;
  final String currentPassword;

  const ChangePasswordPage({
    super.key,
    required this.id,
    required this.role,
    required this.currentPassword,
  });

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final newPinController = TextEditingController();
  final confirmPinController = TextEditingController();

  bool obscurePassword = true;
  bool isSaving = false;

  bool isStrongPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
  }

  bool isValidPin(String pin) {
    
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      return false;
    }

    
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) {
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    newPinController.dispose();
    confirmPinController.dispose();

    super.dispose();
  }

  Future<void> changePassword() async {
    if (isSaving) return;

    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final newPin = newPinController.text.trim();
    final confirmPin = confirmPinController.text.trim();

    if (newPassword.isEmpty ||
        confirmPassword.isEmpty ||
        (widget.role == "student" && (newPin.isEmpty || confirmPin.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields"),
        ),
      );

      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Passwords do not match"),
        ),
      );

      return;
    }

    if (!isStrongPassword(newPassword)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must have 8+ characters, uppercase, lowercase, number, and special character",
          ),
        ),
      );

      return;
    }

    if (widget.role == "student") {
      if (newPin != confirmPin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("PIN does not match"),
          ),
        );

        return;
      }

      if (!isValidPin(newPin)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "PIN must be exactly 6 digits and cannot contain repeating numbers",
            ),
          ),
        );

        return;
      }
    }

    setState(() => isSaving = true);

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.url('change_password.php')),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          "id": widget.id,
          "role": widget.role,
          "current_password": widget.currentPassword,
          "password": newPassword,
          "pin": widget.role == "student" ? newPin : "",
        },
      ).timeout(const Duration(seconds: 8));
      await AppSessionService.instance.handleResponse(response);

      if (!mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Server error: ${response.statusCode}")),
        );
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      final data = decoded;

      if (data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password changed successfully"),
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginPage(),
          ),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                data['message']?.toString() ?? 'Unable to save credentials'),
          ),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("The server took too long to respond")),
      );
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("The server returned an invalid response")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not save the new credentials"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Change Password"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Create your new password",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: newPasswordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: "New Password",
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Confirm Password",
              ),
            ),
            if (widget.role == "student") ...[
              const SizedBox(height: 15),
              TextField(
                controller: newPinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: "New PIN",
                  hintText: "Enter 6-digit PIN",
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: confirmPinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: "Confirm PIN",
                  hintText: "Confirm 6-digit PIN",
                ),
              ),
            ],
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : changePassword,
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Save Password"),
              ),
            )
          ],
        ),
      ),
    );
  }
}
