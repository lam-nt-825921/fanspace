/// Dialog displaying pinned messages in a text channel.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/message_model.dart';

class PinnedMessagesDialog extends StatelessWidget {
  final ChannelModel channel;
  final List<MessageModel> pinnedMessages;

  const PinnedMessagesDialog({
    super.key,
    required this.channel,
    required this.pinnedMessages,
  });

  static Future<void> show(
    BuildContext context, {
    required ChannelModel channel,
    required List<MessageModel> pinnedMessages,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PinnedMessagesDialog(
        channel: channel,
        pinnedMessages: pinnedMessages,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      title: Row(
        children: [
          const Icon(Icons.push_pin_rounded, color: AppTheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tin nhắn đã ghim',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: pinnedMessages.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.push_pin_outlined,
                      size: 40,
                      color: palette.textMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có tin nhắn nào được ghim trong kênh này.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pinnedMessages.length,
                  separatorBuilder: (_, _) => Divider(color: palette.border),
                  itemBuilder: (context, idx) {
                    final msg = pinnedMessages[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.14),
                        child: Text(
                          msg.sender.displayName.characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        msg.sender.displayName,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          msg.content,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
