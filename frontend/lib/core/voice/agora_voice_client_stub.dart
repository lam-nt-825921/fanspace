/// Fallback / In-Memory Mock Voice Client for non-Web platforms & Widget Tests.
library;

import 'agora_voice_client.dart';

AgoraVoiceClient getAgoraVoiceClient() => AgoraVoiceClientStub();

class AgoraVoiceClientStub implements AgoraVoiceClient {
  bool _isMuted = false;
  bool _isDeafened = false;
  String _role = 'LISTENER';
  final Map<int, double> _volumes = {};
  final Set<int> _localMuted = {};

  bool get isMuted => _isMuted;
  String get role => _role;

  @override
  bool get isSupported => false;

  @override
  Future<bool> joinVoiceRoom({
    required String appId,
    required String channelName,
    required String token,
    required int uid,
    required String role,
  }) async {
    _role = role;
    return true;
  }

  @override
  Future<bool> leaveVoiceRoom() async => true;

  @override
  Future<bool> setLocalMute(bool isMuted) async {
    _isMuted = isMuted;
    return true;
  }

  @override
  Future<bool> enforceRole(String newRole) async {
    _role = newRole;
    return true;
  }

  @override
  Future<bool> setUserVolume(int uid, double volumePercent) async {
    _volumes[uid] = volumePercent;
    return true;
  }

  @override
  double getUserVolume(int uid) => _volumes[uid] ?? 100.0;

  @override
  Future<bool> setLocalUserMuted(int uid, bool isMuted) async {
    if (isMuted) {
      _localMuted.add(uid);
    } else {
      _localMuted.remove(uid);
    }
    return true;
  }

  @override
  bool isUserLocallyMuted(int uid) => _localMuted.contains(uid);

  @override
  Future<bool> setDeafen(bool isDeafened) async {
    _isDeafened = isDeafened;
    return true;
  }

  @override
  bool isDeafenActive() => _isDeafened;
}
