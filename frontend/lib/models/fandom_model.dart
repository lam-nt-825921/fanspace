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
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}

