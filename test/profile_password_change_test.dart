import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/profile_password_change.dart';

void main() {
  testWidgets('profile password flow exposes secure fields and OTP methods', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfilePasswordChangePage(
          role: 'admin',
          userId: 'A3001',
          userName: 'Admin One',
        ),
      ),
    );

    expect(find.text('Create your new password'), findsOneWidget);
    expect(find.text('Current Password'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Google Authenticator'), findsOneWidget);
    expect(find.text('Email OTP'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);

    await tester.ensureVisible(find.text('Email OTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email OTP'));
    await tester.pump();
    expect(find.text('Email address'), findsNothing);
    expect(
      find.textContaining('verified email saved in your Profile'),
      findsOneWidget,
    );
  });
}
