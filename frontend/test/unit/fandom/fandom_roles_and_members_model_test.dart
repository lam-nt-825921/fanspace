import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/fandom_model.dart';

void main() {
  group('RoleModel Unit Tests', () {
    test('parses JSON correctly into RoleModel', () {
      final json = {
        'id': 'role-123',
        'fandom_id': 'fandom-456',
        'name': 'Moderator',
        'color_hex': '#42A5F5',
        'priority': 75,
        'permissions_bitmask': FandomPermissionBit.moderateChat | FandomPermissionBit.muteMembers,
        'is_preset_mod': true,
        'is_membership_tier': false,
        'created_at': '2026-11-06T10:00:00Z',
      };

      final role = RoleModel.fromJson(json);
      expect(role.id, 'role-123');
      expect(role.fandomId, 'fandom-456');
      expect(role.name, 'Moderator');
      expect(role.colorHex, '#42A5F5');
      expect(role.priority, 75);
      expect(role.isPresetMod, isTrue);
      expect(role.hasPermission(FandomPermissionBit.moderateChat), isTrue);
      expect(role.hasPermission(FandomPermissionBit.muteMembers), isTrue);
      expect(role.hasPermission(FandomPermissionBit.banMembers), isFalse);
    });

    test('administrator bitmask grants any permission check', () {
      final role = RoleModel(
        id: 'admin-role',
        fandomId: 'f-1',
        name: 'Admin',
        permissionsBitmask: FandomPermissionBit.administrator,
      );

      expect(role.hasPermission(FandomPermissionBit.banMembers), isTrue);
      expect(role.hasPermission(FandomPermissionBit.manageChannels), isTrue);
      expect(role.hasPermission(FandomPermissionBit.manageRoles), isTrue);
    });
  });

  group('FandomMemberModel Unit Tests', () {
    test('parses member with active roles and computes maxPriority', () {
      final json = {
        'user_id': 'user-1',
        'username': 'member_one',
        'display_name': 'Member One',
        'avatar_url': 'https://example.com/a.png',
        'status': 'ACTIVE',
        'joined_at': '2026-11-01T12:00:00Z',
        'roles': [
          {
            'id': 'r1',
            'fandom_id': 'f1',
            'name': 'VIP',
            'priority': 30,
            'permissions_bitmask': 3,
          },
          {
            'id': 'r2',
            'fandom_id': 'f1',
            'name': 'Mod',
            'priority': 70,
            'permissions_bitmask': 512,
          },
        ],
      };

      final member = FandomMemberModel.fromJson(json);
      expect(member.userId, 'user-1');
      expect(member.username, 'member_one');
      expect(member.roles.length, 2);
      expect(member.maxPriority, 70);
      expect(member.isMuted, isFalse);
      expect(member.isBanned, isFalse);
    });

    test('correctly evaluates isMuted and isBanned status', () {
      final mutedMember = FandomMemberModel(
        userId: 'u2',
        username: 'muted_user',
        displayName: 'Muted User',
        status: 'MUTED',
        mutedUntil: DateTime.now().add(const Duration(hours: 5)),
      );
      expect(mutedMember.isMuted, isTrue);

      final expiredMuteMember = FandomMemberModel(
        userId: 'u3',
        username: 'unmuted_user',
        displayName: 'Unmuted User',
        status: 'MUTED',
        mutedUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(expiredMuteMember.isMuted, isFalse);

      final bannedMember = FandomMemberModel(
        userId: 'u4',
        username: 'banned_user',
        displayName: 'Banned User',
        status: 'BANNED',
      );
      expect(bannedMember.isBanned, isTrue);
    });
  });

  group('FandomInviteModel Unit Tests', () {
    test('evaluates expiration and usage exhaustion', () {
      final activeInvite = FandomInviteModel(
        code: 'ACTIVE88',
        fandomId: 'f1',
        fandomName: 'Fandom 1',
        fandomSlug: 'fandom-1',
        maxUses: 10,
        usesCount: 3,
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      expect(activeInvite.isExpired, isFalse);
      expect(activeInvite.isExhausted, isFalse);

      final exhaustedInvite = FandomInviteModel(
        code: 'USEDUP01',
        fandomId: 'f1',
        fandomName: 'Fandom 1',
        fandomSlug: 'fandom-1',
        maxUses: 5,
        usesCount: 5,
      );
      expect(exhaustedInvite.isExhausted, isTrue);

      final expiredInvite = FandomInviteModel(
        code: 'EXPIRED9',
        fandomId: 'f1',
        fandomName: 'Fandom 1',
        fandomSlug: 'fandom-1',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(expiredInvite.isExpired, isTrue);
    });
  });
}
