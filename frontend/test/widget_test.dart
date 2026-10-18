import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/models/user_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/models/session_model.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/core/client_detector/client_detector.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/auth/widgets/password_strength_bar.dart';

void main() {
  group('FanSpace Frontend Unit & Widget Tests', () {
    test('UserModel serialization, roles, and flags', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'email': 'user@fanspace.vn',
        'username': 'fan_master',
        'display_name': 'Super Fan',
        'avatar_url': 'https://example.com/avatar.jpg',
        'bio': 'Passionate fandom supporter',
        'coin_balance': 0,
        'is_email_verified': true,
        'system_role': 'SYSTEM_ADMIN',
        'has_password': true,
        'is_google_linked': true,
        'created_at': '2026-10-18T12:00:00Z',
      };
      final user = UserModel.fromJson(json);
      expect(user.email, 'user@fanspace.vn');
      expect(user.username, 'fan_master');
      expect(user.displayName, 'Super Fan');
      expect(user.coinBalance, 0);
      expect(user.isEmailVerified, true);
      expect(user.isAdmin, true);
      expect(user.isModerator, true);
      expect(user.hasPassword, true);
      expect(user.isGoogleLinked, true);
    });

    test('SessionModel serialization and getters', () {
      final json = {
        'id': 'sess-123',
        'platform': 'MOBILE',
        'device_name': 'Pixel 8 Pro',
        'ip_address': '192.168.1.100',
        'is_current': true,
        'last_active_at': '2026-10-18T10:30:00Z',
        'created_at': '2026-10-18T08:00:00Z',
      };
      final session = SessionModel.fromJson(json);
      expect(session.id, 'sess-123');
      expect(session.platform, 'MOBILE');
      expect(session.deviceName, 'Pixel 8 Pro');
      expect(session.isCurrent, true);
    });

    test('ClientDetector returns valid platform', () async {
      final clientInfo = await ClientDetector.getClientInfo();
      expect(['WEB', 'MOBILE', 'DESKTOP'].contains(clientInfo.platform), true);
    });

    test('FandomDetailModel serialization and getters', () {
      final json = {
        'id': 'fandom-123',
        'slug': 'kpop-vietnam',
        'name': 'K-Pop Fan Community',
        'description': 'K-Pop fandom description',
        'category': 'Music',
        'admission_mode': 'OPEN',
        'member_count': 250,
        'owner_name': 'Leader',
        'owner_id': 'u-456',
        'is_owner': true,
        'is_member': true,
      };
      final fandom = FandomDetailModel.fromJson(json);
      expect(fandom.slug, 'kpop-vietnam');
      expect(fandom.name, 'K-Pop Fan Community');
      expect(fandom.memberCount, 250);
      expect(fandom.admissionMode, 'OPEN');
      expect(fandom.isOwner, true);
    });

    testWidgets('AppTheme dark and light theme smoke tests', (WidgetTester tester) async {
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

    testWidgets('PasswordStrengthBar renders strength accurately', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordStrengthBar(password: 'Weak1'),
          ),
        ),
      );

      // Score for 'Weak1': length < 8 (0), uppercase+lowercase (1), digit (1) -> score 2
      expect(find.byType(PasswordStrengthBar), findsOneWidget);
      expect(find.text('2/4'), findsOneWidget);
    });

    testWidgets('LoginScreen form rendering and validation test', (WidgetTester tester) async {
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

    testWidgets('RegisterScreen form rendering and validation test', (WidgetTester tester) async {
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
  });
}
