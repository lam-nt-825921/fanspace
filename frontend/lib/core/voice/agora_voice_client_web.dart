/// Web Implementation connecting to `window.agoraVoiceBridge` via dart:js_interop.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'agora_voice_client.dart';

AgoraVoiceClient getAgoraVoiceClient() => AgoraVoiceClientWeb();

class AgoraVoiceClientWeb implements AgoraVoiceClient {
  JSObject? get _bridge {
    try {
      if (globalContext.hasProperty('agoraVoiceBridge'.toJS).toDart) {
        return globalContext.getProperty('agoraVoiceBridge'.toJS) as JSObject?;
      }
    } catch (_) {}
    return null;
  }

  @override
  bool get isSupported => _bridge != null;

  @override
  Future<bool> joinVoiceRoom({
    required String appId,
    required String channelName,
    required String token,
    required int uid,
    required String role,
  }) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      final promise = b.callMethodVarArgs<JSAny?>(
        'joinVoiceRoom'.toJS,
        <JSAny?>[
          appId.toJS,
          channelName.toJS,
          token.toJS,
          uid.toJS,
          role.toJS,
        ],
      );
      if (promise != null && promise.isA<JSPromise>()) {
        await (promise as JSPromise).toDart;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> leaveVoiceRoom() async {
    final b = _bridge;
    if (b == null) return false;
    try {
      final promise = b.callMethod<JSAny?>('leaveVoiceRoom'.toJS);
      if (promise != null && promise.isA<JSPromise>()) {
        await (promise as JSPromise).toDart;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setLocalMute(bool isMuted) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      final promise = b.callMethod<JSAny?>('setLocalMute'.toJS, isMuted.toJS);
      if (promise != null && promise.isA<JSPromise>()) {
        await (promise as JSPromise).toDart;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> enforceRole(String newRole) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      final promise = b.callMethod<JSAny?>('enforceRole'.toJS, newRole.toJS);
      if (promise != null && promise.isA<JSPromise>()) {
        await (promise as JSPromise).toDart;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setUserVolume(int uid, double volumePercent) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      b.callMethod<JSAny?>('setUserVolume'.toJS, uid.toJS, volumePercent.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  double getUserVolume(int uid) {
    final b = _bridge;
    if (b == null) return 100.0;
    try {
      final res = b.callMethod<JSAny?>('getUserVolume'.toJS, uid.toJS);
      if (res != null && res.isA<JSNumber>()) {
        return (res as JSNumber).toDartDouble;
      }
    } catch (_) {}
    return 100.0;
  }

  @override
  Future<bool> setLocalUserMuted(int uid, bool isMuted) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      b.callMethod<JSAny?>('setLocalUserMuted'.toJS, uid.toJS, isMuted.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool isUserLocallyMuted(int uid) {
    final b = _bridge;
    if (b == null) return false;
    try {
      final res = b.callMethod<JSAny?>('isUserLocallyMuted'.toJS, uid.toJS);
      if (res != null && res.isA<JSBoolean>()) {
        return (res as JSBoolean).toDart;
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<bool> setDeafen(bool isDeafened) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      b.callMethod<JSAny?>('setDeafen'.toJS, isDeafened.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool isDeafenActive() {
    final b = _bridge;
    if (b == null) return false;
    try {
      final res = b.callMethod<JSAny?>('isDeafenActive'.toJS);
      if (res != null && res.isA<JSBoolean>()) {
        return (res as JSBoolean).toDart;
      }
    } catch (_) {}
    return false;
  }
}
