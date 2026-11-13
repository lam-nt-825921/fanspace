import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/screens/workspace/widgets/workspace_leaderboard_view.dart';

void main() {
  final testFandom = FandomDetailModel(
    id: 'fandom-1',
    name: 'Fandom Âm Nhạc',
    slug: 'fandom-am-nhac',
    category: 'Music',
    admissionMode: 'OPEN',
    memberCount: 120,
    ownerId: 'owner-1',
    ownerName: 'Chủ Fandom',
    isOwner: false,
    isMember: true,
  );

  final testLeaderboard = FandomLeaderboardModel(
    fandomId: 'fandom-1',
    spendingLeaderboard: [
      LeaderboardSpendingEntryModel(
        rank: 1,
        userId: 'u-whale',
        username: 'fan_whale',
        displayName: 'Đại Gia Fandom',
        totalSpentVnd: 300000,
        paidOrdersCount: 2,
        highestTierName: 'Hội viên Vàng',
        highestTierLevel: 2,
        highestTierColorHex: '#FFD700',
      ),
      LeaderboardSpendingEntryModel(
        rank: 2,
        userId: 'u-streak',
        username: 'fan_streak',
        displayName: 'Fan Bền Bỉ',
        totalSpentVnd: 80000,
        paidOrdersCount: 2,
        highestTierName: 'Hội viên Bạc',
        highestTierLevel: 1,
        highestTierColorHex: '#42A5F5',
      ),
    ],
    streakLeaderboard: [
      LeaderboardStreakEntryModel(
        rank: 1,
        userId: 'u-streak',
        username: 'fan_streak',
        displayName: 'Fan Bền Bỉ',
        streakCount: 3,
        streakDays: 90,
        tierName: 'Hội viên Bạc',
        tierLevel: 1,
        tierColorHex: '#42A5F5',
      ),
      LeaderboardStreakEntryModel(
        rank: 2,
        userId: 'u-whale',
        username: 'fan_whale',
        displayName: 'Đại Gia Fandom',
        streakCount: 1,
        streakDays: 30,
        tierName: 'Hội viên Vàng',
        tierLevel: 2,
        tierColorHex: '#FFD700',
      ),
    ],
    mySpendingEntry: LeaderboardSpendingEntryModel(
      rank: 2,
      userId: 'u-streak',
      username: 'fan_streak',
      displayName: 'Fan Bền Bỉ',
      totalSpentVnd: 80000,
      paidOrdersCount: 2,
      highestTierName: 'Hội viên Bạc',
      highestTierLevel: 1,
      highestTierColorHex: '#42A5F5',
    ),
    myStreakEntry: LeaderboardStreakEntryModel(
      rank: 1,
      userId: 'u-streak',
      username: 'fan_streak',
      displayName: 'Fan Bền Bỉ',
      streakCount: 3,
      streakDays: 90,
      tierName: 'Hội viên Bạc',
      tierLevel: 1,
      tierColorHex: '#42A5F5',
    ),
  );

  testWidgets(
    'WorkspaceLeaderboardView renders Spending and Streak tabs and switches accurately',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceLeaderboardView(
              fandom: testFandom,
              initialLeaderboard: testLeaderboard,
              onOpenMembershipTiers: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Tab 1 (Spending Leaderboard) is shown by default
      expect(find.text('Bảng Xếp Hạng Hội Viên'), findsOneWidget);
      expect(find.byKey(const Key('card_my_spending_rank')), findsOneWidget);
      expect(find.textContaining('Thứ hạng Ủng hộ của bạn: #2'), findsOneWidget);
      expect(find.text('Đại Gia Fandom'), findsOneWidget);
      expect(find.text('300.000đ'), findsOneWidget);
      expect(find.text('80.000đ'), findsOneWidget);

      // Switch to Tab 2 (Streak Leaderboard)
      await tester.tap(find.byKey(const Key('tab_leaderboard_streak')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('card_my_streak_rank')), findsOneWidget);
      expect(find.textContaining('Thứ hạng Chuỗi của bạn: #1'), findsOneWidget);
      expect(find.text('3 kỳ'), findsOneWidget);
      expect(find.textContaining('90 ngày gắn bó liên tục'), findsOneWidget);
      expect(find.text('1 kỳ'), findsOneWidget);
    },
  );
}
