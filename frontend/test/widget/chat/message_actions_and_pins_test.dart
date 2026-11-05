/// Widget tests for message reply previews, edited/recalled badges, emoji reactions, and pinned messages dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/models/message_model.dart';
import 'package:frontend/screens/workspace/fandom_workspace_screen.dart';

FandomDetailModel _buildSampleFandom() {
  return FandomDetailModel(
    id: 'fandom-int-1',
    name: 'Cộng Đồng Âm Nhạc',
    slug: 'cong-dong-am-nhac',
    description: 'Không gian giao lưu âm nhạc',
    rulesTos: '1. Tôn trọng lẫn nhau',
    category: 'Âm nhạc',
    admissionMode: 'OPEN',
    isPublic: true,
    memberCount: 250,
    ownerId: 'owner-1',
    ownerName: 'Ca Sĩ A',
    isOwner: false,
    isMember: true,
  );
}

void main() {
  group('FandomWorkspaceScreen Message Interactions & Moderation UI', () {
    testWidgets(
        'renders reply quote preview, edited indicator, recalled placeholder, and reaction chips',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final channelsData = FandomChannelsDataModel(
        fandomId: 'fandom-int-1',
        slug: 'cong-dong-am-nhac',
        myFandomPermissions: {
          FandomPermission.viewChannel,
          FandomPermission.readMessages,
          FandomPermission.sendMessages,
          FandomPermission.moderateChat,
        },
        channels: [
          ChannelModel(
            id: 'ch-general',
            fandomId: 'fandom-int-1',
            name: 'chat-chung',
            type: 'TEXT',
            isAnnouncement: false,
            myPermissions: {
              FandomPermission.viewChannel,
              FandomPermission.readMessages,
              FandomPermission.sendMessages,
              FandomPermission.moderateChat,
            },
          ),
        ],
      );

      final now = DateTime.now().toUtc();
      final initialMessages = {
        'ch-general': [
          MessageModel(
            id: 'msg-1',
            channelId: 'ch-general',
            fandomId: 'fandom-int-1',
            senderId: 'owner-1',
            sender: const MessageSenderModel(
              id: 'owner-1',
              username: 'casi_a',
              displayName: 'Ca Sĩ A',
              isOwner: true,
            ),
            content: 'Tối nay 20h chúng ta có buổi giao lưu trực tuyến nhé!',
            isPinned: true,
            isEdited: true,
            reactions: const {
              '🔥': ['user-1', 'user-2'],
            },
            createdAt: now,
            updatedAt: now,
          ),
          MessageModel(
            id: 'msg-2',
            channelId: 'ch-general',
            fandomId: 'fandom-int-1',
            senderId: 'user-2',
            sender: const MessageSenderModel(
              id: 'user-2',
              username: 'fan_b',
              displayName: 'Bạn Fan B',
            ),
            content: 'Tuyệt vời quá, mình đã đặt lịch nhắc hẹn!',
            replyToId: 'msg-1',
            replyTo: const MessageReplyPreviewModel(
              id: 'msg-1',
              senderId: 'owner-1',
              senderDisplayName: 'Ca Sĩ A',
              content: 'Tối nay 20h chúng ta có buổi giao lưu trực tuyến nhé!',
              isRecalled: false,
            ),
            createdAt: now,
            updatedAt: now,
          ),
          MessageModel(
            id: 'msg-3',
            channelId: 'ch-general',
            fandomId: 'fandom-int-1',
            senderId: 'user-3',
            sender: const MessageSenderModel(
              id: 'user-3',
              username: 'fan_c',
              displayName: 'Bạn Fan C',
            ),
            content: 'Tin nhắn đã bị thu hồi.',
            isRecalled: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: FandomWorkspaceScreen(
            slug: 'cong-dong-am-nhac',
            initialFandom: _buildSampleFandom(),
            initialChannelsData: channelsData,
            initialMessagesByChannel: initialMessages,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to #chat-chung
      await tester.tap(find.text('chat-chung').first);
      await tester.pumpAndSettle();

      // Verify edited label and reaction count chip are shown
      expect(find.textContaining('(đã chỉnh sửa)'), findsOneWidget);
      expect(find.text('🔥 2'), findsOneWidget);

      // Verify reply quote preview is rendered
      expect(find.textContaining('Ca Sĩ A'), findsWidgets);

      // Verify recalled message placeholder is shown
      expect(find.text('Tin nhắn đã bị thu hồi.'), findsOneWidget);

      // Tap reply button on msg-1 and verify reply banner appears above composer
      await tester.tap(find.byKey(const Key('message_reply_msg-1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Đang trả lời'), findsOneWidget);

      // Open Pinned Messages dialog from channel header
      await tester.tap(find.byKey(const Key('channel_pinned_messages_button')));
      await tester.pumpAndSettle();

      expect(find.text('Tin nhắn đã ghim'), findsOneWidget);
    });
  });
}
