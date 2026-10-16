import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/user_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/core/theme/app_theme.dart';

void main() {
  group('Phase 1 Frontend Unit & Smoke Tests', () {
    test('UserModel serialization and getters', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'email': 'test@vnu.edu.vn',
        'username': 'vnutester',
        'display_name': 'VNU Student',
        'avatar_url': null,
        'is_active': true,
        'coin_balance': 500,
      };
      final user = UserModel.fromJson(json);
      expect(user.email, 'test@vnu.edu.vn');
      expect(user.username, 'vnutester');
      expect(user.displayName, 'VNU Student');
      expect(user.coinBalance, 500);
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

    testWidgets('AppTheme dark theme smoke test', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: Text('FanSpace Test'),
            ),
          ),
        ),
      );

      expect(find.text('FanSpace Test'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
