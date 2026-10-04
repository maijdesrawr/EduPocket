import 'package:flutter/material.dart';

class AdminDashboard extends StatelessWidget {
  final String name;
  final String id;

  const AdminDashboard({super.key, required this.name, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Dashboard")),
      body: Center(child: Text("Welcome $name (ID: $id)")),
    );
  }
}
