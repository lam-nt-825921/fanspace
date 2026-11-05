/// Unit tests for UserModel and SessionModel serialization and role getters.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/session_model.dart';
import 'package:frontend/models/user_model.dart';

void main() {
  group('Auth Models Unit Tests', () {
    test('UserModel parses JSON, system roles, and verification flags', () {
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
      expect(user.isEmailVerified, isTrue);
      expect(user.isAdmin, isTrue);
      expect(user.isModerator, isTrue);
      expect(user.hasPassword, isTrue);
      expect(user.isGoogleLinked, isTrue);
    });

    test('SessionModel parses active device session metadata', () {
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
      expect(session.isCurrent, isTrue);
    });
  });
}
