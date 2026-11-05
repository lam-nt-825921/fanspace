/// Widget tests for FandomWorkspaceScreen channel management permission controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/screens/workspace/fandom_workspace_screen.dart';

void main() {
  FandomDetailModel buildMockFandom({required bool isOwner}) {
    return FandomDetailModel(
      id: 'f-100',
      name: 'Sky Music Community',
      slug: 'sky-music',
      description: 'Cộng đồng giao lưu âm nhạc chính thức',
      category: 'Âm nhạc',
      admissionMode: 'OPEN',
      rulesTos: '1. Giữ thái độ văn minh lịch sự.',
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
          name: 'chat-chung',
          type: 'TEXT',
          topic: 'Trò chuyện tự do',
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
  }

  testWidgets(
    'FandomWorkspaceScreen hides channel creation button when MANAGE_CHANNELS is absent',
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

      expect(find.text('Tạo kênh mới'), findsNothing);
    },
  );

  testWidgets(
    'FandomWorkspaceScreen displays channel creation button when MANAGE_CHANNELS is granted',
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

      expect(find.text('Tạo kênh mới'), findsOneWidget);
    },
  );
}
