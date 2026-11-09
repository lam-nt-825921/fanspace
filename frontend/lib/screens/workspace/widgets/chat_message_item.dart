/// Individual chat message row with reply quote, reactions, and contextual action option menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/message_model.dart';

class ChatMessageItem extends StatelessWidget {
  static const List<String> _availableEmojis = [
    '👍',
    '❤️',
    '🔥',
    '😂',
    '🎉',
    '👏',
  ];

  final ChannelModel channel;
  final MessageModel message;
  final VoidCallback onReply;
  final ValueChanged<String> onToggleReaction;
  final VoidCallback onEdit;
  final VoidCallback onRecall;
  final VoidCallback onTogglePin;
  final List<MessageModel> threadReplies;
  final bool isThreadExpanded;
  final VoidCallback? onToggleThread;
  final ValueChanged<MessageModel>? onReplyToThreadMessage;
  final void Function(MessageModel reply, String emoji)? onToggleThreadReaction;
  final ValueChanged<MessageModel>? onEditThreadMessage;
  final ValueChanged<MessageModel>? onRecallThreadMessage;
  final ValueChanged<MessageModel>? onPinThreadMessage;
  final bool isThreadChild;

  const ChatMessageItem({
    super.key,
    required this.channel,
    required this.message,
    required this.onReply,
    required this.onToggleReaction,
    required this.onEdit,
    required this.onRecall,
    required this.onTogglePin,
    this.threadReplies = const [],
    this.isThreadExpanded = true,
    this.onToggleThread,
    this.onReplyToThreadMessage,
    this.onToggleThreadReaction,
    this.onEditThreadMessage,
    this.onRecallThreadMessage,
    this.onPinThreadMessage,
    this.isThreadChild = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sender = message.sender;
    final timeStr =
        '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}';
    final canModerate = channel.canModerateChat;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isThreadChild ? 6 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isThreadChild ? 15 : 19,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.16),
            backgroundImage: sender.avatarUrl != null
                ? NetworkImage(sender.avatarUrl!)
                : null,
            child: sender.avatarUrl == null
                ? Text(
                    sender.displayName.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: isThreadChild ? 12 : 14,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.replyTo != null && !isThreadChild) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceLight.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: AppTheme.primary, width: 3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.reply_rounded,
                          size: 14,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '@${message.replyTo!.senderDisplayName}: ${message.replyTo!.content}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sender.displayName,
                      style: TextStyle(
                        color: sender.isOwner
                            ? AppTheme.primary
                            : palette.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: isThreadChild ? 13 : 14,
                      ),
                    ),
                    if (sender.isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Chủ Fandom',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (message.isPinned)
                      const Icon(
                        Icons.push_pin,
                        size: 13,
                        color: Colors.amber,
                      ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (message.isEdited && !message.isRecalled)
                      Text(
                        '• đã chỉnh sửa',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Message text + compact inline actions right next to text
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceLight.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: palette.border.withValues(alpha: 0.7),
                          ),
                        ),
                        child: message.isRecalled
                            ? Text(
                                'Tin nhắn đã bị thu hồi.',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : SelectableText(
                                message.content,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                      ),
                    ),
                    if (!message.isRecalled) ...[
                      const SizedBox(width: 6),
                      _buildCompactActionCluster(
                        context,
                        palette: palette,
                        canModerate: canModerate,
                      ),
                    ],
                  ],
                ),
                if (!message.isRecalled && message.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final att in message.attachments)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            att.url,
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              padding: const EdgeInsets.all(12),
                              color: palette.surfaceLight,
                              child: Text(
                                att.filename ?? att.url,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (!message.isRecalled && message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in message.reactions.entries)
                        if (entry.value is List &&
                            (entry.value as List).isNotEmpty)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onToggleReaction(entry.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                '${entry.key} ${(entry.value as List).length}',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
                // Slack-style collapsible reply thread
                if (!isThreadChild && threadReplies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSlackThreadSection(context, palette),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact action bar placed immediately next to the message text bubble:
  /// 1. Grouped emoji reaction picker button
  /// 2. Quick reply button (opens/focuses thread reply)
  /// 3. 3-dot more options menu right next to the text
  Widget _buildCompactActionCluster(
    BuildContext context, {
    required AppPalette palette,
    required bool canModerate,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grouped Emoji Picker Popup
          PopupMenuButton<String>(
            key: Key('message_reaction_picker_${message.id}'),
            tooltip: 'Bày tỏ cảm xúc',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: palette.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: palette.border),
            ),
            icon: Icon(
              Icons.add_reaction_outlined,
              size: 16,
              color: palette.textSecondary,
            ),
            onSelected: onToggleReaction,
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                enabled: false,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final emoji in _availableEmojis)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onToggleReaction(emoji);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Reply action button
          if (channel.canSendMessages)
            InkWell(
              key: Key('message_reply_${message.id}'),
              borderRadius: BorderRadius.circular(6),
              onTap: onReply,
              child: Tooltip(
                message: 'Trả lời theo luồng',
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(
                    Icons.reply_rounded,
                    size: 16,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          // 3-dot menu right next to text
          PopupMenuButton<String>(
            key: Key('message_more_${message.id}'),
            tooltip: 'Tùy chọn tin nhắn',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 17,
              color: palette.textSecondary,
            ),
            color: palette.surfaceElevated,
            onSelected: (value) {
              switch (value) {
                case 'reply':
                  onReply();
                case 'edit':
                  onEdit();
                case 'recall':
                  onRecall();
                case 'pin':
                  onTogglePin();
                case 'copy':
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text('Đã sao chép nội dung tin nhắn.'),
                    ),
                  );
              }
            },
            itemBuilder: (ctx) => [
              if (channel.canSendMessages)
                const PopupMenuItem(
                  value: 'reply',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.reply_rounded, size: 18),
                    title: Text('Trả lời trong luồng'),
                  ),
                ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.copy_rounded, size: 18),
                  title: Text('Sao chép nội dung'),
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 18),
                  title: Text('Chỉnh sửa tin nhắn'),
                ),
              ),
              if (canModerate)
                PopupMenuItem(
                  value: 'pin',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.push_pin_outlined, size: 18),
                    title: Text(
                      message.isPinned
                          ? 'Bỏ ghim tin nhắn'
                          : 'Ghim tin nhắn',
                    ),
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'recall',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.undo_rounded,
                    size: 18,
                    color: AppTheme.error,
                  ),
                  title: Text(
                    'Thu hồi tin nhắn',
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

  /// Slack-style collapsible reply thread section under parent message.
  Widget _buildSlackThreadSection(BuildContext context, AppPalette palette) {
    final replyCount = threadReplies.length;
    final lastReply = threadReplies.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: Key('thread_toggle_${message.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onToggleThread,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 15,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '$replyCount phản hồi',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isThreadExpanded
                        ? 'Thu gọn luồng'
                        : '${lastReply.sender.displayName}: ${lastReply.content}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isThreadExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ],
            ),
          ),
        ),
        if (isThreadExpanded)
          Container(
            margin: const EdgeInsets.only(top: 6, left: 6),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                  width: 2.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reply in threadReplies)
                  ChatMessageItem(
                    channel: channel,
                    message: reply,
                    isThreadChild: true,
                    onReply: () =>
                        (onReplyToThreadMessage ?? (_) => onReply())(reply),
                    onToggleReaction: (emoji) =>
                        onToggleThreadReaction?.call(reply, emoji),
                    onEdit: () => onEditThreadMessage?.call(reply),
                    onRecall: () => onRecallThreadMessage?.call(reply),
                    onTogglePin: () => onPinThreadMessage?.call(reply),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
