/// Widget tests for RegisterScreen form rendering and PasswordStrengthBar indicator.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/auth/widgets/password_strength_bar.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('PasswordStrengthBar computes and renders strength score accurately', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PasswordStrengthBar(password: 'Weak1'),
        ),
      ),
    );

    expect(find.byType(PasswordStrengthBar), findsOneWidget);
    expect(find.text('2/4'), findsOneWidget);
  });

  testWidgets('RegisterScreen renders fields and validates empty submission', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(
          home: RegisterScreen(),
        ),
      ),
    );

    expect(find.text('Tạo tài khoản FanSpace'), findsOneWidget);
    expect(find.text('Địa chỉ Email'), findsOneWidget);
    expect(find.text('Tên tài khoản (Username)'), findsOneWidget);
    expect(find.text('Tên hiển thị (Display Name)'), findsOneWidget);

    final submitFinder = find.widgetWithText(ElevatedButton, 'Đăng ký tài khoản');
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập địa chỉ email.'), findsOneWidget);
  });
}
