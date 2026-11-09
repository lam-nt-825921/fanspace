/// Message composer bar and read-only permission notice for text channels.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/message_model.dart';

class ChatMessageComposer extends StatelessWidget {
  final ChannelModel channel;
  final TextEditingController messageController;
  final MessageModel? replyingToMessage;
  final List<MessageAttachmentModel> pendingAttachments;
  final bool isUploadingAttachment;
  final bool isSendingMessage;
  final VoidCallback onCancelReply;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onPickAttachment;
  final VoidCallback onSendMessage;

  const ChatMessageComposer({
    super.key,
    required this.channel,
    required this.messageController,
    required this.replyingToMessage,
    required this.pendingAttachments,
    required this.isUploadingAttachment,
    required this.isSendingMessage,
    required this.onCancelReply,
    required this.onRemoveAttachment,
    required this.onPickAttachment,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (!channel.canSendMessages) {
      final reasonText = channel.isAnnouncement
          ? 'Chỉ Chủ Fandom và Ban quản trị mới có quyền đăng thông báo tại kênh này.'
          : 'Bạn hiện không có quyền gửi tin nhắn trong kênh này.';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(
            top: BorderSide(color: palette.border, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 18,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                reasonText,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyingToMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: palette.surfaceLight,
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                  left: BorderSide(color: AppTheme.primary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đang trả lời @${replyingToMessage!.sender.displayName}: ${replyingToMessage!.content}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: palette.textSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onCancelReply,
                  ),
                ],
              ),
            ),
          ],
          if (pendingAttachments.isNotEmpty) ...[
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pendingAttachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final item = pendingAttachments[idx];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.url,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => onRemoveAttachment(idx),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (channel.canAttachFiles)
                IconButton(
                  tooltip: 'Đính kèm hình ảnh',
                  icon: isUploadingAttachment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.add_photo_alternate_outlined,
                          color: palette.textSecondary,
                        ),
                  onPressed: isUploadingAttachment ? null : onPickAttachment,
                ),
              Expanded(
                child: TextField(
                  key: const Key('channel_message_input'),
                  controller: messageController,
                  cursorColor: AppTheme.primary,
                  style: TextStyle(
                    color: palette.isDark ? Colors.white : palette.textPrimary,
                    fontSize: 14,
                  ),
                  onSubmitted: (_) => onSendMessage(),
                  decoration: InputDecoration(
                    hintText: 'Nhắn tin tới #${channel.name}...',
                    hintStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: palette.border,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: palette.isDark
                        ? AppTheme.surfaceLight
                        : palette.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('channel_send_button'),
                tooltip: 'Gửi tin nhắn',
                icon: isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, color: AppTheme.primary),
                onPressed: isSendingMessage ? null : onSendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
