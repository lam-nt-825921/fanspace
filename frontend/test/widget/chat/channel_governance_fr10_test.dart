/// Widget tests for FR-10 Channel Governance:
/// - ChannelFormDialog multi-role chips, granular role permissions, max_members, slow_mode_seconds, and membership permissions
/// - ChannelHeaderBar and WorkspaceSidebar display of max_members, slow_mode, VIP, and role badges
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/screens/workspace/dialogs/channel_form_dialog.dart';
import 'package:frontend/screens/workspace/widgets/channel_header_bar.dart';

void main() {
  Widget wrapApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );
  }

  testWidgets(
    'ChannelFormDialog renders FR-10 multi-role selection, granular role permissions, max_members, slow-mode presets, and membership permissions',
    (tester) async {
      final roleA = RoleModel.fromJson({
        'id': 'role-a',
        'fandom_id': 'f-1',
        'name': 'Biên tập viên',
        'color_hex': '#10B981',
        'permissions_bitmask': 15,
        'is_membership_tier': false,
      });
      final roleB = RoleModel.fromJson({
        'id': 'role-b',
        'fandom_id': 'f-1',
        'name': 'Điều phối viên',
        'color_hex': '#3B82F6',
        'permissions_bitmask': 15,
        'is_membership_tier': false,
      });

      final existingChannel = ChannelModel.fromJson({
        'id': 'ch-fr10',
        'fandom_id': 'f-1',
        'name': 'phong-thao-luan',
        'type': 'TEXT',
        'max_members': 50,
        'slow_mode_seconds': 15,
        'allowed_role_ids': ['role-a'],
        'role_permissions_bitmask': 32783,
        'is_membership_only': true,
        'min_membership_tier_level': 1,
        'membership_bypass_slowmode': true,
        'membership_permissions_bitmask': 32783,
      });

      await tester.pumpWidget(
        wrapApp(
          ChannelFormDialog(
            fandomSlug: 'test-fandom',
            existing: existingChannel,
            availableRoles: [roleA, roleB],
            availableTiers: const [],
            onSaved: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Max members input is present and initialized to 50
      final maxMembersField = find.byKey(const Key('input_channel_max_members'));
      expect(maxMembersField, findsOneWidget);
      final maxMembersWidget = tester.widget<TextField>(maxMembersField);
      expect(maxMembersWidget.controller?.text, '50');

      // 2. Multi-role FilterChips are rendered and can select multiple roles
      final chipRoleA = find.byKey(const Key('chip_channel_role_role-a'));
      final chipRoleB = find.byKey(const Key('chip_channel_role_role-b'));
      expect(chipRoleA, findsOneWidget);
      expect(chipRoleB, findsOneWidget);

      await tester.ensureVisible(chipRoleB);
      await tester.tap(chipRoleB);
      await tester.pumpAndSettle();

      final roleBWidget = tester.widget<FilterChip>(chipRoleB);
      expect(roleBWidget.selected, isTrue);

      // 3. Granular Role channel permission checkboxes are rendered when roles are selected
      expect(
        find.byKey(const Key('section_channel_role_permissions')),
        findsOneWidget,
      );

      // 4. Granular Membership channel permission checkboxes are rendered
      expect(
        find.byKey(const Key('section_channel_membership_permissions')),
        findsOneWidget,
      );

      // 5. Slow-mode preset chips work
      final preset30s = find.byKey(const Key('chip_slowmode_preset_30'));
      expect(preset30s, findsOneWidget);
      await tester.ensureVisible(preset30s);
      await tester.tap(preset30s);
      await tester.pumpAndSettle();

      final slowModeField = find.byKey(const Key('input_channel_slow_mode'));
      expect(tester.widget<TextField>(slowModeField).controller?.text, '30');
    },
  );

  testWidgets(
    'ChannelHeaderBar displays max_members capacity badge, slow-mode badge, and VIP badge',
    (tester) async {
      final channel = ChannelModel.fromJson({
        'id': 'ch-header-1',
        'fandom_id': 'f-1',
        'name': 'khu-vuc-vip',
        'type': 'TEXT',
        'topic': 'Kênh thảo luận giới hạn 50 người',
        'max_members': 50,
        'slow_mode_seconds': 30,
        'is_membership_only': true,
        'min_membership_tier_level': 2,
        'allowed_role_ids': ['role-1', 'role-2'],
      });

      await tester.pumpWidget(
        wrapApp(
          ChannelHeaderBar(
            channel: channel,
            canManage: true,
            onOpenPinnedMessages: () {},
            onEditChannel: () {},
            onDeleteChannel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('khu-vuc-vip'), findsOneWidget);
      expect(find.textContaining('Tối đa 50 người'), findsOneWidget);
      expect(find.text('Chế độ chậm: 30s'), findsOneWidget);
      expect(find.textContaining('VIP'), findsOneWidget);
    },
  );
}
