/// Unit tests for MessageReplyPreviewModel, MessageModel interaction fields, and ChannelModel moderation permissions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/channel_model.dart';
import 'package:frontend/models/message_model.dart';

void main() {
  group('MessageReplyPreviewModel & MessageModel interaction parsing', () {
    test('parses reply_to preview, edited flag, pinned state, and reactions map', () {
      final json = {
        'id': 'msg-reply-01',
        'channel_id': 'ch-01',
        'fandom_id': 'fd-01',
        'sender_id': 'user-02',
        'sender': {
          'id': 'user-02',
          'username': 'fan_member',
          'display_name': 'Fan Nhiệt Huyết',
          'is_owner': false,
        },
        'content': 'Mình đăng ký 2 vé khu A nhé!',
        'attachments': [],
        'reply_to_id': 'msg-root-01',
        'reply_to': {
          'id': 'msg-root-01',
          'sender_id': 'user-01',
          'sender_display_name': 'Chủ Fandom',
          'content': 'Ai đi concert tối nay điểm danh nào!',
          'is_recalled': false,
        },
        'is_pinned': true,
        'reactions': {
          '🔥': ['user-01', 'user-02'],
          '❤️': ['user-01'],
        },
        'is_edited': true,
        'is_recalled': false,
        'created_at': '2026-11-05T12:00:00Z',
        'updated_at': '2026-11-05T12:05:00Z',
      };

      final msg = MessageModel.fromJson(json);

      expect(msg.id, 'msg-reply-01');
      expect(msg.replyToId, 'msg-root-01');
      expect(msg.replyTo, isNotNull);
      expect(msg.replyTo!.id, 'msg-root-01');
      expect(msg.replyTo!.senderDisplayName, 'Chủ Fandom');
      expect(msg.replyTo!.content, 'Ai đi concert tối nay điểm danh nào!');
      expect(msg.replyTo!.isRecalled, isFalse);
      expect(msg.isPinned, isTrue);
      expect(msg.isEdited, isTrue);
      expect(msg.isRecalled, isFalse);
      expect(msg.reactions['🔥'], hasLength(2));
      expect(msg.reactions['❤️'], hasLength(1));
    });

    test('ChannelModel.canModerateChat evaluates MODERATE_CHAT and ADMINISTRATOR', () {
      final regularChannel = ChannelModel(
        id: 'ch-1',
        fandomId: 'fd-1',
        name: 'chat-chung',
        type: 'TEXT',
        myPermissions: {
          FandomPermission.viewChannel,
          FandomPermission.sendMessages,
        },
      );
      expect(regularChannel.canModerateChat, isFalse);

      final modChannel = ChannelModel(
        id: 'ch-1',
        fandomId: 'fd-1',
        name: 'chat-chung',
        type: 'TEXT',
        myPermissions: {
          FandomPermission.viewChannel,
          FandomPermission.moderateChat,
        },
      );
      expect(modChannel.canModerateChat, isTrue);
    });
  });
}
