/// Abstract Voice Client Interface for Agora RTC integration.
library;

import 'agora_voice_client_stub.dart'
    if (dart.library.html) 'agora_voice_client_web.dart';

abstract class AgoraVoiceClient {
  static final AgoraVoiceClient instance = getAgoraVoiceClient();

  /// Whether the underlying WebRTC / Agora engine is available.
  bool get isSupported;

  /// Connects to the Agora RTC room, captures microphone (if SPEAKER), and starts audio playback.
  Future<bool> joinVoiceRoom({
    required String appId,
    required String channelName,
    required String token,
    required int uid,
    required String role,
  });

  /// Leaves the Agora RTC room and releases local microphone tracks.
  Future<bool> leaveVoiceRoom();

  /// Toggles hardware microphone transmission.
  Future<bool> setLocalMute(bool isMuted);

  /// Enforces server-side moderation role (LISTENER -> unpublish & release mic; SPEAKER -> publish mic).
  Future<bool> enforceRole(String newRole);

  /// Sets personal listening volume for a specific participant (0% to 200%).
  Future<bool> setUserVolume(int uid, double volumePercent);

  /// Retrieves personal listening volume for a specific participant (default 100%).
  double getUserVolume(int uid);

  /// Toggles 1-way local mute for a specific participant (mute for self only).
  Future<bool> setLocalUserMuted(int uid, bool isMuted);

  /// Whether a specific participant is locally muted for the current user.
  bool isUserLocallyMuted(int uid);

  /// Toggles Deafen mode (mutes all remote room audio out of self's speakers).
  Future<bool> setDeafen(bool isDeafened);

  /// Whether Deafen mode is currently active.
  bool isDeafenActive();
}
