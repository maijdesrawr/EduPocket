import 'package:flutter/material.dart';

class RoundedCard extends StatelessWidget {
  final Widget child;
  const RoundedCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const QuickActionButton(
      {super.key, required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.red.shade700),
      label: Text(label, style: const TextStyle(color: Colors.black)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        elevation: 4,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final bool positive;
  const ActivityTile(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.amount,
      this.positive = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: Text(amount,
          style: TextStyle(
              color: positive ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold)),
    );
  }
}
