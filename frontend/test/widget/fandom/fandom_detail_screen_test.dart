/// Widget test verifying the Back button on FandomDetailScreen navigates back to the home directory.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/fandom_provider.dart';
import 'package:frontend/screens/home/fandom_detail_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'FandomDetailScreen renders back button and navigates back to home directory when tapped',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fandom = FandomDetailModel(
        id: 'f-1',
        name: 'Sky Tour - Sơn Tùng M-TP Official',
        slug: 'sontung-mtp-sky',
        description: 'Đại gia đình Sky chính thức',
        category: 'Âm nhạc',
        admissionMode: 'OPEN',
        memberCount: 15420,
        ownerId: 'u-1',
        ownerName: 'Nguyễn Thanh Tùng',
        isOwner: false,
        isMember: false,
      );

      final router = GoRouter(
        initialLocation: '/fandoms/sontung-mtp-sky',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('Trang Chủ Khám Phá')),
            ),
          ),
          GoRoute(
            path: '/fandoms/:slug',
            builder: (context, state) => FandomDetailScreen(
              slug: state.pathParameters['slug']!,
              initialFandom: fandom,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => FandomProvider()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.darkTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify FandomDetailScreen and its back button are rendered.
      expect(find.text('Sky Tour - Sơn Tùng M-TP Official'), findsOneWidget);
      final backButton = find.byKey(const Key('fandom_detail_back_button'));
      expect(backButton, findsOneWidget);

      // Tap the back button and verify navigation to '/'.
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.text('Trang Chủ Khám Phá'), findsOneWidget);
    },
  );
}
