/// Dual-tab Fandom Membership Leaderboard view (Top Spending & Top Renewal Streak).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';

class WorkspaceLeaderboardView extends StatefulWidget {
  final FandomDetailModel fandom;
  final FandomLeaderboardModel? initialLeaderboard;
  final VoidCallback? onOpenMembershipTiers;

  const WorkspaceLeaderboardView({
    super.key,
    required this.fandom,
    this.initialLeaderboard,
    this.onOpenMembershipTiers,
  });

  @override
  State<WorkspaceLeaderboardView> createState() =>
      _WorkspaceLeaderboardViewState();
}

class _WorkspaceLeaderboardViewState extends State<WorkspaceLeaderboardView> {
  FandomLeaderboardModel? _leaderboard;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialLeaderboard != null) {
      _leaderboard = widget.initialLeaderboard;
      _isLoading = false;
    } else {
      _loadLeaderboard();
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);
    final provider = context.read<FandomProvider>();
    final data = await provider.fetchFandomLeaderboard(widget.fandom.slug);
    if (!mounted) return;
    setState(() {
      _leaderboard = data ??
          FandomLeaderboardModel(
            fandomId: widget.fandom.id,
          );
      _isLoading = false;
    });
  }

  String _formatVnd(int amount) {
    final raw = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final posFromEnd = raw.length - i;
      buffer.write(raw[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) {
        buffer.write('.');
      }
    }
    return '${buffer.toString()}đ';
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppTheme.primary;
    final clean = hex.replaceFirst('#', '');
    final parsed = int.tryParse('FF$clean', radix: 16);
    return parsed != null ? Color(parsed) : AppTheme.primary;
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.35),
              blurRadius: 8,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.emoji_events, color: Colors.black87, size: 18),
      );
    }
    if (rank == 2) {
      return Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Color(0xFFC0C0C0),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '#2',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    }
    if (rank == 3) {
      return Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: Color(0xFFCD7F32),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '#3',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '#$rank',
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.leaderboard_rounded,
                        color: Colors.amber,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bảng Xếp Hạng Hội Viên',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Vinh danh các Hội viên đóng góp & gắn bó bền bỉ nhất cùng ${widget.fandom.name}',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onOpenMembershipTiers != null)
                      ElevatedButton.icon(
                        key: const Key('btn_leaderboard_open_memberships'),
                        onPressed: widget.onOpenMembershipTiers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.workspace_premium, size: 18),
                        label: const Text('Nâng cấp / Gia hạn'),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Làm mới bảng xếp hạng',
                      onPressed: _isLoading ? null : _loadLeaderboard,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TabBar(
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: palette.textSecondary,
                  indicatorColor: AppTheme.primary,
                  tabs: const [
                    Tab(
                      key: Key('tab_leaderboard_spending'),
                      icon: Icon(Icons.monetization_on_outlined, size: 18),
                      text: 'Bảng Vàng Ủng Hộ (Theo Tiền)',
                    ),
                    Tab(
                      key: Key('tab_leaderboard_streak'),
                      icon: Icon(Icons.local_fire_department_rounded, size: 18),
                      text: 'Chuỗi Gia Hạn (Streak)',
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildSpendingTab(palette),
                      _buildStreakTab(palette),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpendingTab(AppPalette palette) {
    final items = _leaderboard?.spendingLeaderboard ?? const [];
    final myEntry = _leaderboard?.mySpendingEntry;

    if (items.isEmpty) {
      return _buildEmptyState(
        palette,
        icon: Icons.emoji_events_outlined,
        title: 'Chưa có dữ liệu Bảng Vàng Ủng Hộ',
        subtitle:
            'Hãy trở thành Hội viên đầu tiên sở hữu gói VIP để ghi danh lên Bảng Vàng của Fandom!',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (myEntry != null) ...[
          Container(
            key: const Key('card_my_spending_rank'),
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                _buildRankBadge(myEntry.rank),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thứ hạng Ủng hộ của bạn: #${myEntry.rank}',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tổng ủng hộ: ${_formatVnd(myEntry.totalSpentVnd)} (${myEntry.paidOrdersCount} lần đăng ký)',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        ...items.map((entry) => _buildSpendingRow(palette, entry)),
      ],
    );
  }

  Widget _buildSpendingRow(
    AppPalette palette,
    LeaderboardSpendingEntryModel entry,
  ) {
    final tierColor = _parseColor(entry.highestTierColorHex);
    final name = (entry.displayName != null && entry.displayName!.isNotEmpty)
        ? entry.displayName!
        : entry.username;

    return Container(
      key: Key('spending_rank_row_${entry.rank}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.rank == 1
              ? Colors.amber.withValues(alpha: 0.6)
              : palette.border,
          width: entry.rank == 1 ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _buildRankBadge(entry.rank),
          const SizedBox(width: 14),
          CircleAvatar(
            radius: 20,
            backgroundColor: tierColor.withValues(alpha: 0.18),
            backgroundImage:
                entry.avatarUrl != null ? NetworkImage(entry.avatarUrl!) : null,
            child: entry.avatarUrl == null
                ? Text(
                    name.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: tierColor,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (entry.highestTierName != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tierColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: tierColor.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          entry.highestTierName!,
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '@${entry.username} • ${entry.paidOrdersCount} đơn thành công',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatVnd(entry.totalSpentVnd),
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'Tổng ủng hộ',
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStreakTab(AppPalette palette) {
    final items = _leaderboard?.streakLeaderboard ?? const [];
    final myEntry = _leaderboard?.myStreakEntry;

    if (items.isEmpty) {
      return _buildEmptyState(
        palette,
        icon: Icons.local_fire_department_outlined,
        title: 'Chưa có dữ liệu Chuỗi Gia Hạn',
        subtitle:
            'Đăng ký và gia hạn gói Hội viên liên tiếp để xây dựng chuỗi ngày gắn bó cùng Fandom!',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (myEntry != null) ...[
          Container(
            key: const Key('card_my_streak_rank'),
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.deepOrange.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                _buildRankBadge(myEntry.rank),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thứ hạng Chuỗi của bạn: #${myEntry.rank}',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Chuỗi ${myEntry.streakCount} kỳ liên tiếp (${myEntry.streakDays} ngày) • Gói ${myEntry.tierName}',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        ...items.map((entry) => _buildStreakRow(palette, entry)),
      ],
    );
  }

  Widget _buildStreakRow(
    AppPalette palette,
    LeaderboardStreakEntryModel entry,
  ) {
    final tierColor = _parseColor(entry.tierColorHex);
    final name = (entry.displayName != null && entry.displayName!.isNotEmpty)
        ? entry.displayName!
        : entry.username;

    return Container(
      key: Key('streak_rank_row_${entry.rank}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.rank == 1
              ? Colors.deepOrangeAccent.withValues(alpha: 0.6)
              : palette.border,
          width: entry.rank == 1 ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _buildRankBadge(entry.rank),
          const SizedBox(width: 14),
          CircleAvatar(
            radius: 20,
            backgroundColor: tierColor.withValues(alpha: 0.18),
            backgroundImage:
                entry.avatarUrl != null ? NetworkImage(entry.avatarUrl!) : null,
            child: entry.avatarUrl == null
                ? Text(
                    name.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: tierColor,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: tierColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        entry.tierName,
                        style: TextStyle(
                          color: tierColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '@${entry.username} • ${entry.streakDays} ngày gắn bó liên tục',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.deepOrangeAccent,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '${entry.streakCount} kỳ',
                  style: const TextStyle(
                    color: Colors.deepOrangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    AppPalette palette, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: palette.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
