/// Data models for channel messages, sender profiles, attachments, and cursor pagination.
library;

/// Metadata for a media attachment embedded inside a channel message.
class MessageAttachmentModel {
  final String url;
  final String type;
  final String? filename;

  const MessageAttachmentModel({
    required this.url,
    this.type = 'IMAGE',
    this.filename,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'type': type,
        if (filename != null) 'filename': filename,
      };

  factory MessageAttachmentModel.fromJson(Map<String, dynamic> json) {
    return MessageAttachmentModel(
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'IMAGE',
      filename: json['filename']?.toString(),
    );
  }
}

/// Public profile summary of the user who authored a channel message.
class MessageSenderModel {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isOwner;

  const MessageSenderModel({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isOwner = false,
  });

  factory MessageSenderModel.fromJson(Map<String, dynamic> json) {
    return MessageSenderModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName:
          json['display_name']?.toString() ?? json['username']?.toString() ?? 'Thành viên',
      avatarUrl: json['avatar_url']?.toString(),
      isOwner: json['is_owner'] == true,
    );
  }
}

/// Represents a single message posted in a Fandom text or announcement channel.
class MessageModel {
  final String id;
  final String channelId;
  final String fandomId;
  final String senderId;
  final MessageSenderModel sender;
  final String content;
  final List<MessageAttachmentModel> attachments;
  final String? replyToId;
  final bool isPinned;
  final Map<String, dynamic> reactions;
  final bool isEdited;
  final bool isRecalled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MessageModel({
    required this.id,
    required this.channelId,
    required this.fandomId,
    required this.senderId,
    required this.sender,
    required this.content,
    this.attachments = const [],
    this.replyToId,
    this.isPinned = false,
    this.reactions = const {},
    this.isEdited = false,
    this.isRecalled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    final rawReactions = json['reactions'];
    final rawSender = json['sender'];

    return MessageModel(
      id: json['id']?.toString() ?? '',
      channelId: json['channel_id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      sender: rawSender is Map<String, dynamic>
          ? MessageSenderModel.fromJson(rawSender)
          : const MessageSenderModel(
              id: '',
              username: 'member',
              displayName: 'Thành viên',
            ),
      content: json['content']?.toString() ?? '',
      attachments: rawAttachments is List
          ? rawAttachments
              .whereType<Map<String, dynamic>>()
              .map(MessageAttachmentModel.fromJson)
              .toList()
          : const [],
      replyToId: json['reply_to_id']?.toString(),
      isPinned: json['is_pinned'] == true,
      reactions: rawReactions is Map<String, dynamic> ? rawReactions : const {},
      isEdited: json['is_edited'] == true,
      isRecalled: json['is_recalled'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

/// Paginated response slice for channel message history.
class MessageListResponseModel {
  final String channelId;
  final String fandomId;
  final List<MessageModel> messages;
  final bool hasMore;
  final String? nextCursor;

  const MessageListResponseModel({
    required this.channelId,
    required this.fandomId,
    required this.messages,
    this.hasMore = false,
    this.nextCursor,
  });

  factory MessageListResponseModel.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return MessageListResponseModel(
      channelId: json['channel_id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map<String, dynamic>>()
              .map(MessageModel.fromJson)
              .toList()
          : const [],
      hasMore: json['has_more'] == true,
      nextCursor: json['next_cursor']?.toString(),
    );
  }
}
