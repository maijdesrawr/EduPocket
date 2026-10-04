import 'package:flutter/material.dart';

class PaymentFailureView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const PaymentFailureView(
      {super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFC62828);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
          child: Column(children: [
        const SizedBox(height: 24),
        Image.asset('assets/redlogo.png', height: 64),
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Payment Failed',
                style: TextStyle(
                    color: red, fontSize: 22, fontWeight: FontWeight.bold))),
        Expanded(
            child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
              color: red,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD6CCE7), width: 2)),
              child: SingleChildScrollView(
                  child: Column(children: [
                const SizedBox(height: 55),
                const Icon(Icons.cancel, size: 90, color: Color(0xFFFF4438)),
                const SizedBox(height: 22),
                const Text('Payment Failed',
                    style: TextStyle(
                        color: Color(0xFFFF4438),
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
              ])),
            )),
            const SizedBox(height: 20),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: red,
                    minimumSize: const Size.fromHeight(56)),
                onPressed: onRetry,
                child: const Text('Try Again',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          ]),
        )),
      ])),
    );
  }
}
