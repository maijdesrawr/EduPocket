import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rawr/app_session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SessionHarness {
  _SessionHarness({
    required Duration inactivityTimeout,
    Duration validationInterval = const Duration(hours: 1),
    DateTime Function()? now,
  }) {
    service = AppSessionService(
      baseUrl: 'https://example.test/edupay',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path.endsWith('/logout_session.php')) {
          logoutReasons.add(request.bodyFields['reason'] ?? '');
        }
        return http.Response(jsonEncode({'status': 'success'}), 200);
      }),
      validationInterval: validationInterval,
      inactivityTimeout: inactivityTimeout,
      now: now,
    );
  }

  late final AppSessionService service;
  final List<String> requestedPaths = [];
  final List<String> logoutReasons = [];

  Future<void> activate({DateTime? now}) {
    final reference = now ?? DateTime.now();
    return service.activate(
      token: 'secure-session-token-for-inactivity-testing-0001',
      role: 'student',
      accountSource: 'students',
      userId: 'S1001',
      expiresAtEpochSeconds:
          reference.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('idle deadline logs out on the server and notifies exactly once',
      (tester) async {
    final harness = _SessionHarness(
      inactivityTimeout: const Duration(minutes: 5),
    );
    addTearDown(harness.service.close);
    var callbackCount = 0;
    String? callbackMessage;
    harness.service.setInvalidSessionCallback((message) {
      callbackCount++;
      callbackMessage = message;
    });

    await harness.activate();
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(harness.service.hasActiveSession, isTrue);
    expect(callbackCount, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(harness.service.hasActiveSession, isFalse);
    expect(callbackCount, 1);
    expect(callbackMessage, contains('5 minutes of inactivity'));
    expect(harness.logoutReasons, ['inactivity_timeout']);

    await tester.pump(const Duration(minutes: 10));
    expect(callbackCount, 1);
    expect(harness.logoutReasons, ['inactivity_timeout']);
  });

  testWidgets('pointer and keyboard input both restart the idle window',
      (tester) async {
    final harness = _SessionHarness(
      inactivityTimeout: const Duration(minutes: 5),
    );
    addTearDown(harness.service.close);
    var callbackCount = 0;
    harness.service.setInvalidSessionCallback((_) => callbackCount++);

    await tester.pumpWidget(
      MaterialApp(
        home: AppSessionActivityListener(
          service: harness.service,
          child: const Scaffold(
            body: ColoredBox(
              key: Key('activity-target'),
              color: Colors.transparent,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await harness.activate();

    await tester.pump(const Duration(minutes: 4));
    await tester.tap(find.byKey(const Key('activity-target')));
    await tester.pump(const Duration(minutes: 4));
    expect(callbackCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(callbackCount, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(callbackCount, 1);
  });

  testWidgets(
      'only real activity touches the backend and validation is throttled',
      (tester) async {
    var now = DateTime.utc(2026, 8, 22, 8);
    final harness = _SessionHarness(
      inactivityTimeout: const Duration(minutes: 5),
      validationInterval: const Duration(seconds: 30),
      now: () => now,
    );
    addTearDown(harness.service.close);
    await harness.activate(now: now);
    await tester.pump();
    harness.requestedPaths.clear();

    // Time passing on its own must not keep the backend session alive.
    await tester.pump(const Duration(minutes: 2));
    expect(
      harness.requestedPaths
          .where((path) => path.endsWith('validate_session.php')),
      isEmpty,
    );

    now = now.add(const Duration(seconds: 31));
    harness.service.registerUserActivity();
    harness.service.registerUserActivity();
    harness.service.registerUserActivity();
    await tester.pump();
    expect(
      harness.requestedPaths
          .where((path) => path.endsWith('validate_session.php')),
      hasLength(1),
    );

    now = now.add(const Duration(seconds: 29));
    harness.service.registerUserActivity();
    await tester.pump();
    expect(
      harness.requestedPaths
          .where((path) => path.endsWith('validate_session.php')),
      hasLength(1),
    );

    now = now.add(const Duration(seconds: 1));
    harness.service.registerUserActivity();
    await tester.pump();
    expect(
      harness.requestedPaths
          .where((path) => path.endsWith('validate_session.php')),
      hasLength(2),
    );
    await harness.service.close();
  });

  testWidgets('five minutes in the background expires immediately on resume',
      (tester) async {
    var now = DateTime.utc(2026, 8, 22, 8);
    final harness = _SessionHarness(
      inactivityTimeout: const Duration(minutes: 5),
      now: () => now,
    );
    addTearDown(harness.service.close);
    var callbackCount = 0;
    harness.service.setInvalidSessionCallback((_) => callbackCount++);
    await harness.activate(now: now);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(harness.service.hasActiveSession, isFalse);
    expect(callbackCount, 1);
    expect(harness.logoutReasons, ['inactivity_timeout']);
  });

  testWidgets('resuming before five minutes starts a fresh idle window',
      (tester) async {
    var now = DateTime.utc(2026, 8, 22, 8);
    final harness = _SessionHarness(
      inactivityTimeout: const Duration(minutes: 5),
      now: () => now,
    );
    addTearDown(harness.service.close);
    var callbackCount = 0;
    harness.service.setInvalidSessionCallback((_) => callbackCount++);
    await harness.activate(now: now);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(minutes: 4, seconds: 59));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(harness.service.hasActiveSession, isTrue);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(callbackCount, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(callbackCount, 1);
  });
}
