/// Widget tests for AppTheme dark and light mode configurations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme dark and light theme smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Center(child: Text('Theme Smoke Test')),
        ),
      ),
    );

    expect(find.text('Theme Smoke Test'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
