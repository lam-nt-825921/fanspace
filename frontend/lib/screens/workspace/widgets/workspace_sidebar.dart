/// Sidebar navigation for FandomWorkspaceScreen with quick page navigation and channel groups.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/fandom_model.dart';
import '../../home/dialogs/my_fandoms_quick_switcher_dialog.dart';
import '../fandom_workspace_screen.dart';

class WorkspaceSidebar extends StatelessWidget {
  final FandomDetailModel fandom;
  final FandomChannelsDataModel channelsData;
  final WorkspaceSection activeSection;
  final ChannelModel? selectedChannel;
  final bool rulesAcknowledged;
  final bool isDrawer;
  final VoidCallback onSelectWelcome;
  final VoidCallback onSelectRules;
  final VoidCallback? onSelectLeaderboard;
  final VoidCallback onOpenMembershipTiers;
  final VoidCallback onOpenFandomSettings;
  final VoidCallback onCreateChannel;
  final ValueChanged<ChannelModel> onSelectChannel;

  const WorkspaceSidebar({
    super.key,
    required this.fandom,
    required this.channelsData,
    required this.activeSection,
    required this.selectedChannel,
    required this.rulesAcknowledged,
    required this.isDrawer,
    required this.onSelectWelcome,
    required this.onSelectRules,
    this.onSelectLeaderboard,
    required this.onOpenMembershipTiers,
    required this.onOpenFandomSettings,
    required this.onCreateChannel,
    required this.onSelectChannel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final announcementChannels = channelsData.channels
        .where((c) => c.type == 'TEXT' && c.isAnnouncement)
        .toList();
    final textChannels = channelsData.channels
        .where((c) => c.type == 'TEXT' && !c.isAnnouncement)
        .toList();
    final voiceChannels =
        channelsData.channels.where((c) => c.type == 'VOICE').toList();

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Quick Global Navigation Bar (no URL editing needed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                border: Border(
                  bottom: BorderSide(color: palette.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => GoRouter.maybeOf(context)?.go('/'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.explore_outlined,
                              size: 16,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Trang chủ',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chuyển nhanh sang Fandom khác',
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        MyFandomsQuickSwitcherDialog.show(context),
                  ),
                  IconButton(
                    tooltip: 'Về trang giới thiệu Fandom',
                    icon: Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => GoRouter.maybeOf(context)
                        ?.go('/fandoms/${fandom.slug}'),
                  ),
                ],
              ),
            ),

            // Fandom Identity Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: palette.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.16),
                    backgroundImage: fandom.avatarUrl != null
                        ? NetworkImage(fandom.avatarUrl!)
                        : null,
                    child: fandom.avatarUrl == null
                        ? Text(
                            fandom.name.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fandom.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${fandom.memberCount} thành viên',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fandom.isOwner)
                    IconButton(
                      key: const Key('btn_fandom_settings'),
                      tooltip: 'Cài đặt Fandom',
                      icon: Icon(
                        Icons.settings_outlined,
                        size: 18,
                        color: palette.textSecondary,
                      ),
                      onPressed: onOpenFandomSettings,
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Tùy chọn Fandom',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                    color: palette.surfaceElevated,
                    onSelected: (value) {
                      switch (value) {
                        case 'settings':
                          onOpenFandomSettings();
                        case 'vip':
                          onOpenMembershipTiers();
                        case 'cover':
                          GoRouter.maybeOf(context)
                              ?.go('/fandoms/${fandom.slug}');
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (fandom.isOwner)
                        const PopupMenuItem(
                          value: 'settings',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.settings_outlined, size: 18),
                            title: Text('Tất cả cài đặt Fandom'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'vip',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.workspace_premium_outlined,
                            size: 18,
                            color: Colors.amber,
                          ),
                          title: Text('Gói Hội viên VIP'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'cover',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.open_in_new_rounded, size: 18),
                          title: Text('Trang giới thiệu Fandom'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Navigation & Channels List
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'CỔNG ĐÓN TIẾP & THÔNG TIN',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.home_outlined,
                    label: 'Giới thiệu chung',
                    selected: activeSection == WorkspaceSection.welcome,
                    onTap: () {
                      onSelectWelcome();
                      if (isDrawer) Navigator.of(context).pop();
                    },
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.gavel_outlined,
                    label: 'Nội quy & Quy định',
                    selected: activeSection == WorkspaceSection.rules,
                    trailing: rulesAcknowledged
                        ? const Icon(
                            Icons.verified,
                            size: 16,
                            color: AppTheme.success,
                          )
                        : null,
                    onTap: () {
                      onSelectRules();
                      if (isDrawer) Navigator.of(context).pop();
                    },
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.leaderboard_outlined,
                    label: 'Bảng xếp hạng Hội viên',
                    selected: activeSection == WorkspaceSection.leaderboard,
                    trailing: const Icon(
                      Icons.emoji_events_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                    onTap: () {
                      onSelectLeaderboard?.call();
                      if (isDrawer) Navigator.of(context).pop();
                    },
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.workspace_premium_outlined,
                    label: 'Gói Hội viên VIP',
                    selected: false,
                    trailing: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                    onTap: () {
                      if (isDrawer) Navigator.of(context).pop();
                      onOpenMembershipTiers();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (channelsData.canManageChannels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: onCreateChannel,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tạo kênh mới'),
                      ),
                    ),
                  if (announcementChannels.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'KÊNH THÔNG BÁO',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final ch in announcementChannels)
                      _buildChannelTile(context, ch),
                    const SizedBox(height: 12),
                  ],
                  if (textChannels.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'KÊNH TRÒ CHUYỆN',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final ch in textChannels)
                      _buildChannelTile(context, ch),
                    const SizedBox(height: 12),
                  ],
                  if (voiceChannels.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'KÊNH THOẠI (VOICE)',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final ch in voiceChannels)
                      _buildChannelTile(context, ch),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppTheme.primary : palette.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? (palette.isDark ? Colors.white : AppTheme.primary)
                          : palette.textSecondary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelTile(BuildContext context, ChannelModel channel) {
    final palette = context.palette;
    final isSelected = activeSection == WorkspaceSection.channel &&
        selectedChannel?.id == channel.id;

    IconData iconData;
    if (channel.type == 'VOICE') {
      iconData = channel.voiceRoomType == 'STAGE_ROOM'
          ? Icons.podcasts
          : Icons.volume_up_outlined;
    } else if (channel.isAnnouncement) {
      iconData = Icons.campaign_outlined;
    } else {
      iconData = Icons.tag;
    }

    Widget? trailing;
    if (channel.isMembershipOnly) {
      trailing = const Icon(
        Icons.workspace_premium_rounded,
        size: 14,
        color: Colors.amber,
      );
    } else if (channel.slowModeSeconds > 0) {
      trailing = Icon(
        Icons.timer_outlined,
        size: 14,
        color: palette.textMuted,
      );
    }

    return _buildNavTile(
      context: context,
      icon: iconData,
      label: channel.name,
      selected: isSelected,
      trailing: trailing,
      onTap: () {
        onSelectChannel(channel);
        if (isDrawer) Navigator.of(context).pop();
      },
    );
  }
}
