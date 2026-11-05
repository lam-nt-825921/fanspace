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

