import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/audit_trail_service.dart';

class FirstAuditScreen extends StatelessWidget {
  const FirstAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SecretEntryPage(),
              settings: const RouteSettings(
                arguments: {
                  'pin': '123456',
                  'password': 'must-not-be-recorded',
                },
              ),
            ),
          );
        },
        child: const Text('Open'),
      ),
    );
  }
}

class SecretEntryPage extends StatelessWidget {
  const SecretEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('OTP 654321'));
  }
}

void main() {
  test('canonical names are stable and exclude URL details', () {
    expect(canonicalAuditName('/StudentTransferScreen?token=secret'),
        'student_transfer_screen');
    expect(canonicalAuditName('Cashier QR Scanner'), 'cashier_qr_scanner');
    expect(canonicalAuditName('/'), 'root');
    expect(canonicalAuditName(''), isNull);
  });

  testWidgets(
    'observer records unnamed push and pop screen views without page content',
    (tester) async {
      final events = <Map<String, String>>[];
      final observer = AuditNavigatorObserver(
        recorder: (screen, navigation) {
          events.add({'screen': screen, 'navigation': navigation});
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: const FirstAuditScreen(),
        ),
      );
      await tester.pump();
      expect(events, [
        {'screen': 'first_audit_screen', 'navigation': 'push'},
      ]);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(events.last, {
        'screen': 'secret_entry_page',
        'navigation': 'push',
      });

      Navigator.of(tester.element(find.byType(SecretEntryPage))).pop();
      await tester.pumpAndSettle();
      expect(events.last, {
        'screen': 'first_audit_screen',
        'navigation': 'pop',
      });

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(SecretEntryPage))).pop();
      await tester.pumpAndSettle();
      expect(
        events
            .where(
              (event) =>
                  event['screen'] == 'first_audit_screen' &&
                  event['navigation'] == 'pop',
            )
            .length,
        2,
      );

      final serialized = events.toString();
      expect(serialized, isNot(contains('123456')));
      expect(serialized, isNot(contains('must-not-be-recorded')));
      expect(serialized, isNot(contains('654321')));
    },
  );

  testWidgets('observer records replace and ignores dialogs', (tester) async {
    final events = <String>[];
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AuditNavigatorObserver(
      recorder: (screen, navigation) {
        events.add('$navigation:$screen');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const FirstAuditScreen(),
      ),
    );
    await tester.pump();
    events.clear();

    navigatorKey.currentState!.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SecretEntryPage()),
    );
    await tester.pumpAndSettle();
    expect(events, ['replace:secret_entry_page']);

    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    expect(events, ['replace:secret_entry_page']);
  });
}
