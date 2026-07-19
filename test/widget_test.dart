// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('Calorie tracker smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: CalorieTrackerApp()));

    expect(find.text('Đăng Nhập'), findsOneWidget);
    expect(find.text('Tên đăng nhập'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('ĐĂNG NHẬP'), findsOneWidget);
    expect(find.text('Chưa có tài khoản? Đăng ký ngay'), findsOneWidget);
  });
}
