/// Widget tests for FandomWorkspaceScreen navigation and mock permission UI states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/screens/workspace/fandom_workspace_screen.dart';

void main() {
  FandomDetailModel buildMockFandom({bool isOwner = false}) {
    return FandomDetailModel(
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
      isOwner: isOwner,
      isMember: true,
    );
  }

  FandomChannelsDataModel buildMockChannelsData({required bool canManage}) {
    final fandomPerms = <String>{
      FandomPermission.viewChannel,
      FandomPermission.readMessages,
      if (canManage) FandomPermission.manageChannels,
    };

    return FandomChannelsDataModel(
      fandomId: 'f-100',
      slug: 'sky-music',
      myFandomPermissions: fandomPerms,
      channels: [
        ChannelModel(
          id: 'ch-1',
          fandomId: 'f-100',
          name: 'thông-báo',
          type: 'TEXT',
          topic: 'Kênh thông báo chính thức từ Creator',
          position: 0,
          isAnnouncement: true,
          myPermissions: {
            FandomPermission.viewChannel,
            FandomPermission.readMessages,
            if (canManage) FandomPermission.sendAnnouncement,
            if (canManage) FandomPermission.sendMessages,
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
          myPermissions: {
            FandomPermission.viewChannel,
            FandomPermission.readMessages,
            FandomPermission.sendMessages,
          },
        ),
        ChannelModel(
          id: 'ch-3',
          fandomId: 'f-100',
          name: 'Phòng Thoại Chung',
          type: 'VOICE',
          topic: 'Giao lưu âm thanh',
          position: 2,
          isAnnouncement: false,
          voiceRoomType: 'OPEN_MIC',
          myPermissions: {
            FandomPermission.viewChannel,
            FandomPermission.voiceConnect,
            FandomPermission.voiceSpeak,
          },
        ),
      ],
    );
  }

  testWidgets(
    'FandomWorkspaceScreen opens Welcome screen first, navigates to Rules, then Channels',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FandomWorkspaceScreen(
            slug: 'sky-music',
            initialFandom: buildMockFandom(isOwner: false),
            initialChannelsData: buildMockChannelsData(canManage: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Default screen is Welcome / Overview ('Giới thiệu chung').
      expect(find.text('Chào mừng đến với Sky Music Community'), findsOneWidget);
      expect(find.text('Cộng đồng giao lưu âm nhạc chính thức'), findsOneWidget);

      // Regular member without MANAGE_CHANNELS does NOT see '+ Tạo kênh mới'.
      expect(find.text('Tạo kênh mới'), findsNothing);

      // 2. Navigate to Rules screen via 'Xem Nội quy Cộng đồng' button.
      await tester.tap(find.text('Xem Nội quy Cộng đồng'));
      await tester.pumpAndSettle();

      expect(find.text('Nội quy & Quy định Cộng đồng'), findsOneWidget);
      expect(find.textContaining('1. Giữ thái độ văn minh lịch sự.'), findsOneWidget);

      // Acknowledge the rules.
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

  testWidgets(
    'FandomWorkspaceScreen displays channel creation controls when MANAGE_CHANNELS is granted',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: FandomWorkspaceScreen(
            slug: 'sky-music',
            initialFandom: buildMockFandom(isOwner: true),
            initialChannelsData: buildMockChannelsData(canManage: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User with MANAGE_CHANNELS sees the 'Tạo kênh mới' button.
      expect(find.text('Tạo kênh mới'), findsOneWidget);
    },
  );
}
