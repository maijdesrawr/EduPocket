import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/admin_profile.dart';
import 'package:rawr/canteen_profile_screen.dart';
import 'package:rawr/cashier_profile.dart';
import 'package:rawr/parent_profile.dart';
import 'package:rawr/student_profile.dart';

void main() {
  testWidgets('student profile fits a phone viewport', (tester) async {
    await _verifyProfileLayout(
      tester,
      profile: const StudentProfile(
        id: '20231102208',
        name: 'Student Example',
      ),
      idLabel: 'Student Number:',
    );
  });

  testWidgets('parent profile fits a phone viewport', (tester) async {
    await _verifyProfileLayout(
      tester,
      profile: const ParentProfilePage(
        userId: 'P1001',
        userName: 'Parent Example',
      ),
      idLabel: 'Parent ID:',
    );
  });

  testWidgets('admin profile fits a phone viewport', (tester) async {
    await _verifyProfileLayout(
      tester,
      profile: const AdminProfilePage(
        adminId: 'A3001',
        adminName: 'Admin Example',
      ),
      idLabel: 'Admin ID:',
    );
  });

  testWidgets('canteen profile fits above its dashboard navigation',
      (tester) async {
    await _verifyProfileLayout(
      tester,
      profile: const CanteenProfileScreen(
        canteenId: 'C4001',
        canteenName: 'Canteen Example',
      ),
      idLabel: 'Canteen ID:',
      embeddedInDashboard: true,
    );
  });

  testWidgets('cashier profile fits above its dashboard navigation',
      (tester) async {
    await _verifyProfileLayout(
      tester,
      profile: const CashierProfileScreen(
        cashierId: 'K5001',
        cashierName: 'Cashier Example',
      ),
      idLabel: 'Cashier ID:',
      embeddedInDashboard: true,
    );
  });
}

Future<void> _verifyProfileLayout(
  WidgetTester tester, {
  required Widget profile,
  required String idLabel,
  bool embeddedInDashboard = false,
}) async {
  tester.view.physicalSize = const Size(720, 1612);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final home = embeddedInDashboard
      ? Scaffold(
          extendBody: true,
          body: profile,
          bottomNavigationBar: const SizedBox(height: 92),
        )
      : profile;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 5));

  expect(find.text('Account Information'), findsOneWidget);
  expect(find.text(idLabel), findsOneWidget);
  expect(find.text('Email:'), findsOneWidget);
  expect(find.text('Change'), findsOneWidget);
  expect(find.text('Google Authenticator'), findsOneWidget);
  expect(find.text('Change 6-digit PIN'),
      profile is ParentProfilePage || profile is AdminProfilePage
          ? findsNothing : findsOneWidget);
  expect(find.text('Change Password'), findsOneWidget);
  expect(find.text('Log Out'), findsOneWidget);
  expect(tester.takeException(), isNull);
}
