class FandomSummaryModel {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String category;
  final String? avatarUrl;
  final String? bannerUrl;
  final String admissionMode;
  final int memberCount;
  final String ownerId;
  final String ownerName;
  final DateTime? createdAt;

  FandomSummaryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.category,
    this.avatarUrl,
    this.bannerUrl,
    this.admissionMode = 'OPEN',
    required this.memberCount,
    this.ownerId = '',
    required this.ownerName,
    this.createdAt,
  });

  factory FandomSummaryModel.fromJson(Map<String, dynamic> json) {
    return FandomSummaryModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'],
      category: json['category'] ?? 'General',
      avatarUrl: json['avatar_url'],
      bannerUrl: json['banner_url'],
      admissionMode: json['admission_mode'] ?? 'OPEN',
      memberCount: json['member_count'] ?? 1,
      ownerId: json['owner_id'] ?? '',
      ownerName: json['owner_name'] ?? 'Ẩn danh',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

class FandomDetailModel {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String category;
  final String? avatarUrl;
  final String? bannerUrl;
  final List<String> illustrationUrls;
  final String admissionMode;
  final bool isPublic;
  final String? rulesTos;
  final int memberCount;
  final String ownerId;
  final String ownerName;
  final String? ownerUsername;
  final String? ownerAvatarUrl;
  final bool isOwner;
  final bool isMember;
  final bool isPendingRequest;
  final DateTime? createdAt;

  FandomDetailModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.category,
    this.avatarUrl,
    this.bannerUrl,
    this.illustrationUrls = const [],
    required this.admissionMode,
    this.isPublic = true,
    this.rulesTos,
    required this.memberCount,
    required this.ownerId,
    required this.ownerName,
    this.ownerUsername,
    this.ownerAvatarUrl,
    required this.isOwner,
    required this.isMember,
    this.isPendingRequest = false,
    this.createdAt,
  });

  factory FandomDetailModel.fromJson(Map<String, dynamic> json) {
    final rawIllustrations = json['illustration_urls'];
    return FandomDetailModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'],
      category: json['category'] ?? 'General',
      avatarUrl: json['avatar_url'],
      bannerUrl: json['banner_url'],
      illustrationUrls: rawIllustrations is List
          ? rawIllustrations.map((e) => e.toString()).toList()
          : const [],
      admissionMode: json['admission_mode'] ?? 'OPEN',
      isPublic: json['is_public'] ?? true,
      rulesTos: json['rules_tos'],
      memberCount: json['member_count'] ?? 1,
      ownerId: json['owner_id'] ?? '',
      ownerName: json['owner_name'] ?? 'Ẩn danh',
      ownerUsername: json['owner_username'],
      ownerAvatarUrl: json['owner_avatar_url'],
      isOwner: json['is_owner'] ?? false,
      isMember: json['is_member'] ?? false,
      isPendingRequest: json['is_pending_request'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }

  FandomDetailModel copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    String? category,
    String? avatarUrl,
    String? bannerUrl,
    List<String>? illustrationUrls,
    String? admissionMode,
    bool? isPublic,
    String? rulesTos,
    int? memberCount,
    String? ownerId,
    String? ownerName,
    String? ownerUsername,
    String? ownerAvatarUrl,
    bool? isOwner,
    bool? isMember,
    bool? isPendingRequest,
    DateTime? createdAt,
  }) {
    return FandomDetailModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      category: category ?? this.category,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      illustrationUrls: illustrationUrls ?? this.illustrationUrls,
      admissionMode: admissionMode ?? this.admissionMode,
      isPublic: isPublic ?? this.isPublic,
      rulesTos: rulesTos ?? this.rulesTos,
      memberCount: memberCount ?? this.memberCount,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      ownerAvatarUrl: ownerAvatarUrl ?? this.ownerAvatarUrl,
      isOwner: isOwner ?? this.isOwner,
      isMember: isMember ?? this.isMember,
      isPendingRequest: isPendingRequest ?? this.isPendingRequest,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class FandomJoinRequestItemModel {
  final String id;
  final String fandomId;
  final String fandomName;
  final String fandomSlug;
  final String? fandomAvatarUrl;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String status;
  final Map<String, dynamic>? answersPayload;
  final DateTime? createdAt;

  FandomJoinRequestItemModel({
    required this.id,
    required this.fandomId,
    required this.fandomName,
    required this.fandomSlug,
    this.fandomAvatarUrl,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.status,
    this.answersPayload,
    this.createdAt,
  });

  factory FandomJoinRequestItemModel.fromJson(Map<String, dynamic> json) {
    return FandomJoinRequestItemModel(
      id: json['id'] ?? '',
      fandomId: json['fandom_id'] ?? '',
      fandomName: json['fandom_name'] ?? '',
      fandomSlug: json['fandom_slug'] ?? '',
      fandomAvatarUrl: json['fandom_avatar_url'],
      userId: json['user_id'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? '',
      avatarUrl: json['avatar_url'],
      status: json['status'] ?? 'PENDING',
      answersPayload: json['answers_payload'] is Map<String, dynamic>
          ? json['answers_payload']
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

class MyFandomsDataModel {
  final List<FandomSummaryModel> joined;
  final List<FandomSummaryModel> managed;
  final List<FandomJoinRequestItemModel> pendingRequests;
  final int quotaUsed;
  final int maxQuota;

  MyFandomsDataModel({
    this.joined = const [],
    this.managed = const [],
    this.pendingRequests = const [],
    this.quotaUsed = 0,
    this.maxQuota = 5,
  });

  /// All fandoms the user participates in (owned + joined)
  List<FandomSummaryModel> get allFandoms => [...managed, ...joined];

  /// Checks if the current user is the owner of a given fandom ID
  bool isOwner(String fandomId) => managed.any((f) => f.id == fandomId);

  /// Checks if the user has reached the maximum fandom creation quota
  bool get isQuotaReached => quotaUsed >= maxQuota;

  factory MyFandomsDataModel.fromJson(Map<String, dynamic> json) {
    final rawJoined = json['joined'];
    final rawManaged = json['managed'];
    final rawPending = json['pending_requests'];

    final managedList = rawManaged is List
        ? rawManaged.map((e) => FandomSummaryModel.fromJson(e)).toList()
        : const <FandomSummaryModel>[];

    return MyFandomsDataModel(
      joined: rawJoined is List
          ? rawJoined.map((e) => FandomSummaryModel.fromJson(e)).toList()
          : const [],
      managed: managedList,
      pendingRequests: rawPending is List
          ? rawPending.map((e) => FandomJoinRequestItemModel.fromJson(e)).toList()
          : const [],
      quotaUsed: json['quota_used'] ?? managedList.length,
      maxQuota: json['max_quota'] ?? 5,
    );
  }
}

class FandomPermissionBit {
  static const int readMessages = 1 << 0;
  static const int sendMessages = 1 << 1;
  static const int embedLinks = 1 << 2;
  static const int attachFiles = 1 << 3;
  static const int voiceConnect = 1 << 4;
  static const int voiceSpeak = 1 << 5;
  static const int manageChannels = 1 << 6;
  static const int manageRoles = 1 << 7;
  static const int moderateChat = 1 << 8;
  static const int muteMembers = 1 << 9;
  static const int kickMembers = 1 << 10;
  static const int banMembers = 1 << 11;
  static const int approveJoin = 1 << 12;
  static const int createInvite = 1 << 13;
  static const int administrator = 1 << 14;

  static const List<Map<String, dynamic>> allPermissions = [
    {"bit": readMessages, "name": "Đọc tin nhắn", "desc": "Xem nội dung trong các kênh chat"},
    {"bit": sendMessages, "name": "Gửi tin nhắn", "desc": "Gửi tin nhắn vào các kênh thảo luận"},
    {"bit": embedLinks, "name": "Chèn liên kết", "desc": "Gửi link kèm rich preview"},
    {"bit": attachFiles, "name": "Đính kèm tệp & ảnh", "desc": "Tải ảnh và tệp lên kênh chat"},
    {"bit": voiceConnect, "name": "Tham gia phòng Voice", "desc": "Kết nối vào các phòng âm thanh"},
    {"bit": voiceSpeak, "name": "Phát biểu trong Voice", "desc": "Bật mic nói chuyện trong phòng"},
    {"bit": manageChannels, "name": "Quản lý Kênh", "desc": "Tạo, sửa, xóa các kênh Text và Voice"},
    {"bit": manageRoles, "name": "Quản lý Vai trò", "desc": "Tạo và cấu hình quyền các Role"},
    {"bit": moderateChat, "name": "Kiểm duyệt Tin nhắn", "desc": "Ghim hoặc xóa tin nhắn vi phạm"},
    {"bit": muteMembers, "name": "Tắt tiếng thành viên", "desc": "Mute thành viên có thời hạn"},
    {"bit": kickMembers, "name": "Trục xuất thành viên", "desc": "Kick thành viên vi phạm khỏi fandom"},
    {"bit": banMembers, "name": "Cấm vĩnh viễn", "desc": "Ban vĩnh viễn thành viên khỏi fandom"},
    {"bit": approveJoin, "name": "Xét duyệt đơn gia nhập", "desc": "Duyệt hoặc từ chối đơn xét tuyển"},
    {"bit": createInvite, "name": "Tạo Link mời", "desc": "Tạo mã mời có giới hạn tham gia fandom"},
    {"bit": administrator, "name": "Quản trị viên tối cao", "desc": "Toàn quyền quản trị (bỏ qua mọi rào cản)"},
  ];
}

class RoleModel {
  final String id;
  final String fandomId;
  final String name;
  final String colorHex;
  final int priority;
  final int permissionsBitmask;
  final bool isPresetMod;
  final bool isMembershipTier;
  final DateTime? createdAt;

  RoleModel({
    required this.id,
    required this.fandomId,
    required this.name,
    this.colorHex = '#808080',
    this.priority = 0,
    this.permissionsBitmask = 0,
    this.isPresetMod = false,
    this.isMembershipTier = false,
    this.createdAt,
  });

  bool hasPermission(int bit) =>
      (permissionsBitmask & bit) != 0 || (permissionsBitmask & FandomPermissionBit.administrator) != 0;

  factory RoleModel.fromJson(Map<String, dynamic> json) {
    return RoleModel(
      id: json['id'] ?? '',
      fandomId: json['fandom_id'] ?? '',
      name: json['name'] ?? '',
      colorHex: json['color_hex'] ?? '#808080',
      priority: json['priority'] ?? 0,
      permissionsBitmask: json['permissions_bitmask'] ?? 0,
      isPresetMod: json['is_preset_mod'] ?? false,
      isMembershipTier: json['is_membership_tier'] ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }
}

class FandomMemberModel {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String status;
  final DateTime? mutedUntil;
  final DateTime? joinedAt;
  final List<RoleModel> roles;

  FandomMemberModel({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.status,
    this.mutedUntil,
    this.joinedAt,
    this.roles = const [],
  });

  bool get isMuted {
    if (status != 'MUTED') return false;
    if (mutedUntil == null) return true;
    return mutedUntil!.isAfter(DateTime.now());
  }

  bool get isBanned => status == 'BANNED';

  int get maxPriority {
    if (roles.isEmpty) return 0;
    return roles.map((r) => r.priority).reduce((a, b) => a > b ? a : b);
  }

  factory FandomMemberModel.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    return FandomMemberModel(
      userId: json['user_id'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? '',
      avatarUrl: json['avatar_url'],
      status: json['status'] ?? 'ACTIVE',
      mutedUntil: json['muted_until'] != null ? DateTime.tryParse(json['muted_until']) : null,
      joinedAt: json['joined_at'] != null ? DateTime.tryParse(json['joined_at']) : null,
      roles: rawRoles is List ? rawRoles.map((e) => RoleModel.fromJson(e)).toList() : const [],
    );
  }
}

class FandomInviteModel {
  final String code;
  final String fandomId;
  final String fandomName;
  final String fandomSlug;
  final int? maxUses;
  final int usesCount;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  FandomInviteModel({
    required this.code,
    required this.fandomId,
    required this.fandomName,
    required this.fandomSlug,
    this.maxUses,
    this.usesCount = 0,
    this.expiresAt,
    this.createdAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return expiresAt!.isBefore(DateTime.now());
  }

  bool get isExhausted {
    if (maxUses == null) return false;
    return usesCount >= maxUses!;
  }

  factory FandomInviteModel.fromJson(Map<String, dynamic> json) {
    return FandomInviteModel(
      code: json['code'] ?? '',
      fandomId: json['fandom_id'] ?? '',
      fandomName: json['fandom_name'] ?? '',
      fandomSlug: json['fandom_slug'] ?? '',
      maxUses: json['max_uses'],
      usesCount: json['uses_count'] ?? 0,
      expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }
}


