/// Interactive Real-time Voice Channel view for Open Mic and Stage Room channels via Agora RTC (FR-11 / UC-06).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/voice/agora_voice_client.dart';
import '../../../models/channel_model.dart';
import '../../../providers/auth_provider.dart';

class VoiceChannelView extends StatefulWidget {
  final ChannelModel channel;
  final VoiceRoomStateModel? initialRoomState;
  final bool initialConnected;
  final String? currentUserId;

  const VoiceChannelView({
    super.key,
    required this.channel,
    this.initialRoomState,
    this.initialConnected = false,
    this.currentUserId,
  });

  @override
  State<VoiceChannelView> createState() => _VoiceChannelViewState();
}

class _VoiceChannelViewState extends State<VoiceChannelView> {
  final ApiClient _api = ApiClient();

  VoiceRoomStateModel? _roomState;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _rtcToken;
  int? _agoraUid;
  String? _errorMessage;
  Timer? _pollTimer;
  bool _isDeafened = false;
  final Map<int, double> _userVolumes = {};
  final Set<int> _localMutedUsers = {};
  String? _previousRole;
  bool? _previousServerMute;

  @override
  void initState() {
    super.initState();
    _roomState = widget.initialRoomState;
    _isConnected = widget.initialConnected;
    if (widget.initialRoomState == null) {
      _fetchRoomState();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) {
          _fetchRoomState();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant VoiceChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _isConnected = false;
      _rtcToken = null;
      _agoraUid = null;
      _errorMessage = null;
      AgoraVoiceClient.instance.leaveVoiceRoom();
      _fetchRoomState();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    AgoraVoiceClient.instance.leaveVoiceRoom();
    super.dispose();
  }

  String? _resolveCurrentUserId(BuildContext context) {
    if (widget.currentUserId != null) return widget.currentUserId;
    try {
      return context.read<AuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchRoomState() async {
    try {
      final res = await _api.dio.get(
        '/api/v1/channels/${widget.channel.id}/voice/state',
      );
      if (!mounted) return;
      if (res.data is Map<String, dynamic>) {
        final nextState = VoiceRoomStateModel.fromJson(
          res.data as Map<String, dynamic>,
        );
        final currentUserId = _resolveCurrentUserId(context);
        final myP = nextState.participants
            .where((p) => p.userId == currentUserId)
            .firstOrNull;
        if (myP != null && _isConnected) {
          if (_previousRole != null && _previousRole != myP.role) {
            AgoraVoiceClient.instance.enforceRole(myP.role);
          }
          if (myP.isMuted && _previousServerMute == false) {
            AgoraVoiceClient.instance.setLocalMute(true);
          }
          _previousRole = myP.role;
          _previousServerMute = myP.isMuted;
        }

        setState(() {
          _roomState = nextState;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleJoinVoiceRoom() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _api.dio.post(
        '/api/v1/channels/${widget.channel.id}/voice/token',
      );
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      final stateJson = data['room_state'];
      final appId = data['app_id']?.toString() ?? '';
      final channelName = data['channel_name']?.toString() ?? '';
      final rtcToken = data['rtc_token']?.toString() ?? '';
      final agoraUid = data['uid'] is int ? data['uid'] as int : null;
      final role = data['role']?.toString() ?? 'LISTENER';

      if (agoraUid != null && rtcToken.isNotEmpty) {
        await AgoraVoiceClient.instance.joinVoiceRoom(
          appId: appId,
          channelName: channelName,
          token: rtcToken,
          uid: agoraUid,
          role: role,
        );
      }

      setState(() {
        _rtcToken = rtcToken;
        _agoraUid = agoraUid;
        if (stateJson is Map<String, dynamic>) {
          _roomState = VoiceRoomStateModel.fromJson(stateJson);
        }
        _isConnected = true;
        _isLoading = false;
        _previousRole = role;
        _previousServerMute = role != 'SPEAKER';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể kết nối vào phòng thoại.';
      setState(() {
        _errorMessage = detail ?? 'Không thể kết nối vào phòng thoại.';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi kết nối máy chủ thoại.';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLeaveVoiceRoom() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await AgoraVoiceClient.instance.leaveVoiceRoom();
      final res = await _api.dio.post(
        '/api/v1/channels/${widget.channel.id}/voice/leave',
      );
      if (!mounted) return;
      setState(() {
        if (res.data is Map<String, dynamic>) {
          _roomState = VoiceRoomStateModel.fromJson(
            res.data as Map<String, dynamic>,
          );
        }
        _isConnected = false;
        _rtcToken = null;
        _agoraUid = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleToggleSelfMute(bool nextMuted) async {
    try {
      await AgoraVoiceClient.instance.setLocalMute(nextMuted);
      final res = await _api.dio.put(
        '/api/v1/channels/${widget.channel.id}/voice/me/mute',
        data: {'is_muted': nextMuted},
      );
      if (!mounted) return;
      if (res.data is Map<String, dynamic>) {
        setState(() {
          _roomState = VoiceRoomStateModel.fromJson(
            res.data as Map<String, dynamic>,
          );
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể thay đổi trạng thái Mic.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể thay đổi trạng thái Mic.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleToggleRaiseHand(bool nextRaised) async {
    try {
      final res = await _api.dio.post(
        '/api/v1/channels/${widget.channel.id}/voice/raise-hand',
        data: {'raised': nextRaised},
      );
      if (!mounted) return;
      if (res.data is Map<String, dynamic>) {
        setState(() {
          _roomState = VoiceRoomStateModel.fromJson(
            res.data as Map<String, dynamic>,
          );
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể gửi yêu cầu giơ tay.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể gửi yêu cầu giơ tay.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleManageSpeaker(
    String targetUserId, {
    String? role,
    bool? isMuted,
  }) async {
    try {
      final res = await _api.dio.put(
        '/api/v1/channels/${widget.channel.id}/voice/speakers/$targetUserId',
        data: {
          'role': ?role,
          'is_muted': ?isMuted,
        },
      );
      if (!mounted) return;
      if (res.data is Map<String, dynamic>) {
        setState(() {
          _roomState = VoiceRoomStateModel.fromJson(
            res.data as Map<String, dynamic>,
          );
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể cập nhật quyền người phát biểu.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể cập nhật quyền người phát biểu.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleMuteAll() async {
    try {
      final res = await _api.dio.post(
        '/api/v1/channels/${widget.channel.id}/voice/mute-all',
      );
      if (!mounted) return;
      if (res.data is Map<String, dynamic>) {
        setState(() {
          _roomState = VoiceRoomStateModel.fromJson(
            res.data as Map<String, dynamic>,
          );
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã tắt mic toàn bộ thành viên trong phòng thoại.'),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể tắt mic toàn phòng.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể tắt mic toàn phòng.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleToggleDeafen() async {
    final nextDeafen = !_isDeafened;
    await AgoraVoiceClient.instance.setDeafen(nextDeafen);
    if (!mounted) return;
    setState(() {
      _isDeafened = nextDeafen;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextDeafen
              ? 'Đã tắt âm thanh toàn phòng (Deafen).'
              : 'Đã bật lại âm thanh phòng.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showUserAudioDialog(
    VoiceParticipantModel participant, {
    required bool isMe,
    required bool canModerate,
    required bool isStage,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        double currentVol = _userVolumes[participant.agoraUid] ??
            AgoraVoiceClient.instance.getUserVolume(participant.agoraUid);
        bool isLocallyMuted = _localMutedUsers.contains(participant.agoraUid) ||
            AgoraVoiceClient.instance.isUserLocallyMuted(participant.agoraUid);

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.palette.surface,
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.16),
                    backgroundImage: participant.avatarUrl != null
                        ? NetworkImage(participant.avatarUrl!)
                        : null,
                    child: participant.avatarUrl == null
                        ? Text(
                            (participant.displayName.isNotEmpty
                                    ? participant.displayName
                                    : '?')
                                .characters
                                .first
                                .toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          participant.displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          participant.isOwner
                              ? 'Chủ Fandom'
                              : (participant.isSpeaker ? 'Diễn giả' : 'Thính giả'),
                          style: TextStyle(
                            fontSize: 11,
                            color: participant.isSpeaker
                                ? AppTheme.success
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe) ...[
                      // 1. Personal Volume Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Âm lượng đối với bạn:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${currentVol.toInt()}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: currentVol > 100
                                  ? Colors.amber
                                  : AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        key: Key('slider_voice_volume_${participant.userId}'),
                        value: currentVol,
                        min: 0.0,
                        max: 200.0,
                        divisions: 40,
                        label: '${currentVol.toInt()}%',
                        activeColor: currentVol > 100
                            ? Colors.amber
                            : AppTheme.primary,
                        onChanged: (val) {
                          setDialogState(() => currentVol = val);
                          setState(() {
                            _userVolumes[participant.agoraUid] = val;
                          });
                          AgoraVoiceClient.instance.setUserVolume(
                            participant.agoraUid,
                            val,
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // 2. Local 1-way Mute
                      SwitchListTile(
                        key: Key('switch_voice_local_mute_${participant.userId}'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Tắt âm người này với tôi',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Chỉ bạn không nghe thấy, cả phòng vẫn nghe',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        value: isLocallyMuted,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppTheme.error,
                        onChanged: (val) {
                          setDialogState(() => isLocallyMuted = val);
                          setState(() {
                            if (val) {
                              _localMutedUsers.add(participant.agoraUid);
                            } else {
                              _localMutedUsers.remove(participant.agoraUid);
                            }
                          });
                          AgoraVoiceClient.instance.setLocalUserMuted(
                            participant.agoraUid,
                            val,
                          );
                        },
                      ),
                      const Divider(height: 24),
                    ],

                    // 3. Server Moderation Controls (Host / Mod only)
                    if (canModerate && !participant.isOwner && !isMe) ...[
                      const Text(
                        'Quản trị viên (Cả phòng thoại):',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (participant.isSpeaker) ...[
                        ElevatedButton.icon(
                          key: Key('btn_voice_server_mute_${participant.userId}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.warning,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(38),
                          ),
                          icon: const Icon(Icons.mic_off, size: 16),
                          label: const Text(
                            'Tắt mic thành viên này (Server)',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _handleManageSpeaker(participant.userId, isMuted: true);
                          },
                        ),
                        const SizedBox(height: 8),
                        if (isStage)
                          ElevatedButton.icon(
                            key: Key('btn_voice_demote_listener_${participant.userId}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(38),
                            ),
                            icon: const Icon(Icons.arrow_downward, size: 16),
                            label: const Text(
                              'Hạ xuống Khán giả (Tắt hẳn quyền nói)',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _handleManageSpeaker(
                                participant.userId,
                                role: 'LISTENER',
                                isMuted: true,
                              );
                            },
                          ),
                      ] else if (isStage) ...[
                        ElevatedButton.icon(
                          key: Key('btn_voice_promote_speaker_${participant.userId}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(38),
                          ),
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          label: const Text(
                            'Mời lên làm Diễn giả (Cấp quyền nói)',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _handleManageSpeaker(
                              participant.userId,
                              role: 'SPEAKER',
                              isMuted: false,
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isStage =
        (_roomState?.voiceRoomType ?? widget.channel.voiceRoomType) ==
        'STAGE_ROOM';
    final canModerate =
        widget.channel.canModerateChat || widget.channel.canManageChannel;
    final myUserId = _resolveCurrentUserId(context);
    final participants = _roomState?.participants ?? const [];
    final myParticipant = myUserId != null
        ? participants.where((p) => p.userId == myUserId).firstOrNull
        : null;
    final speakers = _roomState?.speakers ?? const [];
    final listeners = _roomState?.listeners ?? const [];
    final raisedHandParticles = participants
        .where(
          (p) =>
              p.isHandRaised ||
              (_roomState?.raisedHandUserIds.contains(p.userId) ?? false),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Voice Room Status Banner Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.14),
                          child: Icon(
                            isStage ? Icons.podcasts : Icons.headset_mic_outlined,
                            size: 30,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    widget.channel.name,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (isStage
                                              ? Colors.amber
                                              : AppTheme.success)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isStage
                                          ? 'Sân khấu (Stage Room)'
                                          : 'Đàm thoại tự do (Open Mic)',
                                      style: TextStyle(
                                        color: isStage
                                            ? Colors.amber
                                            : AppTheme.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          AppTheme.primary.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      widget.channel.maxMembers > 0
                                          ? '${participants.length}/${widget.channel.maxMembers} đang kết nối'
                                          : '${participants.length} đang kết nối',
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isStage
                                    ? 'Chế độ Sân khấu (Agora RTC Opus): Thính giả cần giơ tay để được Chủ Fandom / Mod duyệt lên sân khấu phát biểu.'
                                    : 'Chế độ Đàm thoại tự do (Agora RTC Opus): Thành viên có quyền thoại có thể bật mic trò chuyện trực tiếp.',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    if (_rtcToken != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.graphic_eq,
                              size: 16,
                              color: AppTheme.success,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Đã kết nối Agora RTC Cloud (UID: ${_agoraUid ?? 0})',
                                style: const TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        if (!_isConnected) ...[
                          if (widget.channel.canConnectVoice)
                            ElevatedButton.icon(
                              key: const Key('btn_voice_join'),
                              onPressed: _isLoading ? null : _handleJoinVoiceRoom,
                              icon: const Icon(Icons.call_outlined),
                              label: Text(
                                widget.channel.canSpeakVoice
                                    ? 'Tham gia phòng thoại (Có quyền bật Mic)'
                                    : 'Tham gia với tư cách Thính giả',
                              ),
                            )
                          else
                            const Text(
                              'Bạn không có quyền kết nối vào phòng thoại này.',
                              style: TextStyle(
                                color: AppTheme.error,
                                fontSize: 13,
                              ),
                            ),
                        ] else ...[
                          if (myParticipant == null || myParticipant.isSpeaker)
                            ElevatedButton.icon(
                              key: const Key('btn_voice_toggle_mic'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    (myParticipant?.isMuted ?? false)
                                        ? palette.surfaceElevated
                                        : AppTheme.success,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _handleToggleSelfMute(
                                !(myParticipant?.isMuted ?? false),
                              ),
                              icon: Icon(
                                (myParticipant?.isMuted ?? false)
                                    ? Icons.mic_off_outlined
                                    : Icons.mic_none_rounded,
                              ),
                              label: Text(
                                (myParticipant?.isMuted ?? false)
                                    ? 'Bật Mic'
                                    : 'Đang mở Mic (Nhấn để tắt)',
                              ),
                            ),
                          OutlinedButton.icon(
                            key: const Key('btn_voice_toggle_deafen'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _isDeafened
                                  ? AppTheme.error
                                  : palette.textPrimary,
                              side: BorderSide(
                                color: _isDeafened
                                    ? AppTheme.error
                                    : palette.border,
                              ),
                            ),
                            onPressed: _handleToggleDeafen,
                            icon: Icon(
                              _isDeafened
                                  ? Icons.headset_off_outlined
                                  : Icons.headset_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _isDeafened
                                  ? 'Bật loa phòng'
                                  : 'Tắt loa phòng (Deafen)',
                            ),
                          ),
                          if (isStage &&
                              myParticipant != null &&
                              !myParticipant.isSpeaker)
                            OutlinedButton.icon(
                              key: const Key('btn_voice_raise_hand'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber,
                                side: const BorderSide(color: Colors.amber),
                              ),
                              onPressed: () => _handleToggleRaiseHand(
                                !myParticipant.isHandRaised,
                              ),
                              icon: Icon(
                                myParticipant.isHandRaised
                                    ? Icons.pan_tool
                                    : Icons.pan_tool_outlined,
                                size: 18,
                              ),
                              label: Text(
                                myParticipant.isHandRaised
                                    ? 'Hạ tay'
                                    : 'Giơ tay xin phát biểu',
                              ),
                            ),
                          if (canModerate)
                            OutlinedButton.icon(
                              key: const Key('btn_voice_mute_all'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.warning,
                                side: const BorderSide(color: AppTheme.warning),
                              ),
                              onPressed: _handleMuteAll,
                              icon: const Icon(Icons.volume_off_outlined, size: 18),
                              label: const Text('Tắt mic toàn phòng'),
                            ),
                          ElevatedButton.icon(
                            key: const Key('btn_voice_leave'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _isLoading ? null : _handleLeaveVoiceRoom,
                            icon: const Icon(Icons.call_end_outlined, size: 18),
                            label: const Text('Rời phòng'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Raise Hand Queue (For Stage Room Moderators & Viewers)
              if (isStage && raisedHandParticles.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.pan_tool_rounded,
                            size: 18,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Hàng đợi Giơ tay xin phát biểu (${raisedHandParticles.length})',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: raisedHandParticles.map((p) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: palette.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  p.displayName,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                if (canModerate) ...[
                                  const SizedBox(width: 10),
                                  TextButton.icon(
                                    key: Key(
                                      'btn_voice_approve_speaker_${p.userId}',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.success,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    onPressed: () => _handleManageSpeaker(
                                      p.userId,
                                      role: 'SPEAKER',
                                      isMuted: false,
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Mời lên sân khấu',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 3. Speakers Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.record_voice_over_outlined,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'NGƯỜI PHÁT BIỂU (${speakers.length})',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (speakers.isEmpty)
                      Text(
                        'Chưa có người phát biểu nào trên sân khấu.',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: speakers
                            .map(
                              (p) => _buildParticipantCard(
                                context,
                                p,
                                canModerate: canModerate,
                                isStage: isStage,
                              ),
                            )
                            .toList(),
                      ),
                    if (listeners.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Divider(color: palette.border, height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.headphones_outlined,
                            size: 18,
                            color: palette.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'THÍNH GIẢ ĐANG NGHE (${listeners.length})',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: listeners
                            .map(
                              (p) => _buildParticipantCard(
                                context,
                                p,
                                canModerate: canModerate,
                                isStage: isStage,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantCard(
    BuildContext context,
    VoiceParticipantModel participant, {
    required bool canModerate,
    required bool isStage,
  }) {
    final palette = context.palette;
    final isSpeakingActive = participant.isSpeaker && !participant.isMuted;

    final myUserId = _resolveCurrentUserId(context);
    final isMe = participant.userId == myUserId;
    final isLocallyMuted = _localMutedUsers.contains(participant.agoraUid) ||
        AgoraVoiceClient.instance.isUserLocallyMuted(participant.agoraUid);

    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSpeakingActive ? AppTheme.success : palette.border,
          width: isSpeakingActive ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.16),
                backgroundImage: participant.avatarUrl != null
                    ? NetworkImage(participant.avatarUrl!)
                    : null,
                child: participant.avatarUrl == null
                    ? Text(
                        (participant.displayName.isNotEmpty
                                ? participant.displayName
                                : '?')
                            .characters
                            .first
                            .toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: participant.isHandRaised
                      ? Colors.amber
                      : (participant.isMuted
                          ? AppTheme.error
                          : AppTheme.success),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  participant.isHandRaised
                      ? Icons.pan_tool_rounded
                      : (participant.isMuted ? Icons.mic_off : Icons.mic),
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            participant.isOwner
                ? 'Chủ Fandom'
                : (participant.isSpeaker ? 'Diễn giả' : 'Thính giả'),
            style: TextStyle(
              color: participant.isOwner
                  ? Colors.amber
                  : palette.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: 2,
            children: [
              IconButton(
                key: Key('btn_voice_audio_settings_${participant.userId}'),
                tooltip: isMe
                    ? 'Cài đặt âm lượng'
                    : (isLocallyMuted
                        ? 'Đang tắt âm người này với bạn (Bấm để mở)'
                        : 'Cài đặt âm lượng & Tắt âm 1 phía'),
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  isLocallyMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_outlined,
                  size: 16,
                  color: isLocallyMuted ? AppTheme.error : palette.textSecondary,
                ),
                onPressed: () => _showUserAudioDialog(
                  participant,
                  isMe: isMe,
                  canModerate: canModerate,
                  isStage: isStage,
                ),
              ),
              if (canModerate && !participant.isOwner && !isMe) ...[
                if (participant.isSpeaker && !participant.isMuted)
                  IconButton(
                    key: Key('btn_voice_quick_mute_${participant.userId}'),
                    tooltip: 'Tắt mic thành viên này (Server)',
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.mic_off_outlined,
                      size: 16,
                      color: AppTheme.warning,
                    ),
                    onPressed: () => _handleManageSpeaker(
                      participant.userId,
                      isMuted: true,
                    ),
                  ),
                if (isStage && participant.isSpeaker)
                  IconButton(
                    key: Key('btn_voice_quick_demote_${participant.userId}'),
                    tooltip: 'Hạ xuống làm Thính giả (Tước quyền nói)',
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: AppTheme.error,
                    ),
                    onPressed: () => _handleManageSpeaker(
                      participant.userId,
                      role: 'LISTENER',
                      isMuted: true,
                    ),
                  ),
                if (isStage && !participant.isSpeaker)
                  IconButton(
                    key: Key('btn_voice_quick_promote_${participant.userId}'),
                    tooltip: 'Mời lên làm Diễn giả',
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: AppTheme.success,
                    ),
                    onPressed: () => _handleManageSpeaker(
                      participant.userId,
                      role: 'SPEAKER',
                      isMuted: false,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
