/// End-to-end user journey scenario test for FandomWorkspaceScreen onboarding and channel navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/screens/workspace/fandom_workspace_screen.dart';

void main() {
  testWidgets(
    'Member completes onboarding from Welcome to Rules acknowledgment, then switches from read-only Announcement to interactive Chat channel',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fandom = FandomDetailModel(
        id: 'f-100',
        name: 'Sky Music Community',
        slug: 'sky-music',
        description: 'Cộng đồng giao lưu âm nhạc chính thức',
        category: 'Âm nhạc',
        admissionMode: 'OPEN',
        rulesTos: '1. Giữ thái độ văn minh lịch sự.\n2. Không quảng cáo trái phép.',
        memberCount: 1280,
        ownerId: 'u-owner',
        ownerName: 'Creator Sky',
        isOwner: false,
        isMember: true,
      );

      final channelsData = FandomChannelsDataModel(
        fandomId: 'f-100',
        slug: 'sky-music',
        myFandomPermissions: const {
          FandomPermission.viewChannel,
          FandomPermission.readMessages,
        },
        channels: [
          ChannelModel(
            id: 'ch-1',
            fandomId: 'f-100',
            name: 'thông-báo',
            type: 'TEXT',
            topic: 'Kênh thông báo chính thức từ Creator',
            position: 0,
            isAnnouncement: true,
            myPermissions: const {
              FandomPermission.viewChannel,
              FandomPermission.readMessages,
            },
          ),
          ChannelModel(
            id: 'ch-2',
            fandomId: 'f-100',
            name: 'chat-chung',
            type: 'TEXT',
            topic: 'Trò chuyện tự do',
            position: 1,
            isAnnouncement: false,
            myPermissions: const {
              FandomPermission.viewChannel,
              FandomPermission.readMessages,
              FandomPermission.sendMessages,
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FandomWorkspaceScreen(
            slug: 'sky-music',
            initialFandom: fandom,
            initialChannelsData: channelsData,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Default screen is Welcome / Overview ('Giới thiệu chung').
      expect(find.text('Chào mừng đến với Sky Music Community'), findsOneWidget);
      expect(find.text('Cộng đồng giao lưu âm nhạc chính thức'), findsOneWidget);

      // 2. Navigate to Rules screen via 'Xem Nội quy Cộng đồng' button and acknowledge rules.
      await tester.tap(find.text('Xem Nội quy Cộng đồng'));
      await tester.pumpAndSettle();

      expect(find.text('Nội quy & Quy định Cộng đồng'), findsOneWidget);
      expect(find.textContaining('1. Giữ thái độ văn minh lịch sự.'), findsOneWidget);

      await tester.tap(find.text('Tôi đã đọc và đồng ý tuân thủ nội quy'));
      await tester.pumpAndSettle();
      expect(find.text('Đã xác nhận tuân thủ nội quy'), findsOneWidget);

      // 3. Navigate to Announcement channel ('thông-báo') -> read-only notice for regular member.
      await tester.tap(find.text('thông-báo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Chỉ Chủ Fandom và Ban quản trị mới có quyền đăng thông báo'),
        findsOneWidget,
      );

      // 4. Navigate to Text channel ('chat-chung') -> composer is unlocked for member with SEND_MESSAGES.
      await tester.tap(find.text('chat-chung'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('channel_message_input')), findsOneWidget);
    },
  );
}
