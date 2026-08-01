import 'package:flutter/material.dart';
import 'package:flutter_application_1/app/theme.dart';
import 'package:flutter_application_1/features/auth/screens/login_screen.dart';
import 'package:flutter_application_1/features/auth/screens/register_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login screen shows CalTrack branding and existing controls', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await _pumpAuthApp(tester, initialLocation: '/login');
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('CalTrack logo'), findsOneWidget);
    expect(find.text('Đăng Nhập'), findsOneWidget);
    expect(find.text('Tên đăng nhập'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('BỎ QUA ĐĂNG NHẬP (tạm thời)'), findsOneWidget);
    expect(find.text('Chưa có tài khoản? Đăng ký ngay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register screen shows CalTrack branding and existing controls', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await _pumpAuthApp(tester, initialLocation: '/register');
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('CalTrack logo'), findsOneWidget);
    expect(find.text('Đăng Ký'), findsOneWidget);
    expect(find.text('Tên đăng nhập'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Tên hiển thị'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('ĐĂNG KÝ'), findsOneWidget);
    expect(find.text('Đã có tài khoản? Đăng nhập ngay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpAuthApp(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
}
