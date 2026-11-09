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
  static const int bypassSlowmode = 1 << 15;

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
    {"bit": bypassSlowmode, "name": "Miễn Slow-mode", "desc": "Không bị giới hạn thời gian chờ giữa các tin nhắn"},
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
  final int? tierLevel;
  final String? iconUrl;
  final int? priceFiatVnd;
  final int? durationDays;
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
    this.tierLevel,
    this.iconUrl,
    this.priceFiatVnd,
    this.durationDays,
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
      tierLevel: json['tier_level'],
      iconUrl: json['icon_url'],
      priceFiatVnd: json['price_fiat_vnd'],
      durationDays: json['duration_days'],
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

class FandomBankAccountModel {
  final String id;
  final String fandomId;
  final String bankCode;
  final String accountNumber;
  final String accountName;
  final bool isActive;
  final DateTime? updatedAt;

  FandomBankAccountModel({
    required this.id,
    required this.fandomId,
    required this.bankCode,
    required this.accountNumber,
    required this.accountName,
    this.isActive = true,
    this.updatedAt,
  });

  factory FandomBankAccountModel.fromJson(Map<String, dynamic> json) {
    return FandomBankAccountModel(
      id: json['id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      bankCode: json['bank_code'] ?? 'MBBank',
      accountNumber: json['account_number'] ?? '',
      accountName: json['account_name'] ?? '',
      isActive: json['is_active'] ?? true,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}

class MembershipTierModel {
  final String id;
  final String fandomId;
  final String name;
  final int tierLevel;
  final String colorHex;
  final int priority;
  final int permissionsBitmask;
  final int priceFiatVnd;
  final int durationDays;
  final String? iconUrl;
  final bool isOwned;
  final DateTime? ownedExpiresAt;
  final DateTime? createdAt;

  MembershipTierModel({
    required this.id,
    required this.fandomId,
    required this.name,
    this.tierLevel = 1,
    this.colorHex = '#FFD700',
    this.priority = 50,
    this.permissionsBitmask = 0,
    required this.priceFiatVnd,
    this.durationDays = 30,
    this.iconUrl,
    this.isOwned = false,
    this.ownedExpiresAt,
    this.createdAt,
  });

  bool hasPermission(int bit) =>
      (permissionsBitmask & bit) != 0 ||
      (permissionsBitmask & FandomPermissionBit.administrator) != 0;

  factory MembershipTierModel.fromJson(Map<String, dynamic> json) {
    return MembershipTierModel(
      id: json['id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      name: json['name'] ?? '',
      tierLevel: json['tier_level'] ?? 1,
      colorHex: json['color_hex'] ?? '#FFD700',
      priority: json['priority'] ?? 50,
      permissionsBitmask: json['permissions_bitmask'] ?? 0,
      priceFiatVnd: json['price_fiat_vnd'] ?? 0,
      durationDays: json['duration_days'] ?? 30,
      iconUrl: json['icon_url'],
      isOwned: json['is_owned'] ?? false,
      ownedExpiresAt: json['owned_expires_at'] != null
          ? DateTime.tryParse(json['owned_expires_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class FandomMembershipsDataModel {
  final String fandomId;
  final bool bankConfigured;
  final FandomBankAccountModel? bankAccount;
  final List<MembershipTierModel> tiers;

  FandomMembershipsDataModel({
    required this.fandomId,
    this.bankConfigured = false,
    this.bankAccount,
    this.tiers = const [],
  });

  factory FandomMembershipsDataModel.fromJson(Map<String, dynamic> json) {
    final rawTiers = json['tiers'];
    return FandomMembershipsDataModel(
      fandomId: json['fandom_id']?.toString() ?? '',
      bankConfigured: json['bank_configured'] ?? false,
      bankAccount: json['bank_account'] is Map<String, dynamic>
          ? FandomBankAccountModel.fromJson(json['bank_account'])
          : null,
      tiers: rawTiers is List
          ? rawTiers
              .whereType<Map<String, dynamic>>()
              .map(MembershipTierModel.fromJson)
              .toList()
          : const [],
    );
  }
}

class PaymentTransactionModel {
  final String id;
  final int sepayTransactionId;
  final String? orderId;
  final String? orderCode;
  final String? userId;
  final String? fandomId;
  final String gateway;
  final String transactionDate;
  final String accountNumber;
  final String transferType;
  final int transferAmount;
  final String? code;
  final String content;
  final String? referenceCode;
  final String reconciliationStatus;
  final String? auditNote;
  final DateTime? createdAt;

  PaymentTransactionModel({
    required this.id,
    required this.sepayTransactionId,
    this.orderId,
    this.orderCode,
    this.userId,
    this.fandomId,
    required this.gateway,
    required this.transactionDate,
    required this.accountNumber,
    this.transferType = 'in',
    required this.transferAmount,
    this.code,
    required this.content,
    this.referenceCode,
    required this.reconciliationStatus,
    this.auditNote,
    this.createdAt,
  });

  bool get isDiscrepant => const {
        'UNDERPAID',
        'OVERPAID',
        'UNMATCHED_ORDER',
        'EXPIRED_ORDER',
      }.contains(reconciliationStatus);

  factory PaymentTransactionModel.fromJson(Map<String, dynamic> json) {
    return PaymentTransactionModel(
      id: json['id']?.toString() ?? '',
      sepayTransactionId: json['sepay_transaction_id'] ?? 0,
      orderId: json['order_id']?.toString(),
      orderCode: json['order_code']?.toString(),
      userId: json['user_id']?.toString(),
      fandomId: json['fandom_id']?.toString(),
      gateway: json['gateway'] ?? 'MBBank',
      transactionDate: json['transaction_date'] ?? '',
      accountNumber: json['account_number'] ?? '',
      transferType: json['transfer_type'] ?? 'in',
      transferAmount: json['transfer_amount'] ?? 0,
      code: json['code']?.toString(),
      content: json['content'] ?? '',
      referenceCode: json['reference_code']?.toString(),
      reconciliationStatus: json['reconciliation_status'] ?? 'UNMATCHED_ORDER',
      auditNote: json['audit_note']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class PaymentOrderModel {
  final String id;
  final String orderCode;
  final String userId;
  final String fandomId;
  final String roleId;
  final String roleName;
  final int amountVnd;
  final int paidAmountVnd;
  final int remainingAmountVnd;
  final int durationDays;
  final String bankCode;
  final String accountNumber;
  final String accountName;
  final String qrUrl;
  final String status;
  final DateTime expiresAt;
  final DateTime? paidAt;
  final DateTime? memberRoleExpiresAt;
  final DateTime? createdAt;
  final List<PaymentTransactionModel> transactions;

  PaymentOrderModel({
    required this.id,
    required this.orderCode,
    required this.userId,
    required this.fandomId,
    required this.roleId,
    required this.roleName,
    required this.amountVnd,
    this.paidAmountVnd = 0,
    required this.remainingAmountVnd,
    this.durationDays = 30,
    required this.bankCode,
    required this.accountNumber,
    required this.accountName,
    required this.qrUrl,
    required this.status,
    required this.expiresAt,
    this.paidAt,
    this.memberRoleExpiresAt,
    this.createdAt,
    this.transactions = const [],
  });

  bool get isCompleted => status == 'PAID' || status == 'OVERPAID';
  bool get isUnderpaid => status == 'UNDERPAID';
  bool get isPending => status == 'PENDING';

  factory PaymentOrderModel.fromJson(Map<String, dynamic> json) {
    final rawTxs = json['transactions'];
    final amount = (json['amount_vnd'] ?? 0) as int;
    final paid = (json['paid_amount_vnd'] ?? 0) as int;
    return PaymentOrderModel(
      id: json['id']?.toString() ?? '',
      orderCode: json['order_code'] ?? '',
      userId: json['user_id']?.toString() ?? '',
      fandomId: json['fandom_id']?.toString() ?? '',
      roleId: json['role_id']?.toString() ?? '',
      roleName: json['role_name'] ?? '',
      amountVnd: amount,
      paidAmountVnd: paid,
      remainingAmountVnd:
          json['remaining_amount_vnd'] ?? (amount > paid ? amount - paid : 0),
      durationDays: json['duration_days'] ?? 30,
      bankCode: json['bank_code'] ?? 'MBBank',
      accountNumber: json['account_number'] ?? '',
      accountName: json['account_name'] ?? '',
      qrUrl: json['qr_url'] ?? '',
      status: json['status'] ?? 'PENDING',
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
          DateTime.now().add(const Duration(minutes: 15)),
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'].toString())
          : null,
      memberRoleExpiresAt: json['member_role_expires_at'] != null
          ? DateTime.tryParse(json['member_role_expires_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      transactions: rawTxs is List
          ? rawTxs
              .whereType<Map<String, dynamic>>()
              .map(PaymentTransactionModel.fromJson)
              .toList()
          : const [],
    );
  }
}

class FandomLedgerModel {
  final String fandomId;
  final int totalRevenueVnd;
  final int paidOrdersCount;
  final int discrepantTransactionsCount;
  final List<PaymentOrderModel> orders;
  final List<PaymentTransactionModel> transactions;

  FandomLedgerModel({
    required this.fandomId,
    this.totalRevenueVnd = 0,
    this.paidOrdersCount = 0,
    this.discrepantTransactionsCount = 0,
    this.orders = const [],
    this.transactions = const [],
  });

  factory FandomLedgerModel.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'];
    final rawTxs = json['transactions'];
    return FandomLedgerModel(
      fandomId: json['fandom_id']?.toString() ?? '',
      totalRevenueVnd: json['total_revenue_vnd'] ?? 0,
      paidOrdersCount: json['paid_orders_count'] ?? 0,
      discrepantTransactionsCount: json['discrepant_transactions_count'] ?? 0,
      orders: rawOrders is List
          ? rawOrders
              .whereType<Map<String, dynamic>>()
              .map(PaymentOrderModel.fromJson)
              .toList()
          : const [],
      transactions: rawTxs is List
          ? rawTxs
              .whereType<Map<String, dynamic>>()
              .map(PaymentTransactionModel.fromJson)
              .toList()
          : const [],
    );
  }
}



