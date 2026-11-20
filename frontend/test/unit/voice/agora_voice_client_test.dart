/// Unit tests for AgoraVoiceClient facade and stub implementation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/voice/agora_voice_client.dart';

void main() {
  group('AgoraVoiceClient Audio Management Tests', () {
    late AgoraVoiceClient client;

    setUp(() {
      client = AgoraVoiceClient.instance;
    });

    test('joinVoiceRoom and leaveVoiceRoom update connection lifecycle', () async {
      final joined = await client.joinVoiceRoom(
        appId: 'test_app_id',
        channelName: 'test_channel',
        token: 'test_token',
        uid: 12345,
        role: 'SPEAKER',
      );
      expect(joined, isTrue);

      final left = await client.leaveVoiceRoom();
      expect(left, isTrue);
    });

    test('setLocalMute and enforceRole toggle microphone state', () async {
      final muted = await client.setLocalMute(true);
      expect(muted, isTrue);

      final unmuted = await client.setLocalMute(false);
      expect(unmuted, isTrue);

      final demoted = await client.enforceRole('LISTENER');
      expect(demoted, isTrue);

      final promoted = await client.enforceRole('SPEAKER');
      expect(promoted, isTrue);
    });

    test('setUserVolume adjusts per-user volume from 0% to 200%', () async {
      const targetUid = 99999;
      // Default volume is 100%
      expect(client.getUserVolume(targetUid), equals(100.0));

      // Adjust volume to 150% (boost)
      final set150 = await client.setUserVolume(targetUid, 150.0);
      expect(set150, isTrue);
      expect(client.getUserVolume(targetUid), equals(150.0));

      // Adjust volume down to 30%
      final set30 = await client.setUserVolume(targetUid, 30.0);
      expect(set30, isTrue);
      expect(client.getUserVolume(targetUid), equals(30.0));
    });

    test('setLocalUserMuted toggles 1-way local mute for specific participant', () async {
      const targetUid = 88888;
      expect(client.isUserLocallyMuted(targetUid), isFalse);

      // Mute user locally
      final muted = await client.setLocalUserMuted(targetUid, true);
      expect(muted, isTrue);
      expect(client.isUserLocallyMuted(targetUid), isTrue);

      // Unmute user locally
      final unmuted = await client.setLocalUserMuted(targetUid, false);
      expect(unmuted, isTrue);
      expect(client.isUserLocallyMuted(targetUid), isFalse);
    });

    test('setDeafen toggles master room deafen for self', () async {
      expect(client.isDeafenActive(), isFalse);

      // Turn Deafen ON
      final deafened = await client.setDeafen(true);
      expect(deafened, isTrue);
      expect(client.isDeafenActive(), isTrue);

      // Turn Deafen OFF
      final undeafened = await client.setDeafen(false);
      expect(undeafened, isTrue);
      expect(client.isDeafenActive(), isFalse);
    });
  });
}
