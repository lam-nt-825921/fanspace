class SessionModel {
  final String id;
  final String platform;
  final String? deviceName;
  final String? ipAddress;
  final bool isCurrent;
  final DateTime? lastActiveAt;
  final DateTime? createdAt;

  SessionModel({
    required this.id,
    required this.platform,
    this.deviceName,
    this.ipAddress,
    this.isCurrent = false,
    this.lastActiveAt,
    this.createdAt,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id']?.toString() ?? '',
      platform: json['platform'] ?? 'WEB',
      deviceName: json['device_name'],
      ipAddress: json['ip_address'],
      isCurrent: json['is_current'] ?? false,
      lastActiveAt: json['last_active_at'] != null ? DateTime.tryParse(json['last_active_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'platform': platform,
      'device_name': deviceName,
      'ip_address': ipAddress,
      'is_current': isCurrent,
      'last_active_at': lastActiveAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
