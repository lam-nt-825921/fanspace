import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/providers/fandom_provider.dart';
import 'package:frontend/screens/workspace/fandom_monetization_tab.dart';
import 'package:provider/provider.dart';

void main() {
  final sampleFandom = FandomDetailModel(
    id: 'fandom-1',
    name: 'VNU Gaming',
    slug: 'vnu-gaming',
    category: 'Gaming',
    admissionMode: 'OPEN',
    memberCount: 42,
    ownerId: 'owner-1',
    ownerName: 'Chủ Fandom',
    isOwner: true,
    isMember: true,
  );

  final sampleMemberships = FandomMembershipsDataModel(
    fandomId: 'fandom-1',
    bankConfigured: true,
    tiers: [
      MembershipTierModel(
        id: 'tier-1',
        fandomId: 'fandom-1',
        name: 'Fan Bạc',
        tierLevel: 1,
        priceFiatVnd: 20000,
      ),
      MembershipTierModel(
        id: 'tier-3',
        fandomId: 'fandom-1',
        name: 'Fan Kim Cương',
        tierLevel: 3,
        priceFiatVnd: 100000,
      ),
    ],
  );

  final sampleEmojis = <FandomEmojiModel>[
    FandomEmojiModel(
      id: 'emj-1',
      fandomId: 'fandom-1',
      code: 'heart_fire',
      shortcode: ':heart_fire:',
      name: 'Trái tim rực lửa',
      assetType: 'EMOJI',
      imageUrl: 'http://localhost:9000/fanspace-media/heart.png',
      minTierLevel: 1,
      minTierName: 'Fan Bạc',
      isUnlocked: true,
    ),
    FandomEmojiModel(
      id: 'stk-1',
      fandomId: 'fandom-1',
      code: 'super_cheer',
      shortcode: ':super_cheer:',
      name: 'Cổ vũ siêu cấp',
      assetType: 'STICKER',
      imageUrl: 'http://localhost:9000/fanspace-media/cheer.webp',
      minTierLevel: 3,
      minTierName: 'Fan Kim Cương',
      isUnlocked: true,
    ),
  ];

  testWidgets(
      'FandomMonetizationTab displays Emoji & Sticker setup section and opens UpsertFandomEmojiDialog',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FandomProvider>(
        create: (_) => FandomProvider(),
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: FandomMonetizationTab(
              fandom: sampleFandom,
              initialMembershipsData: sampleMemberships,
              initialEmojis: sampleEmojis,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('section_emoji_sticker_setup')), findsOneWidget);
    expect(find.byKey(const Key('setup_emoji_row_heart_fire')), findsOneWidget);
    expect(find.byKey(const Key('setup_emoji_row_super_cheer')), findsOneWidget);
    expect(find.text('Mở khóa từ: Cấp 1 (Fan Bạc)'), findsOneWidget);
    expect(find.text('Mở khóa từ: Cấp 3 (Fan Kim Cương)'), findsOneWidget);

    // Open Add Emoji/Sticker dialog
    await tester.ensureVisible(find.byKey(const Key('btn_add_fandom_emoji')));
    await tester.tap(find.byKey(const Key('btn_add_fandom_emoji')));
    await tester.pumpAndSettle();

    expect(find.text('Thêm Emoji / Sticker Độc quyền'), findsOneWidget);
    expect(find.byKey(const Key('chip_asset_type_emoji')), findsOneWidget);
    expect(find.byKey(const Key('chip_asset_type_sticker')), findsOneWidget);
    expect(find.byKey(const Key('input_emoji_code')), findsOneWidget);
    expect(find.byKey(const Key('dropdown_emoji_min_tier')), findsOneWidget);

    // Switch to STICKER chip
    await tester.tap(find.byKey(const Key('chip_asset_type_sticker')));
    await tester.pump();
  });
}
