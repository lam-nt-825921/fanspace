import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/models/message_model.dart';
import 'package:frontend/screens/workspace/widgets/chat_message_item.dart';
import 'package:frontend/screens/workspace/widgets/fandom_emoji_sticker_picker.dart';

void main() {
  final sampleEmojis = <FandomEmojiModel>[
    FandomEmojiModel(
      id: 'emoji-1',
      fandomId: 'fandom-1',
      code: 'star_glow',
      shortcode: ':star_glow:',
      name: 'Star Glow',
      assetType: 'EMOJI',
      imageUrl: 'http://localhost:9000/fanspace-media/star.png',
      minTierLevel: 1,
      isUnlocked: true,
    ),
    FandomEmojiModel(
      id: 'emoji-2',
      fandomId: 'fandom-1',
      code: 'gold_crown',
      shortcode: ':gold_crown:',
      name: 'Gold Crown',
      assetType: 'EMOJI',
      imageUrl: 'http://localhost:9000/fanspace-media/crown.png',
      minTierLevel: 2,
      isUnlocked: false,
    ),
    FandomEmojiModel(
      id: 'sticker-1',
      fandomId: 'fandom-1',
      code: 'dance_cat',
      shortcode: ':dance_cat:',
      name: 'Dance Cat',
      assetType: 'STICKER',
      imageUrl: 'http://localhost:9000/fanspace-media/cat.png',
      minTierLevel: 2,
      isUnlocked: false,
    ),
  ];

  testWidgets(
      'FandomEmojiStickerPicker shows unlocked and locked emojis/stickers and prompts upgrade on locked tap',
      (WidgetTester tester) async {
    FandomEmojiModel? selectedEmoji;
    bool openedMembershipModal = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: FandomEmojiStickerPicker(
            items: sampleEmojis,
            userHighestTierLevel: 1,
            onSelectEmoji: (e) => selectedEmoji = e,
            onSelectSticker: (_) {},
            onOpenMembershipTiers: () => openedMembershipModal = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('tab_picker_emojis')), findsOneWidget);
    expect(find.byKey(const Key('tab_picker_stickers')), findsOneWidget);

    // Unlocked emoji does not have lock badge; locked emoji has lock badge
    expect(find.byKey(const Key('lock_badge_star_glow')), findsNothing);
    expect(find.byKey(const Key('lock_badge_gold_crown')), findsOneWidget);
    expect(find.text('🔒 Cấp 2'), findsOneWidget);

    // Tap locked emoji -> shows upgrade prompt banner
    await tester.tap(find.byKey(const Key('picker_item_gold_crown')));
    await tester.pump();

    expect(find.byKey(const Key('banner_locked_emoji_prompt')), findsOneWidget);
    expect(find.textContaining('Cấp 2'), findsWidgets);

    await tester.tap(find.text('Mua gói ngay'));
    await tester.pump();
    expect(openedMembershipModal, isTrue);

    // Tap unlocked emoji -> triggers onSelectEmoji
    await tester.tap(find.byKey(const Key('picker_item_star_glow')));
    await tester.pump();
    expect(selectedEmoji?.code, equals('star_glow'));
  });

  testWidgets(
      'ChatMessageItem renders inline custom emoji shortcode and STICKER attachment',
      (WidgetTester tester) async {
    final channel = ChannelModel(
      id: 'chan-1',
      fandomId: 'fandom-1',
      name: 'general',
      type: 'TEXT',
      isAnnouncement: false,
      isMembershipOnly: false,
      slowModeSeconds: 0,
      position: 0,
      myPermissions: {
        FandomPermission.viewChannel,
        FandomPermission.sendMessages,
      },
    );

    final message = MessageModel(
      id: 'msg-1',
      channelId: 'chan-1',
      fandomId: 'fandom-1',
      senderId: 'user-1',
      sender: const MessageSenderModel(
        id: 'user-1',
        username: 'alice',
        displayName: 'Alice VIP',
      ),
      content: 'Chào cả nhà :star_glow: tuyệt vời!',
      attachments: const [
        MessageAttachmentModel(
          url: 'http://localhost:9000/fanspace-media/cat.png',
          type: 'STICKER',
          filename: ':dance_cat:',
        ),
      ],
      reactions: const {},
      isPinned: false,
      isRecalled: false,
      createdAt: DateTime(2026, 11, 13, 12, 0),
      updatedAt: DateTime(2026, 11, 13, 12, 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatMessageItem(
              channel: channel,
              message: message,
              threadReplies: const [],
              isThreadExpanded: true,
              customEmojisByCode: {
                for (final e in sampleEmojis) e.code: e,
              },
              onToggleThread: () {},
              onReply: () {},
              onToggleReaction: (_) {},
              onEdit: () {},
              onRecall: () {},
              onTogglePin: () {},
              onReplyToThreadMessage: (_) {},
              onToggleThreadReaction: (_, __) {},
              onEditThreadMessage: (_) {},
              onRecallThreadMessage: (_) {},
              onPinThreadMessage: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('inline_custom_emoji_msg-1_star_glow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('message_sticker_msg-1')),
      findsOneWidget,
    );
  });
}
