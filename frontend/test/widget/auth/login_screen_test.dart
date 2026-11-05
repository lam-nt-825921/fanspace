/// Widget tests for LoginScreen form rendering and empty-field validation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('LoginScreen renders fields and validates empty submission', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    expect(find.text('Đăng nhập FanSpace'), findsOneWidget);
    expect(find.text('Email hoặc Tên đăng nhập'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);

    final submitFinder = find.widgetWithText(ElevatedButton, 'Đăng nhập');
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập Email hoặc Username.'), findsOneWidget);
  });
}
