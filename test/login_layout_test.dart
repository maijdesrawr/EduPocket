import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawr/login.dart';
import 'package:rawr/login_service.dart';

void main() {
  testWidgets('login stays valid on a TECNO-sized viewport with keyboard open',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1612);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(api: _FakeLoginApi())),
    );
    expect(tester.takeException(), isNull);

    // Model the transient near-full-height inset observed while Android opens
    // the keyboard. The usable layout height can briefly fall below the form's
    // decorative header offset.
    tester.view.viewInsets = const FakeViewPadding(bottom: 1500);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('login-heading')), findsOneWidget);
    expect(find.text('Tap into the future of payments'), findsOneWidget);
    expect(find.byKey(const Key('login-id-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
    expect(find.byKey(const Key('login-submit-button')), findsOneWidget);
  });

  testWidgets('login tolerates a zero-size startup frame', (tester) async {
    tester.view.physicalSize = Size.zero;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(api: _FakeLoginApi())),
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(720, 1532);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('login-heading')), findsOneWidget);
  });
}

class _FakeLoginApi implements LoginApi {
  @override
  Future<LoginAttempt> login({required String id, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<LoginOtpChallenge> requestOtp({
    required LoginOtpChallenge challenge,
    required LoginOtpMethod method,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LoginUser> verifyOtp({
    required String challengeToken,
    required String code,
  }) {
    throw UnimplementedError();
  }
}
