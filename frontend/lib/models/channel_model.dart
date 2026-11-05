/// Declarative permission specifications and channel data models for Fandom workspaces.
library;

/// Canonical permission identifiers matching the backend `Permission` enumeration.
class FandomPermission {
  static const String viewChannel = 'VIEW_CHANNEL';
  static const String readMessages = 'READ_MESSAGES';
  static const String sendMessages = 'SEND_MESSAGES';
  static const String sendAnnouncement = 'SEND_ANNOUNCEMENT';
  static const String attachFiles = 'ATTACH_FILES';
  static const String embedLinks = 'EMBED_LINKS';
  static const String moderateChat = 'MODERATE_CHAT';
  static const String bypassSlowmode = 'BYPASS_SLOWMODE';
  static const String manageChannels = 'MANAGE_CHANNELS';
  static const String voiceConnect = 'VOICE_CONNECT';
  static const String voiceSpeak = 'VOICE_SPEAK';
  static const String administrator = 'ADMINISTRATOR';
}

/// Declarative specification of permissions expected by a frontend feature or view.
class PermissionSpec {
  /// Permissions that must all be present for the requirement to be satisfied.
  final Set<String> mustHave;

  /// Permissions where at least one must be present (if non-empty).
  final Set<String> anyOf;

  /// Optional permissions inspected to unlock additional UI capabilities.
  final Set<String> mayHave;

  const PermissionSpec({
    this.mustHave = const {},
    this.anyOf = const {},
    this.mayHave = const {},
  });

  /// Evaluates whether [granted] satisfies this specification.
  bool isSatisfiedBy(Iterable<String> granted) {
    final grantedSet = granted.toSet();
    if (grantedSet.contains(FandomPermission.administrator)) {
      return true;
    }
    if (!grantedSet.containsAll(mustHave)) {
      return false;
    }
    if (anyOf.isNotEmpty && grantedSet.intersection(anyOf).isEmpty) {
      return false;
    }
    return true;
  }
}

/// Represents a single communication channel (Text, Announcement, or Voice) in a Fandom.
class ChannelModel {
  final String id;
  final String fandomId;
  final String name;
  final String type;
  final String? topic;
  final int position;
  final bool isAnnouncement;
  final bool isMembershipOnly;
  final String? requiredRoleId;
  final int slowModeSeconds;
  final String? voiceRoomType;
  final DateTime? createdAt;
  final Set<String> myPermissions;

  /// Declarative requirement for posting messages in a regular text channel.
  static const PermissionSpec sendRegularMessageSpec = PermissionSpec(
    mustHave: {
      FandomPermission.viewChannel,
      FandomPermission.sendMessages,
    },
    mayHave: {
      FandomPermission.attachFiles,
      FandomPermission.embedLinks,
      FandomPermission.bypassSlowmode,
    },
  );

  /// Declarative requirement for posting in an announcement channel.
  static const PermissionSpec sendAnnouncementMessageSpec = PermissionSpec(
    mustHave: {
      FandomPermission.viewChannel,
      FandomPermission.sendMessages,
      FandomPermission.sendAnnouncement,
    },
  );

  /// Declarative requirement for editing or deleting a channel.
  static const PermissionSpec manageChannelSpec = PermissionSpec(
    mustHave: {
      FandomPermission.viewChannel,
      FandomPermission.manageChannels,
    },
  );

  /// Declarative requirement for connecting to a voice channel.
  static const PermissionSpec connectVoiceSpec = PermissionSpec(
    mustHave: {
      FandomPermission.viewChannel,
      FandomPermission.voiceConnect,
    },
    mayHave: {
      FandomPermission.voiceSpeak,
    },
  );

  ChannelModel({
    required this.id,
    required this.fandomId,
    required this.name,
    required this.type,
    this.topic,
    this.position = 0,
    this.isAnnouncement = false,
    this.isMembershipOnly = false,
    this.requiredRoleId,
    this.slowModeSeconds = 0,
    this.voiceRoomType,
    this.createdAt,
    this.myPermissions = const {},
  });

  /// Evaluates an arbitrary [PermissionSpec] against [myPermissions].
  bool satisfies(PermissionSpec spec) => spec.isSatisfiedBy(myPermissions);

  /// Whether the caller is allowed to send messages in this channel.
  bool get canSendMessages => isAnnouncement
      ? satisfies(sendAnnouncementMessageSpec)
      : satisfies(sendRegularMessageSpec);

  /// Whether the caller is allowed to attach media files in this channel.
  bool get canAttachFiles => satisfies(
        const PermissionSpec(
          mustHave: {
            FandomPermission.viewChannel,
            FandomPermission.sendMessages,
            FandomPermission.attachFiles,
          },
        ),
      );

  /// Whether the caller can edit or delete this channel.
  bool get canManageChannel => satisfies(manageChannelSpec);

  /// Whether the caller can moderate messages (pin/unpin or recall others' messages) in this channel.
  bool get canModerateChat => satisfies(
        const PermissionSpec(
          mustHave: {
            FandomPermission.viewChannel,
            FandomPermission.moderateChat,
          },
        ),
      );

  /// Whether the caller can connect to this voice room.
  bool get canConnectVoice => satisfies(connectVoiceSpec);

  /// Whether the caller can unmute and speak in this voice room.
  bool get canSpeakVoice => satisfies(
        const PermissionSpec(
          mustHave: {
            FandomPermission.viewChannel,
            FandomPermission.voiceConnect,
            FandomPermission.voiceSpeak,
          },
        ),
      );

  factory ChannelModel.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['my_permissions'];
    return ChannelModel(
      id: json['id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'TEXT',
      topic: json['topic']?.toString(),
      position: json['position'] is int ? json['position'] as int : 0,
      isAnnouncement: json['is_announcement'] == true,
      isMembershipOnly: json['is_membership_only'] == true,
      requiredRoleId: json['required_role_id']?.toString(),
      slowModeSeconds:
          json['slow_mode_seconds'] is int ? json['slow_mode_seconds'] as int : 0,
      voiceRoomType: json['voice_room_type']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      myPermissions: rawPerms is List
          ? rawPerms.map((e) => e.toString()).toSet()
          : const {},
    );
  }
}

/// Aggregates all channels and fandom-level permissions for the caller.
class FandomChannelsDataModel {
  final String fandomId;
  final String slug;
  final Set<String> myFandomPermissions;
  final List<ChannelModel> channels;

  FandomChannelsDataModel({
    required this.fandomId,
    required this.slug,
    this.myFandomPermissions = const {},
    this.channels = const [],
  });

  /// Evaluates whether the caller has `MANAGE_CHANNELS` at the fandom level.
  bool get canManageChannels => const PermissionSpec(
        mustHave: {
          FandomPermission.viewChannel,
          FandomPermission.manageChannels,
        },
      ).isSatisfiedBy(myFandomPermissions);

  factory FandomChannelsDataModel.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['my_fandom_permissions'];
    final rawChannels = json['channels'];
    return FandomChannelsDataModel(
      fandomId: json['fandom_id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      myFandomPermissions: rawPerms is List
          ? rawPerms.map((e) => e.toString()).toSet()
          : const {},
      channels: rawChannels is List
          ? rawChannels
              .whereType<Map<String, dynamic>>()
              .map(ChannelModel.fromJson)
              .toList()
          : const [],
    );
  }
}
