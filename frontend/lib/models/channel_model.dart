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

/// Bitmask constants for granular channel-level Role and Membership permissions (FR-10).
class ChannelPermissionBit {
  static const int readMessages = 1 << 0; // 1
  static const int sendMessages = 1 << 1; // 2
  static const int embedLinks = 1 << 2; // 4
  static const int attachFiles = 1 << 3; // 8
  static const int voiceConnect = 1 << 4; // 16
  static const int voiceSpeak = 1 << 5; // 32
  static const int bypassSlowmode = 1 << 15; // 32768

  static const int defaultChannelMask =
      readMessages |
      sendMessages |
      embedLinks |
      attachFiles |
      voiceConnect |
      voiceSpeak |
      bypassSlowmode; // 32831
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
  final int minMembershipTierLevel;
  final bool membershipBypassSlowmode;
  final String? requiredRoleId;
  final List<String> allowedRoleIds;
  final int maxMembers;
  final int rolePermissionsBitmask;
  final int membershipPermissionsBitmask;
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
    this.minMembershipTierLevel = 0,
    this.membershipBypassSlowmode = false,
    this.requiredRoleId,
    this.allowedRoleIds = const [],
    this.maxMembers = 0,
    this.rolePermissionsBitmask = ChannelPermissionBit.defaultChannelMask,
    this.membershipPermissionsBitmask = ChannelPermissionBit.defaultChannelMask,
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
    final rawAllowedRoles = json['allowed_role_ids'];
    final reqRoleId = json['required_role_id']?.toString();
    final parsedAllowedRoles = <String>[];
    if (rawAllowedRoles is List) {
      for (final item in rawAllowedRoles) {
        final str = item?.toString() ?? '';
        if (str.isNotEmpty && !parsedAllowedRoles.contains(str)) {
          parsedAllowedRoles.add(str);
        }
      }
    }
    if (parsedAllowedRoles.isEmpty && reqRoleId != null && reqRoleId.isNotEmpty) {
      parsedAllowedRoles.add(reqRoleId);
    }

    return ChannelModel(
      id: json['id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'TEXT',
      topic: json['topic']?.toString(),
      position: json['position'] is int ? json['position'] as int : 0,
      isAnnouncement: json['is_announcement'] == true,
      isMembershipOnly: json['is_membership_only'] == true,
      minMembershipTierLevel: json['min_membership_tier_level'] is int
          ? json['min_membership_tier_level'] as int
          : 0,
      membershipBypassSlowmode: json['membership_bypass_slowmode'] == true,
      requiredRoleId:
          reqRoleId ?? (parsedAllowedRoles.isNotEmpty ? parsedAllowedRoles.first : null),
      allowedRoleIds: parsedAllowedRoles,
      maxMembers: json['max_members'] is int ? json['max_members'] as int : 0,
      rolePermissionsBitmask: json['role_permissions_bitmask'] is int
          ? json['role_permissions_bitmask'] as int
          : ChannelPermissionBit.defaultChannelMask,
      membershipPermissionsBitmask: json['membership_permissions_bitmask'] is int
          ? json['membership_permissions_bitmask'] as int
          : ChannelPermissionBit.defaultChannelMask,
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

/// Real-time participant inside a voice channel room (FR-11 / UC-06).
class VoiceParticipantModel {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final bool isMuted;
  final bool isHandRaised;
  final bool isOwner;
  final DateTime? joinedAt;

  const VoiceParticipantModel({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.role = 'LISTENER',
    this.isMuted = true,
    this.isHandRaised = false,
    this.isOwner = false,
    this.joinedAt,
  });

  bool get isSpeaker => role == 'SPEAKER';

  factory VoiceParticipantModel.fromJson(Map<String, dynamic> json) {
    return VoiceParticipantModel(
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName:
          json['display_name']?.toString() ?? json['username']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      role: json['role']?.toString() ?? 'LISTENER',
      isMuted: json['is_muted'] != false,
      isHandRaised: json['is_hand_raised'] == true,
      isOwner: json['is_owner'] == true,
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
    );
  }
}

/// Snapshot of a real-time voice channel room (Open Mic or Stage Room via Agora RTC).
class VoiceRoomStateModel {
  final String channelId;
  final String fandomId;
  final String channelName;
  final String voiceRoomType;
  final int maxMembers;
  final int activeCount;
  final List<VoiceParticipantModel> participants;
  final List<String> raisedHandUserIds;

  const VoiceRoomStateModel({
    required this.channelId,
    required this.fandomId,
    this.channelName = '',
    this.voiceRoomType = 'OPEN_MIC',
    this.maxMembers = 0,
    this.activeCount = 0,
    this.participants = const [],
    this.raisedHandUserIds = const [],
  });

  List<VoiceParticipantModel> get speakers =>
      participants.where((p) => p.isSpeaker).toList();

  List<VoiceParticipantModel> get listeners =>
      participants.where((p) => !p.isSpeaker).toList();

  factory VoiceRoomStateModel.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    final rawRaisedHands = json['raised_hand_user_ids'];
    final parsedParticipants = rawParticipants is List
        ? rawParticipants
            .whereType<Map<String, dynamic>>()
            .map(VoiceParticipantModel.fromJson)
            .toList()
        : const <VoiceParticipantModel>[];

    return VoiceRoomStateModel(
      channelId: json['channel_id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      channelName: json['channel_name']?.toString() ?? '',
      voiceRoomType: json['voice_room_type']?.toString() ?? 'OPEN_MIC',
      maxMembers: json['max_members'] is int ? json['max_members'] as int : 0,
      activeCount: json['active_count'] is int
          ? json['active_count'] as int
          : parsedParticipants.length,
      participants: parsedParticipants,
      raisedHandUserIds: rawRaisedHands is List
          ? rawRaisedHands.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

