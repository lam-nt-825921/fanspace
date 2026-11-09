/// Widget tests for Fandom Settings, Visibility Toggle, and Delete confirmation (FR-06 / UC-05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/providers/fandom_provider.dart';
import 'package:frontend/screens/home/create_fandom_screen.dart';
import 'package:frontend/screens/workspace/fandom_workspace_screen.dart';
import 'package:provider/provider.dart';

void main() {
  FandomDetailModel buildMockFandom({required bool isOwner, bool isPublic = true}) {
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
      isPublic: isPublic,
    );
  }

  FandomChannelsDataModel buildMockChannelsData() {
    return FandomChannelsDataModel(
      fandomId: 'f-100',
      slug: 'sky-music',
      myFandomPermissions: const {
        FandomPermission.viewChannel,
        FandomPermission.readMessages,
        FandomPermission.manageChannels,
      },
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

  Widget createTestWidget(Widget child, {FandomProvider? provider}) {
    return ChangeNotifierProvider<FandomProvider>(
      create: (_) => provider ?? FandomProvider(),
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: child,
      ),
    );
  }

  testWidgets('Settings icon button is shown only to the Owner in FandomWorkspaceScreen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 1. Owner view
    final ownerFandom = buildMockFandom(isOwner: true);
    await tester.pumpWidget(
      createTestWidget(
        FandomWorkspaceScreen(
          key: const Key('ws_owner'),
          slug: 'sky-music',
          initialFandom: ownerFandom,
          initialChannelsData: buildMockChannelsData(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('btn_fandom_settings')), findsOneWidget);

    // 2. Non-owner view
    final memberFandom = buildMockFandom(isOwner: false);
    await tester.pumpWidget(
      createTestWidget(
        FandomWorkspaceScreen(
          key: const Key('ws_member'),
          slug: 'sky-music',
          initialFandom: memberFandom,
          initialChannelsData: buildMockChannelsData(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('btn_fandom_settings')), findsNothing);
  });

  testWidgets('Tapping Settings opens dialog with visibility switch and danger zone delete button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ownerFandom = buildMockFandom(isOwner: true, isPublic: true);
    await tester.pumpWidget(
      createTestWidget(
        FandomWorkspaceScreen(
          key: const Key('ws_owner_dialog'),
          slug: 'sky-music',
          initialFandom: ownerFandom,
          initialChannelsData: buildMockChannelsData(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap settings button
    await tester.tap(find.byKey(const Key('btn_fandom_settings')));
    await tester.pumpAndSettle();

    expect(find.text('Cài đặt Fandom: Sky Music Community'), findsOneWidget);
    expect(find.text('Chế độ hiển thị không gian'), findsOneWidget);
    expect(find.text('Chế độ Công khai'), findsOneWidget);
    expect(find.text('Khu vực nguy hiểm'), findsOneWidget);
    expect(find.text('XÓA VĨNH VIỄN FANDOM NÀY'), findsOneWidget);

    // Tap delete button to open confirm dialog
    await tester.tap(find.text('XÓA VĨNH VIỄN FANDOM NÀY'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận xóa Fandom'), findsOneWidget);
    expect(find.text('Mật khẩu tài khoản của bạn'), findsOneWidget);
    expect(find.text('Xác nhận xóa'), findsOneWidget);
    expect(find.text('Hủy'), findsOneWidget);

    // Cancel closes dialog
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Xác nhận xóa Fandom'), findsNothing);
  });

  testWidgets('CreateFandomScreen displays quota indicator and public switch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createTestWidget(const CreateFandomScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Khởi tạo Fandom mới'), findsOneWidget);
    expect(find.textContaining('Hạn ngạch Fandom:'), findsOneWidget);
    expect(find.text('Công khai trên Danh mục Khám phá'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('KHỞI TẠO KHÔNG GIAN FANDOM'), findsOneWidget);
  });
}
