import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/screens/workspace/dialogs/channel_form_dialog.dart';
import 'package:frontend/screens/workspace/management/dialogs/monetization_dialogs.dart';
import 'package:frontend/screens/workspace/management/fandom_roles_tab.dart';

void main() {
  Widget wrapApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );
  }

  testWidgets(
    'CreateMembershipTierDialog renders isolated MBS perks section and toggles perk checkboxes',
    (tester) async {
      await tester.pumpWidget(
        wrapApp(
          CreateMembershipTierDialog(
            fandomId: 'fandom-1',
            existingTiersCount: 0,
            onCreated: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('section_membership_perks_bitmask')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('dropdown_tier_level')), findsOneWidget);

      final emojiPerkKey = Key(
        'chk_membership_perk_${FandomMembershipPerkBit.exclusiveEmojis}',
      );
      final priorityPerkKey = Key(
        'chk_membership_perk_${FandomMembershipPerkBit.priorityChannelAccess}',
      );
      expect(find.byKey(emojiPerkKey), findsOneWidget);
      expect(find.byKey(priorityPerkKey), findsOneWidget);

      final priorityTileBefore = tester.widget<CheckboxListTile>(
        find.byKey(priorityPerkKey),
      );
      expect(priorityTileBefore.value, isTrue);

      await tester.ensureVisible(find.byKey(priorityPerkKey));
      await tester.tap(find.byKey(priorityPerkKey));
      await tester.pumpAndSettle();

      final priorityTileAfter = tester.widget<CheckboxListTile>(
        find.byKey(priorityPerkKey),
      );
      expect(priorityTileAfter.value, isFalse);
    },
  );

  testWidgets(
    'FandomRolesTab excludes isMembershipTier roles from regular Roles management',
    (tester) async {
      final fandom = FandomDetailModel.fromJson({
        'id': 'fandom-1',
        'name': 'Test Fandom',
        'slug': 'test-fandom',
        'description': 'desc',
        'category': 'MUSIC',
        'is_public': true,
        'admission_mode': 'OPEN',
        'member_count': 10,
        'owner_id': 'owner-1',
        'is_owner': true,
        'is_member': true,
      });

      final regularRole = RoleModel.fromJson({
        'id': 'role-mod',
        'fandom_id': 'fandom-1',
        'name': 'Điều phối viên',
        'color_hex': '#3498DB',
        'permissions_bitmask': 2,
        'membership_perks_bitmask': 0,
        'is_membership_tier': false,
        'member_count': 2,
      });

      final membershipTierRole = RoleModel.fromJson({
        'id': 'role-vip',
        'fandom_id': 'fandom-1',
        'name': 'VIP Gold Tier',
        'color_hex': '#F59E0B',
        'permissions_bitmask': 0,
        'membership_perks_bitmask': 15,
        'is_membership_tier': true,
        'member_count': 5,
      });

      await tester.pumpWidget(
        wrapApp(
          FandomRolesTab(
            fandom: fandom,
            roles: [regularRole, membershipTierRole],
            members: const [],
            isLoading: false,
            onRefreshRoles: () {},
            onRefreshAll: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Điều phối viên'), findsOneWidget);
      expect(find.text('VIP Gold Tier'), findsNothing);
    },
  );

  testWidgets(
    'ChannelFormDialog separates regular role selector from membership priority settings',
    (tester) async {
      final regularRole = RoleModel.fromJson({
        'id': 'role-staff',
        'fandom_id': 'fandom-1',
        'name': 'Biên tập viên',
        'color_hex': '#10B981',
        'permissions_bitmask': 1,
        'is_membership_tier': false,
      });
      final tierRole = RoleModel.fromJson({
        'id': 'role-tier-1',
        'fandom_id': 'fandom-1',
        'name': 'Gói Hạng 1 (Should Not Appear)',
        'color_hex': '#F59E0B',
        'permissions_bitmask': 0,
        'is_membership_tier': true,
      });
      final tiers = [
        MembershipTierModel.fromJson({
          'id': 'tier-1',
          'role_id': 'role-tier-1',
          'name': 'Bạc',
          'price_vnd': 49000,
          'duration_days': 30,
          'tier_level': 1,
          'membership_perks_bitmask': 15,
          'is_active': true,
        }),
        MembershipTierModel.fromJson({
          'id': 'tier-2',
          'role_id': 'role-tier-2',
          'name': 'Vàng',
          'price_vnd': 99000,
          'duration_days': 30,
          'tier_level': 2,
          'membership_perks_bitmask': 15,
          'is_active': true,
        }),
      ];

      final existingChannel = ChannelModel.fromJson({
        'id': 'ch-1',
        'fandom_id': 'fandom-1',
        'name': 'khu-vuc-vip',
        'type': 'TEXT',
        'is_membership_only': false,
        'min_membership_tier_level': 0,
        'membership_bypass_slowmode': false,
        'slow_mode_seconds': 15,
      });

      await tester.pumpWidget(
        wrapApp(
          ChannelFormDialog(
            fandomSlug: 'test-fandom',
            existing: existingChannel,
            availableRoles: [regularRole, tierRole],
            availableTiers: tiers,
            onSaved: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Regular role dropdown is visible and excludes membership tier roles.
      final roleDropdown = find.byKey(
        const Key('dropdown_channel_required_role'),
      );
      expect(roleDropdown, findsOneWidget);

      await tester.ensureVisible(roleDropdown);
      await tester.tap(roleDropdown);
      await tester.pumpAndSettle();

      expect(find.text('Biên tập viên'), findsWidgets);
      expect(find.text('Gói Hạng 1 (Should Not Appear)'), findsNothing);

      // Dismiss dropdown menu by selecting "Biên tập viên".
      await tester.tap(find.text('Biên tập viên').last);
      await tester.pumpAndSettle();

      // Membership priority card contains VIP switch and slowmode bypass switch.
      expect(
        find.byKey(const Key('card_channel_membership_priority')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('switch_channel_membership_only')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('switch_channel_membership_bypass_slowmode')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('dropdown_channel_min_tier')),
        findsNothing,
      );

      // Turning on VIP reveals min_membership_tier_level dropdown with tier labels.
      final vipSwitch = find.byKey(const Key('switch_channel_membership_only'));
      await tester.ensureVisible(vipSwitch);
      await tester.tap(vipSwitch);
      await tester.pumpAndSettle();

      final minTierDropdown = find.byKey(
        const Key('dropdown_channel_min_tier'),
      );
      expect(minTierDropdown, findsOneWidget);

      await tester.ensureVisible(minTierDropdown);
      await tester.tap(minTierDropdown);
      await tester.pumpAndSettle();

      expect(find.text('Từ Hạng 2 trở lên (Vàng)'), findsWidgets);
    },
  );
}
