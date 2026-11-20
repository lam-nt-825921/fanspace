/**
 * FanSpace Real-time Voice Room Audio Bridge (FR-11 / UC-06).
 *
 * Coordinates Agora RTC Web SDK (`agora-rtc-sdk-ng`) for Flutter Web.
 * Provides:
 * - Live microphone capture & audio publishing for SPEAKERS
 * - Audio playback & subscription for remote participants
 * - Per-user volume slider (0% to 200%)
 * - Local 1-way mute (Mute target speaker for self only)
 * - Deafen mode (Mute all incoming audio for self)
 * - Server moderation enforcement (Instant unpublish on demotion to LISTENER)
 */

(function () {
  const agoraVoiceBridge = {
    client: null,
    localAudioTrack: null,
    remoteUsers: {},
    userVolumes: {}, // uid (int) -> volume (0..200, default 100)
    localMutedUsers: {}, // uid (int) -> boolean
    isDeafened: false,
    currentRole: "LISTENER",
    currentUid: null,
    currentChannel: null,
    isJoined: false,

    isSupported: function () {
      return typeof AgoraRTC !== "undefined";
    },

    joinVoiceRoom: async function (appId, channelName, token, uid, role) {
      if (!this.isSupported()) {
        console.warn("[AgoraVoiceBridge] AgoraRTC SDK is not loaded.");
        return { success: false, error: "AgoraRTC SDK not loaded" };
      }

      if (this.isJoined) {
        await this.leaveVoiceRoom();
      }

      try {
        this.client = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });
        this.currentRole = (role || "LISTENER").toUpperCase();
        this.currentUid = uid;
        this.currentChannel = channelName;

        // Remote streams listener
        this.client.on("user-published", async (user, mediaType) => {
          try {
            await this.client.subscribe(user, mediaType);
            if (mediaType === "audio" && user.audioTrack) {
              this.remoteUsers[user.uid] = user;
              this.applyUserVolume(user.uid);
              user.audioTrack.play();
              console.log("[AgoraVoiceBridge] Playing audio for remote UID:", user.uid);
            }
          } catch (subErr) {
            console.error("[AgoraVoiceBridge] Failed to subscribe remote audio:", subErr);
          }
        });

        this.client.on("user-unpublished", (user, mediaType) => {
          if (mediaType === "audio" && user.audioTrack) {
            user.audioTrack.stop();
          }
        });

        this.client.on("user-left", (user) => {
          delete this.remoteUsers[user.uid];
        });

        this.client.on("token-privilege-will-expire", () => {
          console.warn("[AgoraVoiceBridge] Dynamic RTC token privilege will expire soon.");
        });

        // Join Agora RTC channel
        await this.client.join(appId, channelName, token, uid);
        this.isJoined = true;
        console.log(`[AgoraVoiceBridge] Joined room '${channelName}' as UID ${uid} (${this.currentRole})`);

        // If SPEAKER, capture mic and publish
        if (this.currentRole === "SPEAKER") {
          await this._startLocalAudioPublishing();
        }

        return { success: true, uid: uid };
      } catch (err) {
        console.error("[AgoraVoiceBridge] joinVoiceRoom error:", err);
        this.isJoined = false;
        return { success: false, error: String(err) };
      }
    },

    _startLocalAudioPublishing: async function () {
      if (!this.client || !this.isJoined) return;
      try {
        if (!this.localAudioTrack) {
          this.localAudioTrack = await AgoraRTC.createMicrophoneAudioTrack({
            AEC: true, // Acoustic Echo Cancellation
            ANS: true, // Automatic Noise Suppression
            AGC: true, // Automatic Gain Control
          });
        }
        await this.client.publish([this.localAudioTrack]);
        console.log("[AgoraVoiceBridge] Published local microphone track to channel.");
      } catch (micErr) {
        console.warn("[AgoraVoiceBridge] Microphone capture failed (permission denied or no mic):", micErr);
      }
    },

    leaveVoiceRoom: async function () {
      try {
        if (this.localAudioTrack) {
          try {
            this.localAudioTrack.stop();
            this.localAudioTrack.close();
          } catch (_) {}
          this.localAudioTrack = null;
        }

        if (this.client) {
          try {
            await this.client.leave();
          } catch (_) {}
          this.client = null;
        }

        this.remoteUsers = {};
        this.isJoined = false;
        this.currentUid = null;
        this.currentChannel = null;
        console.log("[AgoraVoiceBridge] Left voice room.");
        return { success: true };
      } catch (err) {
        console.error("[AgoraVoiceBridge] leaveVoiceRoom error:", err);
        return { success: false, error: String(err) };
      }
    },

    setLocalMute: async function (isMuted) {
      if (!this.localAudioTrack) return { success: false, error: "No local track" };
      try {
        await this.localAudioTrack.setEnabled(!isMuted);
        console.log(`[AgoraVoiceBridge] Local microphone enabled = ${!isMuted}`);
        return { success: true, isMuted: !!isMuted };
      } catch (err) {
        console.error("[AgoraVoiceBridge] setLocalMute error:", err);
        return { success: false, error: String(err) };
      }
    },

    enforceRole: async function (newRole) {
      const normalizedRole = (newRole || "LISTENER").toUpperCase();
      this.currentRole = normalizedRole;

      if (normalizedRole === "LISTENER") {
        // Demoted to Listener -> unpublish and destroy local microphone track immediately
        if (this.localAudioTrack) {
          try {
            await this.localAudioTrack.setEnabled(false);
            if (this.client && this.isJoined) {
              await this.client.unpublish([this.localAudioTrack]);
            }
            this.localAudioTrack.stop();
            this.localAudioTrack.close();
          } catch (_) {}
          this.localAudioTrack = null;
          console.log("[AgoraVoiceBridge] Demoted to LISTENER: Unpublished microphone.");
        }
      } else if (normalizedRole === "SPEAKER") {
        // Promoted to Speaker -> start publishing
        if (!this.localAudioTrack && this.client && this.isJoined) {
          await this._startLocalAudioPublishing();
        }
      }
      return { success: true, role: normalizedRole };
    },

    // ------------------------------------------------------------------------
    // Audio Output Controls (Volume, Local Mute, Deafen)
    // ------------------------------------------------------------------------

    applyUserVolume: function (uid) {
      const user = this.remoteUsers[uid];
      if (!user || !user.audioTrack) return;

      if (this.isDeafened || this.localMutedUsers[uid]) {
        user.audioTrack.setVolume(0);
      } else {
        const vol = this.userVolumes[uid] !== undefined ? this.userVolumes[uid] : 100;
        user.audioTrack.setVolume(Math.max(0, Math.min(200, Math.round(vol))));
      }
    },

    setUserVolume: function (uid, volumePercent) {
      const vol = Math.max(0, Math.min(200, Number(volumePercent) || 0));
      this.userVolumes[uid] = vol;
      this.applyUserVolume(uid);
      console.log(`[AgoraVoiceBridge] Set user volume for UID ${uid} to ${vol}%`);
      return { success: true, uid: uid, volume: vol };
    },

    getUserVolume: function (uid) {
      if (this.userVolumes[uid] !== undefined) {
        return this.userVolumes[uid];
      }
      return 100;
    },

    setLocalUserMuted: function (uid, isMuted) {
      this.localMutedUsers[uid] = !!isMuted;
      this.applyUserVolume(uid);
      console.log(`[AgoraVoiceBridge] Set local mute for UID ${uid} = ${!!isMuted}`);
      return { success: true, uid: uid, isMuted: !!isMuted };
    },

    isUserLocallyMuted: function (uid) {
      return !!this.localMutedUsers[uid];
    },

    setDeafen: function (isDeafened) {
      this.isDeafened = !!isDeafened;
      Object.keys(this.remoteUsers).forEach((uid) => {
        this.applyUserVolume(uid);
      });
      console.log(`[AgoraVoiceBridge] Set deafen mode = ${this.isDeafened}`);
      return { success: true, isDeafened: this.isDeafened };
    },

    isDeafenActive: function () {
      return this.isDeafened;
    },

    getState: function () {
      return {
        isJoined: this.isJoined,
        currentRole: this.currentRole,
        currentUid: this.currentUid,
        currentChannel: this.currentChannel,
        isDeafened: this.isDeafened,
        remoteCount: Object.keys(this.remoteUsers).length,
      };
    },
  };

  window.agoraVoiceBridge = agoraVoiceBridge;
})();
