class FandomSummaryModel {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String category;
  final String? avatarUrl;
  final String? bannerUrl;
  final int memberCount;
  final String ownerName;

  FandomSummaryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.category,
    this.avatarUrl,
    this.bannerUrl,
    required this.memberCount,
    required this.ownerName,
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
      memberCount: json['member_count'] ?? 1,
      ownerName: json['owner_name'] ?? 'Ẩn danh',
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
  final String admissionMode;
  final String? rulesTos;
  final int memberCount;
  final String ownerId;
  final String ownerName;
  final bool isOwner;
  final bool isMember;

  FandomDetailModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.category,
    this.avatarUrl,
    this.bannerUrl,
    required this.admissionMode,
    this.rulesTos,
    required this.memberCount,
    required this.ownerId,
    required this.ownerName,
    required this.isOwner,
    required this.isMember,
  });

  factory FandomDetailModel.fromJson(Map<String, dynamic> json) {
    return FandomDetailModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'],
      category: json['category'] ?? 'General',
      avatarUrl: json['avatar_url'],
      bannerUrl: json['banner_url'],
      admissionMode: json['admission_mode'] ?? 'OPEN',
      rulesTos: json['rules_tos'],
      memberCount: json['member_count'] ?? 1,
      ownerId: json['owner_id'] ?? '',
      ownerName: json['owner_name'] ?? 'Ẩn danh',
      isOwner: json['is_owner'] ?? false,
      isMember: json['is_member'] ?? false,
    );
  }
}
