/// Unit tests for frontend declarative PermissionSpec and ChannelModel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/channel_model.dart';

void main() {
  group('Frontend PermissionSpec & ChannelModel Unit Tests', () {
    test('PermissionSpec enforces mustHave and anyOf and respects ADMINISTRATOR', () {
      const spec = PermissionSpec(
        mustHave: {
          FandomPermission.viewChannel,
          FandomPermission.readMessages,
        },
        anyOf: {
          FandomPermission.sendMessages,
          FandomPermission.sendAnnouncement,
        },
        mayHave: {
          FandomPermission.attachFiles,
        },
      );

      expect(
        spec.isSatisfiedBy({
          FandomPermission.viewChannel,
          FandomPermission.readMessages,
          FandomPermission.sendMessages,
        }),
        isTrue,
      );

      // Missing one mustHave permission -> false.
      expect(
        spec.isSatisfiedBy({
          FandomPermission.viewChannel,
          FandomPermission.sendMessages,
        }),
        isFalse,
      );

      // Missing all anyOf permissions -> false.
      expect(
        spec.isSatisfiedBy({
          FandomPermission.viewChannel,
          FandomPermission.readMessages,
        }),
        isFalse,
      );

      // ADMINISTRATOR satisfies any PermissionSpec automatically.
      expect(
        spec.isSatisfiedBy({FandomPermission.administrator}),
        isTrue,
      );
    });

    test('ChannelModel parses JSON and evaluates declarative channel capabilities', () {
      final announcementChannel = ChannelModel.fromJson({
        'id': 'ch-ann-1',
        'fandom_id': 'f-1',
        'name': 'thông-báo',
        'type': 'TEXT',
        'topic': 'Kênh thông báo chính thức',
        'position': 0,
        'is_announcement': true,
        'is_membership_only': false,
        'slow_mode_seconds': 0,
        'my_permissions': ['VIEW_CHANNEL', 'READ_MESSAGES'],
      });

      expect(announcementChannel.isAnnouncement, isTrue);
      expect(announcementChannel.canSendMessages, isFalse);
      expect(announcementChannel.canManageChannel, isFalse);

      final generalChannel = ChannelModel.fromJson({
        'id': 'ch-txt-1',
        'fandom_id': 'f-1',
        'name': 'chat-chung',
        'type': 'TEXT',
        'topic': 'Kênh thảo luận chung',
        'position': 1,
        'is_announcement': false,
        'is_membership_only': false,
        'slow_mode_seconds': 5,
        'my_permissions': [
          'VIEW_CHANNEL',
          'READ_MESSAGES',
          'SEND_MESSAGES',
          'ATTACH_FILES',
        ],
      });

      expect(generalChannel.canSendMessages, isTrue);
      expect(generalChannel.canAttachFiles, isTrue);
      expect(generalChannel.slowModeSeconds, 5);
    });
  });
}
