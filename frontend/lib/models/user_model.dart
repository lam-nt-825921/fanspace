class UserModel {
  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? bio;
  final int coinBalance;
  final bool isEmailVerified;
  final String systemRole;
  final bool hasPassword;
  final bool isGoogleLinked;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bannerUrl,
    this.bio,
    this.coinBalance = 0,
    this.isEmailVerified = false,
    this.systemRole = 'USER',
    this.hasPassword = true,
    this.isGoogleLinked = false,
    this.createdAt,
  });

  bool get isAdmin => systemRole == 'SYSTEM_ADMIN';
  bool get isModerator => systemRole == 'SYSTEM_MODERATOR' || isAdmin;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['username'] ?? '',
      avatarUrl: json['avatar_url'],
      bannerUrl: json['banner_url'],
      bio: json['bio'],
      coinBalance: json['coin_balance'] ?? 0,
      isEmailVerified: json['is_email_verified'] ?? false,
      systemRole: json['system_role'] ?? 'USER',
      hasPassword: json['has_password'] ?? true,
      isGoogleLinked: json['is_google_linked'] ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'bio': bio,
      'coin_balance': coinBalance,
      'is_email_verified': isEmailVerified,
      'system_role': systemRole,
      'has_password': hasPassword,
      'is_google_linked': isGoogleLinked,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? displayName,
    String? avatarUrl,
    String? bannerUrl,
    String? bio,
    int? coinBalance,
    bool? isEmailVerified,
    String? systemRole,
    bool? hasPassword,
    bool? isGoogleLinked,
  }) {
    return UserModel(
      id: id,
      email: email,
      username: username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      bio: bio ?? this.bio,
      coinBalance: coinBalance ?? this.coinBalance,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      systemRole: systemRole ?? this.systemRole,
      hasPassword: hasPassword ?? this.hasPassword,
      isGoogleLinked: isGoogleLinked ?? this.isGoogleLinked,
      createdAt: createdAt,
    );
  }
}

class UserProfilePublicModel {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? bio;
  final String systemRole;
  final DateTime createdAt;
  final int fandomsOwnedCount;
  final int fandomsJoinedCount;

  UserProfilePublicModel({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bannerUrl,
    this.bio,
    this.systemRole = 'USER',
    required this.createdAt,
    this.fandomsOwnedCount = 0,
    this.fandomsJoinedCount = 0,
  });

  bool get isAdmin => systemRole == 'SYSTEM_ADMIN';
  bool get isModerator => systemRole == 'SYSTEM_MODERATOR' || isAdmin;

  factory UserProfilePublicModel.fromJson(Map<String, dynamic> json) {
    return UserProfilePublicModel(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['username'] ?? '',
      avatarUrl: json['avatar_url'],
      bannerUrl: json['banner_url'],
      bio: json['bio'],
      systemRole: json['system_role'] ?? 'USER',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      fandomsOwnedCount: json['fandoms_owned_count'] ?? 0,
      fandomsJoinedCount: json['fandoms_joined_count'] ?? 0,
    );
  }
}
