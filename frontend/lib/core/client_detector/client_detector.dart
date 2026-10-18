import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ClientInfo {
  final String platform; // "MOBILE", "DESKTOP", "WEB"
  final String? deviceId;

  const ClientInfo({
    required this.platform,
    this.deviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      if (deviceId != null) 'device_id': deviceId,
    };
  }
}

class ClientDetector {
  static const String _deviceIdKey = 'fanspace_device_id';
  static final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Returns the current client platform and persistent device ID (if mobile).
  static Future<ClientInfo> getClientInfo() async {
    if (kIsWeb) {
      return const ClientInfo(platform: 'WEB', deviceId: null);
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final deviceId = await _getOrCreateDeviceId();
        return ClientInfo(platform: 'MOBILE', deviceId: deviceId);
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return const ClientInfo(platform: 'DESKTOP', deviceId: null);
      }
    } catch (_) {
      // Fallback if Platform check fails
    }

    return const ClientInfo(platform: 'WEB', deviceId: null);
  }

  /// Retrieves or securely generates a persistent device UUID.
  static Future<String> _getOrCreateDeviceId() async {
    try {
      final existingId = await _storage.read(key: _deviceIdKey);
      if (existingId != null && existingId.isNotEmpty) {
        return existingId;
      }

      final newId = _generateUuidV4();
      await _storage.write(key: _deviceIdKey, value: newId);
      return newId;
    } catch (_) {
      return _generateUuidV4();
    }
  }

  /// Generates a cryptographically secure UUID v4 string.
  static String _generateUuidV4() {
    final Random random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));

    // Set version to 0100 (v4)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to 10xx (RFC 4122)
    values[8] = (values[8] & 0x3f) | 0x80;

    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
