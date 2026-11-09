/// Header bar for an active text or voice channel with pinned messages and action options menu.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../widgets/theme/theme_toggle_button.dart';

class ChannelHeaderBar extends StatelessWidget {
  final ChannelModel channel;
  final bool canManage;
  final VoidCallback onOpenPinnedMessages;
  final VoidCallback onEditChannel;
  final VoidCallback onDeleteChannel;

  const ChannelHeaderBar({
    super.key,
    required this.channel,
    required this.canManage,
    required this.onOpenPinnedMessages,
    required this.onEditChannel,
    required this.onDeleteChannel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            channel.type == 'VOICE'
                ? Icons.volume_up_outlined
                : (channel.isAnnouncement
                    ? Icons.campaign_outlined
                    : Icons.tag),
            color: AppTheme.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      channel.name,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (channel.isMembershipOnly)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.workspace_premium_rounded,
                              size: 12,
                              color: Colors.amber,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'VIP',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (channel.slowModeSeconds > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Chế độ chậm: ${channel.slowModeSeconds}s',
                          style: const TextStyle(
                            color: AppTheme.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (channel.topic != null && channel.topic!.isNotEmpty)
                  Text(
                    channel.topic!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (channel.type == 'TEXT')
            IconButton(
              key: const Key('channel_pinned_messages_button'),
              tooltip: 'Tin nhắn đã ghim',
              icon: Icon(
                Icons.push_pin_outlined,
                size: 20,
                color: palette.textSecondary,
              ),
              onPressed: onOpenPinnedMessages,
            ),
          const ThemeToggleButton(compact: true),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: 'Tùy chọn quản lý kênh',
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
              color: palette.surfaceElevated,
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEditChannel();
                  case 'delete':
                    onDeleteChannel();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined, size: 18),
                    title: Text('Chỉnh sửa cấu hình kênh'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppTheme.error,
                    ),
                    title: Text(
                      'Xóa kênh này',
                      style: TextStyle(color: AppTheme.error),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
