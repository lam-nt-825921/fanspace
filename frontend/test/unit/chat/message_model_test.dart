/// Unit tests for MessageModel, MessageSenderModel, and MessageListResponseModel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/message_model.dart';

void main() {
  group('MessageModel & Pagination Response Serialization Tests', () {
    test('MessageModel parses sender, content, and attachments accurately', () {
      final json = {
        'id': 'msg-001',
        'channel_id': 'ch-001',
        'fandom_id': 'f-001',
        'sender_id': 'u-001',
        'sender': {
          'id': 'u-001',
          'username': 'sontung_sky',
          'display_name': 'Nguyễn Thanh Tùng',
          'avatar_url': 'https://example.com/avatar.jpg',
          'is_owner': true,
        },
        'content': 'Chào mừng toàn thể đại gia đình Sky!',
        'attachments': [
          {
            'url': 'https://example.com/photo.jpg',
            'type': 'IMAGE',
            'filename': 'photo.jpg',
          },
        ],
        'is_pinned': true,
        'is_edited': false,
        'is_recalled': false,
        'created_at': '2026-11-05T10:00:00Z',
        'updated_at': '2026-11-05T10:00:00Z',
      };

      final message = MessageModel.fromJson(json);
      expect(message.id, 'msg-001');
      expect(message.sender.displayName, 'Nguyễn Thanh Tùng');
      expect(message.sender.isOwner, isTrue);
      expect(message.content, 'Chào mừng toàn thể đại gia đình Sky!');
      expect(message.attachments.length, 1);
      expect(message.attachments.first.url, 'https://example.com/photo.jpg');
      expect(message.isPinned, isTrue);
    });

    test('MessageListResponseModel parses cursor pagination fields', () {
      final json = {
        'channel_id': 'ch-001',
        'fandom_id': 'f-001',
        'has_more': true,
        'next_cursor': 'msg-001',
        'messages': [
          {
            'id': 'msg-001',
            'channel_id': 'ch-001',
            'fandom_id': 'f-001',
            'sender_id': 'u-001',
            'sender': {
              'id': 'u-001',
              'username': 'fan_01',
              'display_name': 'Fan 01',
              'is_owner': false,
            },
            'content': 'Tin nhắn đầu tiên',
            'attachments': [],
            'created_at': '2026-11-05T10:00:00Z',
            'updated_at': '2026-11-05T10:00:00Z',
          },
        ],
      };

      final page = MessageListResponseModel.fromJson(json);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'msg-001');
      expect(page.messages.length, 1);
      expect(page.messages.first.content, 'Tin nhắn đầu tiên');
    });
  });
}
