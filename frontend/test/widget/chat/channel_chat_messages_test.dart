/// Widget tests for real-time text channel message list and composer in FandomWorkspaceScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/models/message_model.dart';
import 'package:frontend/screens/workspace/fandom_workspace_screen.dart';

void main() {
  testWidgets(
    'FandomWorkspaceScreen renders channel message history and appends newly sent message',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fandom = FandomDetailModel(
        id: 'f-200',
        name: 'T1 Fanclub VN',
        slug: 't1-faker-vietnam',
        description: 'Cộng đồng người hâm mộ T1',
        category: 'Game & Esports',
        admissionMode: 'OPEN',
        memberCount: 500,
        ownerId: 'u-owner',
        ownerName: 'Faker Admin',
        isOwner: false,
        isMember: true,
      );

      final channelsData = FandomChannelsDataModel(
        fandomId: 'f-200',
        slug: 't1-faker-vietnam',
        myFandomPermissions: const {
          FandomPermission.viewChannel,
          FandomPermission.readMessages,
        },
        channels: [
          ChannelModel(
            id: 'ch-chat',
            fandomId: 'f-200',
            name: 'chat-chung',
            type: 'TEXT',
            topic: 'Kênh thảo luận chung',
            position: 0,
            isAnnouncement: false,
            myPermissions: const {
              FandomPermission.viewChannel,
              FandomPermission.readMessages,
              FandomPermission.sendMessages,
            },
          ),
        ],
      );

      final initialMessages = {
        'ch-chat': [
          MessageModel(
            id: 'm-1',
            channelId: 'ch-chat',
            fandomId: 'f-200',
            senderId: 'u-owner',
            sender: const MessageSenderModel(
              id: 'u-owner',
              username: 'faker_admin',
              displayName: 'Faker Admin',
              isOwner: true,
            ),
            content: 'Chào mừng anh em vào kênh chat chung!',
            createdAt: DateTime.utc(2026, 11, 5, 10, 0),
            updatedAt: DateTime.utc(2026, 11, 5, 10, 0),
          ),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FandomWorkspaceScreen(
            slug: 't1-faker-vietnam',
            initialFandom: fandom,
            initialChannelsData: channelsData,
            initialMessagesByChannel: initialMessages,
            onSendMessageOverride: (channelId, content, attachments) async {
              return MessageModel(
                id: 'm-2',
                channelId: channelId,
                fandomId: 'f-200',
                senderId: 'u-member',
                sender: const MessageSenderModel(
                  id: 'u-member',
                  username: 't1_fan',
                  displayName: 'T1 Fanboy',
                  isOwner: false,
                ),
                content: content,
                attachments: attachments,
                createdAt: DateTime.utc(2026, 11, 5, 10, 5),
                updatedAt: DateTime.utc(2026, 11, 5, 10, 5),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to #chat-chung channel.
      await tester.tap(find.text('chat-chung'));
      await tester.pumpAndSettle();

      // Verify existing message and Owner badge are displayed.
      expect(find.text('Chào mừng anh em vào kênh chat chung!'), findsOneWidget);
      expect(find.text('Faker Admin'), findsOneWidget);
      expect(find.text('Chủ Fandom'), findsOneWidget);

      // Type and send a new message.
      final inputFinder = find.byKey(const Key('channel_message_input'));
      await tester.enterText(inputFinder, 'T1 vô địch CKTG!');
      await tester.tap(find.byKey(const Key('channel_send_button')));
      await tester.pumpAndSettle();

      // Verify newly sent message is appended to the list.
      expect(find.text('T1 vô địch CKTG!'), findsOneWidget);
      expect(find.text('T1 Fanboy'), findsOneWidget);

      // Verify composer input has high-contrast white text color against dark surface fill.
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.style?.color, equals(Colors.white));
      expect(textField.decoration?.fillColor, equals(AppTheme.surfaceLight));
    },
  );
}
