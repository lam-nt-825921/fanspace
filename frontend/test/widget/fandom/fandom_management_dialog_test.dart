import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/providers/fandom_provider.dart';
import 'package:frontend/screens/workspace/fandom_management_dialog.dart';

class MockFandomProvider extends ChangeNotifier implements FandomProvider {
  final List<RoleModel> mockRoles;
  final List<FandomMemberModel> mockMembers;
  final List<FandomInviteModel> mockInvites;

  MockFandomProvider({
    this.mockRoles = const [],
    this.mockMembers = const [],
    this.mockInvites = const [],
  });

  @override
  Future<List<RoleModel>> fetchRoles(String identifier) async => mockRoles;

  @override
  Future<List<FandomMemberModel>> fetchMembers(
    String identifier, {
    String? search,
    String statusFilter = 'ACTIVE',
    int limit = 50,
    int offset = 0,
  }) async => mockMembers;

  @override
  Future<List<FandomInviteModel>> fetchInvites(String identifier) async => mockInvites;

  @override
  Future<Map<String, dynamic>> updateFandomVisibility(String identifier, bool isPublic) async => {
        'success': true,
        'is_public': isPublic,
      };

  @override
  Future<Map<String, dynamic>> createRole(
    String identifier, {
    required String name,
    String colorHex = '#808080',
    int priority = 0,
    int permissionsBitmask = 0,
  }) async => {
        'success': true,
        'role': RoleModel(
          id: 'new-role-1',
          fandomId: identifier,
          name: name,
          colorHex: colorHex,
          priority: priority,
          permissionsBitmask: permissionsBitmask,
        ),
      };

  @override
  Future<Map<String, dynamic>> createInvite(
    String identifier, {
    int? maxUses,
    int? expiresInHours,
  }) async => {
        'success': true,
        'invite': FandomInviteModel(
          code: 'NEWCODE8',
          fandomId: identifier,
          fandomName: 'Fandom Test',
          fandomSlug: 'fandom-test',
        ),
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final testFandom = FandomDetailModel(
    id: 'fandom-uuid-1',
    name: 'Sơn Tùng M-TP Fans',
    slug: 'son-tung-mtp',
    category: 'Âm nhạc',
    admissionMode: 'OPEN',
    isPublic: true,
    memberCount: 150,
    ownerId: 'owner-uuid-1',
    ownerName: 'Admin',
    isOwner: true,
    isMember: true,
  );

  final testMember = FandomMemberModel(
    userId: 'user-2',
    username: 'skymember',
    displayName: 'Sky Fan',
    status: 'ACTIVE',
    roles: [
      RoleModel(
        id: 'role-vip',
        fandomId: 'fandom-uuid-1',
        name: 'VIP Sky',
        colorHex: '#FF4081',
        priority: 50,
      ),
    ],
  );

  final testRole = RoleModel(
    id: 'role-mod',
    fandomId: 'fandom-uuid-1',
    name: 'Chat Moderator',
    colorHex: '#42A5F5',
    priority: 80,
    isPresetMod: true,
  );

  final testInvite = FandomInviteModel(
    code: 'SKY2026X',
    fandomId: 'fandom-uuid-1',
    fandomName: 'Sơn Tùng M-TP Fans',
    fandomSlug: 'son-tung-mtp',
    maxUses: 50,
    usesCount: 12,
  );

  Widget createWidgetUnderTest(MockFandomProvider provider) {
    return ChangeNotifierProvider<FandomProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: FandomManagementDialog(fandom: testFandom),
        ),
      ),
    );
  }

  testWidgets('FandomManagementDialog renders all 4 tabs and switches between them', (tester) async {
    final provider = MockFandomProvider(
      mockMembers: [testMember],
      mockRoles: [testRole],
      mockInvites: [testInvite],
    );

    await tester.pumpWidget(createWidgetUnderTest(provider));
    await tester.pumpAndSettle();

    // Verify title and tabs
    expect(find.text('Cài đặt Fandom: Sơn Tùng M-TP Fans'), findsOneWidget);
    expect(find.byKey(const Key('tab_settings')), findsOneWidget);
    expect(find.byKey(const Key('tab_members')), findsOneWidget);
    expect(find.byKey(const Key('tab_roles')), findsOneWidget);
    expect(find.byKey(const Key('tab_invites')), findsOneWidget);

    // Initial Tab: Settings
    expect(find.byKey(const Key('switch_fandom_visibility')), findsOneWidget);
    expect(find.byKey(const Key('btn_trigger_delete_fandom')), findsOneWidget);

    // Switch to Members Tab
    await tester.tap(find.byKey(const Key('tab_members')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('input_search_members')), findsOneWidget);
    expect(find.text('Sky Fan'), findsOneWidget);
    expect(find.text('VIP Sky'), findsOneWidget);
    expect(find.byKey(const Key('btn_kick_user-2')), findsOneWidget);
    expect(find.byKey(const Key('btn_ban_user-2')), findsOneWidget);

    // Switch to Roles Tab
    await tester.tap(find.byKey(const Key('tab_roles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('btn_create_role')), findsOneWidget);
    expect(find.text('Chat Moderator'), findsOneWidget);
    expect(find.text('PRESET MOD'), findsOneWidget);

    // Switch to Invites Tab
    await tester.tap(find.byKey(const Key('tab_invites')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('btn_create_invite')), findsOneWidget);
    expect(find.text('SKY2026X'), findsOneWidget);
    expect(find.text('Đã dùng: 12 / 50'), findsOneWidget);
  });

  testWidgets('Opens create role dialog and create invite dialog', (tester) async {
    final provider = MockFandomProvider();
    await tester.pumpWidget(createWidgetUnderTest(provider));
    await tester.pumpAndSettle();

    // Go to Roles tab and tap create role
    await tester.tap(find.byKey(const Key('tab_roles')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_create_role')));
    await tester.pumpAndSettle();

    expect(find.text('Tạo vai trò mới'), findsOneWidget);
    expect(find.byKey(const Key('input_role_name')), findsOneWidget);
    expect(find.byKey(const Key('btn_save_role')), findsOneWidget);

    // Cancel role dialog
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    // Go to Invites tab and tap create invite
    await tester.tap(find.byKey(const Key('tab_invites')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_create_invite')));
    await tester.pumpAndSettle();

    expect(find.text('Tạo liên kết / Mã mời mới'), findsOneWidget);
    expect(find.byKey(const Key('btn_confirm_create_invite')), findsOneWidget);
  });
}
