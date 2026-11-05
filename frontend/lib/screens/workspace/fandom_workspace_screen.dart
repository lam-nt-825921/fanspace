/// Fandom internal workspace screen featuring Welcome, Rules, and real-time Channel Chat.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/channel_model.dart';
import '../../models/fandom_model.dart';
import '../../models/message_model.dart';
import '../../providers/fandom_provider.dart';

/// Active navigation section inside the Fandom workspace.
enum WorkspaceSection {
  welcome,
  rules,
  channel,
}

/// Callback signature for overriding message sending in widget tests.
typedef SendMessageOverride = Future<MessageModel> Function(
  String channelId,
  String content,
  List<MessageAttachmentModel> attachments,
);

/// Interactive internal workspace for an active Fandom member or owner.
class FandomWorkspaceScreen extends StatefulWidget {
  final String slug;
  final FandomDetailModel? initialFandom;
  final FandomChannelsDataModel? initialChannelsData;
  final Map<String, List<MessageModel>>? initialMessagesByChannel;
  final SendMessageOverride? onSendMessageOverride;

  const FandomWorkspaceScreen({
    super.key,
    required this.slug,
    this.initialFandom,
    this.initialChannelsData,
    this.initialMessagesByChannel,
    this.onSendMessageOverride,
  });

  @override
  State<FandomWorkspaceScreen> createState() => _FandomWorkspaceScreenState();
}

class _FandomWorkspaceScreenState extends State<FandomWorkspaceScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();

  FandomDetailModel? _fandom;
  FandomChannelsDataModel? _channelsData;
  WorkspaceSection _activeSection = WorkspaceSection.welcome;
  ChannelModel? _selectedChannel;
  bool _rulesAcknowledged = false;
  bool _isLoading = true;
  String? _errorMessage;

  final Map<String, List<MessageModel>> _messagesByChannel = {};
  final Map<String, bool> _hasMoreByChannel = {};
  final Map<String, String?> _nextCursorByChannel = {};
  bool _isLoadingMessages = false;
  bool _isSendingMessage = false;
  bool _isUploadingAttachment = false;
  final List<MessageAttachmentModel> _pendingAttachments = [];
  MessageModel? _replyingToMessage;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialMessagesByChannel != null) {
      for (final entry in widget.initialMessagesByChannel!.entries) {
        _messagesByChannel[entry.key] = List<MessageModel>.from(entry.value);
      }
    }
    if (widget.initialFandom != null && widget.initialChannelsData != null) {
      _fandom = widget.initialFandom;
      _channelsData = widget.initialChannelsData;
      _isLoading = false;
    } else {
      _loadWorkspaceData();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaceData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fandomRes =
          await _api.dio.get('/api/v1/fandoms/${widget.slug}/preview');
      final channelsRes =
          await _api.dio.get('/api/v1/fandoms/${widget.slug}/channels');

      if (!mounted) return;
      final fandom = FandomDetailModel.fromJson(
        fandomRes.data as Map<String, dynamic>,
      );
      final channelsData = FandomChannelsDataModel.fromJson(
        channelsRes.data as Map<String, dynamic>,
      );

      setState(() {
        _fandom = fandom;
        _channelsData = channelsData;
        if (_selectedChannel != null) {
          final updated = channelsData.channels
              .where((c) => c.id == _selectedChannel!.id)
              .firstOrNull;
          _selectedChannel = updated;
          if (updated == null && _activeSection == WorkspaceSection.channel) {
            _activeSection = WorkspaceSection.welcome;
          }
        }
        _isLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : null;
      setState(() {
        _errorMessage = detail ??
            'Không thể tải dữ liệu không gian Fandom. Vui lòng thử lại.';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Đã xảy ra lỗi kết nối máy chủ.';
        _isLoading = false;
      });
    }
  }

  void _selectChannel(ChannelModel channel) {
    setState(() {
      _selectedChannel = channel;
      _activeSection = WorkspaceSection.channel;
      _pendingAttachments.clear();
      _replyingToMessage = null;
    });

    _pollingTimer?.cancel();
    if (channel.type == 'TEXT') {
      if (widget.initialFandom == null &&
          !_messagesByChannel.containsKey(channel.id)) {
        _fetchChannelMessages(channel.id, refresh: true);
      }
      if (widget.initialFandom == null) {
        _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (mounted &&
              _activeSection == WorkspaceSection.channel &&
              _selectedChannel?.id == channel.id &&
              !_isSendingMessage) {
            _pollLatestMessages(channel.id);
          }
        });
      }
    }
  }

  Future<void> _fetchChannelMessages(
    String channelId, {
    bool refresh = false,
    String? beforeId,
  }) async {
    if (_isLoadingMessages) return;
    setState(() {
      _isLoadingMessages = true;
    });

    try {
      final res = await _api.dio.get(
        '/api/v1/channels/$channelId/messages',
        queryParameters: {
          'limit': 30,
          'before_id': ?beforeId,
        },
      );
      if (!mounted) return;

      final page = MessageListResponseModel.fromJson(
        res.data as Map<String, dynamic>,
      );

      setState(() {
        if (refresh || beforeId == null) {
          _messagesByChannel[channelId] = page.messages;
        } else {
          final existing = _messagesByChannel[channelId] ?? const [];
          final existingIds = existing.map((m) => m.id).toSet();
          final older =
              page.messages.where((m) => !existingIds.contains(m.id)).toList();
          _messagesByChannel[channelId] = [...older, ...existing];
        }
        _hasMoreByChannel[channelId] = page.hasMore;
        _nextCursorByChannel[channelId] = page.nextCursor;
        _isLoadingMessages = false;
      });

      if (refresh) {
        _scrollToBottom();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMessages = false;
      });
    }
  }

  Future<void> _pollLatestMessages(String channelId) async {
    try {
      final res = await _api.dio.get(
        '/api/v1/channels/$channelId/messages',
        queryParameters: {'limit': 30},
      );
      if (!mounted) return;
      final page = MessageListResponseModel.fromJson(
        res.data as Map<String, dynamic>,
      );
      final current = List<MessageModel>.from(
        _messagesByChannel[channelId] ?? const [],
      );
      final incomingById = {for (final m in page.messages) m.id: m};
      bool hasChanges = false;

      for (var i = 0; i < current.length; i++) {
        final updated = incomingById[current[i].id];
        if (updated != null &&
            (updated.updatedAt != current[i].updatedAt ||
                updated.isEdited != current[i].isEdited ||
                updated.isRecalled != current[i].isRecalled ||
                updated.isPinned != current[i].isPinned ||
                updated.reactions.length != current[i].reactions.length)) {
          current[i] = updated;
          hasChanges = true;
        }
      }

      final currentIds = current.map((m) => m.id).toSet();
      final brandNew =
          page.messages.where((m) => !currentIds.contains(m.id)).toList();
      if (brandNew.isNotEmpty) {
        current.addAll(brandNew);
        hasChanges = true;
      }

      if (hasChanges) {
        setState(() {
          _messagesByChannel[channelId] = current;
        });
        if (brandNew.isNotEmpty) {
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  void _replaceMessageInChannel(String channelId, MessageModel updated) {
    final list = List<MessageModel>.from(
      _messagesByChannel[channelId] ?? const [],
    );
    final idx = list.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      list[idx] = updated;
      setState(() {
        _messagesByChannel[channelId] = list;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageScrollController.hasClients) {
        _messageScrollController.animateTo(
          _messageScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handlePickAndUploadAttachment() async {
    if (_isUploadingAttachment || _pendingAttachments.length >= 5) return;

    final file = await FilePicker.pickFile(
      type: FileType.image,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;

    setState(() {
      _isUploadingAttachment = true;
    });

    try {
      final formData = FormData.fromMap({
        'target': 'CHAT_ATTACHMENT',
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
        ),
      });

      final res = await _api.dio.post('/api/v1/media/upload', data: formData);
      if (!mounted) return;
      final url = res.data['url']?.toString();
      if (url != null && url.isNotEmpty) {
        setState(() {
          _pendingAttachments.add(
            MessageAttachmentModel(
              url: url,
              type: 'IMAGE',
              filename: file.name,
            ),
          );
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể tải tệp đính kèm lên.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể tải tệp đính kèm lên.'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAttachment = false;
        });
      }
    }
  }

  Future<void> _handleSendMessage(ChannelModel channel) async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingAttachments.isEmpty) || _isSendingMessage) {
      return;
    }

    final attachmentsToSend =
        List<MessageAttachmentModel>.from(_pendingAttachments);
    final replyToId = _replyingToMessage?.id;

    setState(() {
      _isSendingMessage = true;
    });

    try {
      MessageModel created;
      if (widget.onSendMessageOverride != null) {
        created = await widget.onSendMessageOverride!(
          channel.id,
          text,
          attachmentsToSend,
        );
      } else {
        final res = await _api.dio.post(
          '/api/v1/channels/${channel.id}/messages',
          data: {
            'content': text,
            'attachments': attachmentsToSend.map((a) => a.toJson()).toList(),
            'reply_to_id': ?replyToId,
          },
        );
        created = MessageModel.fromJson(res.data as Map<String, dynamic>);
      }

      if (!mounted) return;
      setState(() {
        final list = List<MessageModel>.from(
          _messagesByChannel[channel.id] ?? const [],
        );
        if (!list.any((m) => m.id == created.id)) {
          list.add(created);
        }
        _messagesByChannel[channel.id] = list;
        _messageController.clear();
        _pendingAttachments.clear();
        _replyingToMessage = null;
        _isSendingMessage = false;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể gửi tin nhắn.';
      setState(() {
        _isSendingMessage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể gửi tin nhắn.'),
          backgroundColor: AppTheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  Future<void> _handleToggleReaction(
    ChannelModel channel,
    MessageModel message,
    String emoji,
  ) async {
    try {
      final res = await _api.dio.post(
        '/api/v1/channels/${channel.id}/messages/${message.id}/reactions',
        data: {'emoji': emoji},
      );
      if (!mounted) return;
      final updated = MessageModel.fromJson(res.data as Map<String, dynamic>);
      _replaceMessageInChannel(channel.id, updated);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể thả biểu cảm.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể thả biểu cảm.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _showEditMessageDialog(
    ChannelModel channel,
    MessageModel message,
  ) async {
    final editCtrl = TextEditingController(text: message.content);
    String? dialogError;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: AppTheme.darkTheme,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text(
                'Chỉnh sửa tin nhắn',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null) ...[
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: editCtrl,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nội dung tin nhắn',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final trimmed = editCtrl.text.trim();
                          if (trimmed.isEmpty) {
                            setDialogState(() {
                              dialogError =
                                  'Nội dung tin nhắn không được để trống.';
                            });
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });
                          try {
                            final res = await _api.dio.put(
                              '/api/v1/channels/${channel.id}/messages/${message.id}',
                              data: {'content': trimmed},
                            );
                            final updated = MessageModel.fromJson(
                              res.data as Map<String, dynamic>,
                            );
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            _replaceMessageInChannel(channel.id, updated);
                          } on DioException catch (e) {
                            final detail = e.response?.data is Map
                                ? e.response?.data['detail']?.toString()
                                : 'Không thể chỉnh sửa tin nhắn.';
                            setDialogState(() {
                              dialogError =
                                  detail ?? 'Không thể chỉnh sửa tin nhắn.';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleRecallMessage(
    ChannelModel channel,
    MessageModel message,
  ) async {
    try {
      final res = await _api.dio.delete(
        '/api/v1/channels/${channel.id}/messages/${message.id}',
      );
      if (!mounted) return;
      final updated = MessageModel.fromJson(res.data as Map<String, dynamic>);
      _replaceMessageInChannel(channel.id, updated);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể thu hồi tin nhắn.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể thu hồi tin nhắn.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleTogglePinMessage(
    ChannelModel channel,
    MessageModel message,
  ) async {
    try {
      final res = await _api.dio.post(
        '/api/v1/channels/${channel.id}/messages/${message.id}/pin',
      );
      if (!mounted) return;
      final updated = MessageModel.fromJson(res.data as Map<String, dynamic>);
      _replaceMessageInChannel(channel.id, updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.isPinned
                ? 'Đã ghim tin nhắn vào kênh #${channel.name}.'
                : 'Đã bỏ ghim tin nhắn.',
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể cập nhật trạng thái ghim tin nhắn.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể cập nhật trạng thái ghim.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _showPinnedMessagesDialog(ChannelModel channel) async {
    final localPinned = (_messagesByChannel[channel.id] ?? const [])
        .where((m) => m.isPinned && !m.isRecalled)
        .toList();

    List<MessageModel> pinnedMessages = localPinned;
    if (widget.initialFandom == null) {
      try {
        final res = await _api.dio.get('/api/v1/channels/${channel.id}/pins');
        if (res.data is List) {
          pinnedMessages = (res.data as List)
              .whereType<Map<String, dynamic>>()
              .map(MessageModel.fromJson)
              .toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: AppTheme.darkTheme,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.push_pin, color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Tin nhắn đã ghim',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: pinnedMessages.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Chưa có tin nhắn nào được ghim trong kênh này.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: pinnedMessages.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: AppTheme.surfaceLight),
                      itemBuilder: (context, idx) {
                        final msg = pinnedMessages[idx];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            msg.sender.displayName,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            msg.content,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateOrEditChannelDialog({ChannelModel? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final topicCtrl = TextEditingController(text: existing?.topic ?? '');
    final slowModeCtrl = TextEditingController(
      text: (existing?.slowModeSeconds ?? 0).toString(),
    );
    String selectedType = existing?.type ?? 'TEXT';
    bool isAnnouncement = existing?.isAnnouncement ?? false;
    String voiceRoomType = existing?.voiceRoomType ?? 'OPEN_MIC';
    String? dialogError;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Theme(
          data: AppTheme.darkTheme,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                backgroundColor: AppTheme.surface,
                title: Text(
                  existing == null
                      ? 'Tạo kênh giao tiếp mới'
                      : 'Chỉnh sửa cấu hình kênh',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dialogError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              dialogError!,
                              style: const TextStyle(
                                color: AppTheme.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (existing == null) ...[
                          const Text(
                            'Loại kênh',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'TEXT',
                                icon: Icon(Icons.tag, size: 18),
                                label: Text('Kênh Văn bản'),
                              ),
                              ButtonSegment(
                                value: 'VOICE',
                                icon: Icon(Icons.volume_up_outlined, size: 18),
                                label: Text('Kênh Thoại'),
                              ),
                            ],
                            selected: {selectedType},
                            onSelectionChanged: (val) {
                              setDialogState(() {
                                selectedType = val.first;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: nameCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Tên kênh',
                            hintText: 'Ví dụ: chat-chung, góc-fanart',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: topicCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Chủ đề / Mô tả kênh',
                            hintText: 'Giới thiệu ngắn về mục đích của kênh',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (selectedType == 'TEXT') ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Kênh thông báo một chiều',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: const Text(
                              'Chỉ Chủ Fandom và Ban quản trị được phép gửi tin nhắn',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            value: isAnnouncement,
                            onChanged: (val) {
                              setDialogState(() => isAnnouncement = val);
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: slowModeCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText:
                                  'Giới hạn tốc độ nhắn tin (Slow-mode giây)',
                              hintText: '0 = Không giới hạn',
                            ),
                          ),
                        ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: voiceRoomType,
                          decoration: const InputDecoration(
                            labelText: 'Chế độ phòng thoại',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'OPEN_MIC',
                              child: Text('Đàm thoại tự do (Open Mic)'),
                            ),
                            DropdownMenuItem(
                              value: 'STAGE_ROOM',
                              child: Text(
                                'Sân khấu phát biểu (Stage Room - Giơ tay)',
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => voiceRoomType = val);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final trimmedName = nameCtrl.text.trim();
                          if (trimmedName.length < 2) {
                            setDialogState(() {
                              dialogError = 'Tên kênh phải có ít nhất 2 ký tự.';
                            });
                            return;
                          }
                          final slowSec =
                              int.tryParse(slowModeCtrl.text.trim()) ?? 0;

                          setDialogState(() {
                            isSubmitting = true;
                            dialogError = null;
                          });

                          try {
                            if (existing == null) {
                              final res = await _api.dio.post(
                                '/api/v1/fandoms/${widget.slug}/channels',
                                data: {
                                  'name': trimmedName,
                                  'type': selectedType,
                                  'topic': topicCtrl.text.trim().isEmpty
                                      ? null
                                      : topicCtrl.text.trim(),
                                  'is_announcement': selectedType == 'TEXT'
                                      ? isAnnouncement
                                      : false,
                                  'slow_mode_seconds':
                                      selectedType == 'TEXT' ? slowSec : 0,
                                  'voice_room_type': selectedType == 'VOICE'
                                      ? voiceRoomType
                                      : null,
                                },
                              );
                              final created = ChannelModel.fromJson(
                                res.data as Map<String, dynamic>,
                              );
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                              await _loadWorkspaceData();
                              _selectChannel(created);
                            } else {
                              final res = await _api.dio.put(
                                '/api/v1/fandoms/${widget.slug}/channels/${existing.id}',
                                data: {
                                  'name': trimmedName,
                                  'topic': topicCtrl.text.trim(),
                                  'is_announcement': selectedType == 'TEXT'
                                      ? isAnnouncement
                                      : null,
                                  'slow_mode_seconds':
                                      selectedType == 'TEXT' ? slowSec : null,
                                  'voice_room_type': selectedType == 'VOICE'
                                      ? voiceRoomType
                                      : null,
                                },
                              );
                              final updated = ChannelModel.fromJson(
                                res.data as Map<String, dynamic>,
                              );
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                              await _loadWorkspaceData();
                              _selectChannel(updated);
                            }
                          } on DioException catch (e) {
                            final detail = e.response?.data is Map
                                ? e.response?.data['detail']?.toString()
                                : null;
                            setDialogState(() {
                              dialogError = detail ?? 'Không thể lưu kênh.';
                              isSubmitting = false;
                            });
                          }
                        },
                  child: Text(existing == null ? 'Tạo kênh' : 'Lưu thay đổi'),
                ),
              ],
            );
          },
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteChannel(ChannelModel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: AppTheme.darkTheme,
        child: AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
            'Xác nhận xóa kênh',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Bạn có chắc chắn muốn xóa kênh "${channel.name}" không? Hành động này không thể hoàn tác.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Xóa kênh'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.dio
          .delete('/api/v1/fandoms/${widget.slug}/channels/${channel.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa kênh "${channel.name}".')),
      );
      setState(() {
        _selectedChannel = null;
        _activeSection = WorkspaceSection.welcome;
      });
      await _loadWorkspaceData();
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể xóa kênh.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail ?? 'Không thể xóa kênh.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _showFandomSettingsDialog() async {
    if (_fandom == null || !_fandom!.isOwner) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool currentPublic = _fandom!.isPublic;
        bool isUpdating = false;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Theme(
              data: AppTheme.darkTheme,
              child: AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.settings_suggest, color: AppTheme.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cài đặt Fandom: ${_fandom!.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Chế độ hiển thị không gian',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: AppTheme.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppTheme.surfaceLight),
                        ),
                        child: SwitchListTile(
                          value: currentPublic,
                          activeColor: AppTheme.primary,
                          title: Text(
                            currentPublic ? 'Công khai (Public)' : 'Riêng tư (Private)',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            currentPublic
                                ? 'Fandom xuất hiện trên Danh mục Khám phá công khai.'
                                : 'Ẩn khỏi Danh mục Khám phá (chỉ truy cập qua link/mã mời).',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          onChanged: isUpdating
                              ? null
                              : (val) async {
                                  setDialogState(() => isUpdating = true);
                                  final provider = context.read<FandomProvider>();
                                  final res = await provider.updateFandomVisibility(_fandom!.slug, val);
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    setState(() {
                                      _fandom = _fandom!.copyWith(isPublic: val);
                                    });
                                    setDialogState(() {
                                      currentPublic = val;
                                      isUpdating = false;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res['message'] ?? 'Đã cập nhật trạng thái hiển thị.'),
                                        backgroundColor: AppTheme.success,
                                      ),
                                    );
                                  } else {
                                    setDialogState(() => isUpdating = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res['error'] ?? 'Không thể cập nhật.'),
                                        backgroundColor: AppTheme.error,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: AppTheme.surfaceLight),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Vùng nguy hiểm (Danger Zone)',
                            style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Xóa hoàn toàn không gian Fandom này cùng toàn bộ kênh thảo luận, tin nhắn chat và vai trò thành viên. Hành động này không thể hoàn tác.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.error,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: const Text('XÓA VĨNH VIỄN FANDOM NÀY'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showConfirmDeleteFandomDialog();
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Đóng'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showConfirmDeleteFandomDialog() async {
    if (_fandom == null || !_fandom!.isOwner) return;

    final passwordController = TextEditingController();
    String? localError;
    bool isDeleting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Theme(
              data: AppTheme.darkTheme,
              child: AlertDialog(
                backgroundColor: AppTheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.delete_forever, color: AppTheme.error, size: 26),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Xác nhận xóa Fandom',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                          children: [
                            const TextSpan(text: 'Bạn có chắc chắn muốn xóa Fandom '),
                            TextSpan(
                              text: '"${_fandom!.name}"',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                            const TextSpan(
                              text: '? Toàn bộ kênh, tin nhắn chat và danh sách thành viên sẽ bị xóa vĩnh viễn.\n\nVui lòng nhập mật khẩu tài khoản của bạn để xác nhận:',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu tài khoản của bạn',
                          prefixIcon: const Icon(Icons.lock_outline),
                          errorText: localError,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isDeleting ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                    onPressed: isDeleting
                        ? null
                        : () async {
                            final password = passwordController.text.trim();
                            if (password.isEmpty) {
                              setDialogState(() => localError = 'Vui lòng nhập mật khẩu xác nhận.');
                              return;
                            }

                            setDialogState(() {
                              isDeleting = true;
                              localError = null;
                            });

                            final provider = context.read<FandomProvider>();
                            final res = await provider.deleteFandom(_fandom!.slug, password);

                            if (!mounted) return;
                            if (res['success'] == true) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['message'] ?? 'Fandom đã được xóa thành công.'),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                              context.go('/public');
                            } else {
                              setDialogState(() {
                                isDeleting = false;
                                localError = res['error'] ?? 'Xác nhận xóa thất bại.';
                              });
                            }
                          },
                    child: isDeleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Xác nhận xóa'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _fandom == null || _channelsData == null) {
      return Theme(
        data: AppTheme.darkTheme,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: const Text('Không gian Fandom'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/fandoms/${widget.slug}'),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: AppTheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage ?? 'Không thể tải dữ liệu Fandom.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/fandoms/${widget.slug}'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Quay lại trang thông tin Fandom'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 760;
    final sidebar = _buildSidebar(isDrawer: !isWide);

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: isWide
            ? null
            : AppBar(
                backgroundColor: AppTheme.surface,
                title: Text(
                  _fandom!.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  if (_fandom!.isOwner)
                    IconButton(
                      key: const Key('btn_fandom_settings'),
                      tooltip: 'Cài đặt Fandom (Owner)',
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      onPressed: _showFandomSettingsDialog,
                    ),
                  TextButton.icon(
                    onPressed: () => context.go('/fandoms/${widget.slug}'),
                    icon: const Icon(Icons.exit_to_app, size: 18),
                    label: const Text('Trang bìa'),
                  ),
                ],
              ),
        drawer: isWide
            ? null
            : Drawer(backgroundColor: AppTheme.surface, child: sidebar),
        body: Row(
          children: [
            if (isWide) SizedBox(width: 280, child: sidebar),
            Expanded(child: _buildMainContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({required bool isDrawer}) {
    final fandom = _fandom!;
    final channelsData = _channelsData!;

    final announcementChannels = channelsData.channels
        .where((c) => c.type == 'TEXT' && c.isAnnouncement)
        .toList();
    final textChannels = channelsData.channels
        .where((c) => c.type == 'TEXT' && !c.isAnnouncement)
        .toList();
    final voiceChannels =
        channelsData.channels.where((c) => c.type == 'VOICE').toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          right: BorderSide(color: AppTheme.surfaceLight, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.surfaceLight, width: 1),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                    backgroundImage: fandom.avatarUrl != null
                        ? NetworkImage(fandom.avatarUrl!)
                        : null,
                    child: fandom.avatarUrl == null
                        ? Text(
                            fandom.name.characters.first.toUpperCase(),
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
                          fandom.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${fandom.memberCount} thành viên',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fandom.isOwner)
                    IconButton(
                      key: const Key('btn_fandom_settings'),
                      tooltip: 'Cài đặt Fandom (Owner)',
                      icon: const Icon(
                        Icons.settings_outlined,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: _showFandomSettingsDialog,
                    ),
                  IconButton(
                    tooltip: 'Về trang giới thiệu công khai',
                    icon: const Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => context.go('/fandoms/${widget.slug}'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'CỔNG ĐÓN TIẾP & THÔNG TIN',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  _buildNavTile(
                    icon: Icons.home_outlined,
                    label: 'Giới thiệu chung',
                    selected: _activeSection == WorkspaceSection.welcome,
                    onTap: () {
                      setState(() {
                        _activeSection = WorkspaceSection.welcome;
                        _selectedChannel = null;
                      });
                      if (isDrawer) Navigator.of(context).pop();
                    },
                  ),
                  _buildNavTile(
                    icon: Icons.gavel_outlined,
                    label: 'Nội quy & Quy định',
                    selected: _activeSection == WorkspaceSection.rules,
                    trailing: _rulesAcknowledged
                        ? const Icon(
                            Icons.verified,
                            size: 16,
                            color: Colors.greenAccent,
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _activeSection = WorkspaceSection.rules;
                        _selectedChannel = null;
                      });
                      if (isDrawer) Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (channelsData.canManageChannels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () => _showCreateOrEditChannelDialog(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tạo kênh mới'),
                      ),
                    ),
                  if (announcementChannels.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'KÊNH THÔNG BÁO',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final ch in announcementChannels)
                      _buildChannelTile(ch, isDrawer: isDrawer),
                    const SizedBox(height: 12),
                  ],
                  if (textChannels.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'KÊNH TRÒ CHUYỆN',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final ch in textChannels)
                      _buildChannelTile(ch, isDrawer: isDrawer),
                    const SizedBox(height: 12),
                  ],
                  if (voiceChannels.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'KÊNH THOẠI (VOICE)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final ch in voiceChannels)
                      _buildChannelTile(ch, isDrawer: isDrawer),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : AppTheme.textSecondary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelTile(ChannelModel channel, {required bool isDrawer}) {
    final isSelected = _activeSection == WorkspaceSection.channel &&
        _selectedChannel?.id == channel.id;

    IconData iconData;
    if (channel.type == 'VOICE') {
      iconData = channel.voiceRoomType == 'STAGE_ROOM'
          ? Icons.podcasts
          : Icons.volume_up_outlined;
    } else if (channel.isAnnouncement) {
      iconData = Icons.campaign_outlined;
    } else {
      iconData = Icons.tag;
    }

    return _buildNavTile(
      icon: iconData,
      label: channel.name,
      selected: isSelected,
      trailing: channel.slowModeSeconds > 0
          ? const Icon(
              Icons.timer_outlined,
              size: 14,
              color: AppTheme.textSecondary,
            )
          : null,
      onTap: () {
        _selectChannel(channel);
        if (isDrawer) Navigator.of(context).pop();
      },
    );
  }

  Widget _buildMainContent() {
    switch (_activeSection) {
      case WorkspaceSection.welcome:
        return _buildWelcomeView();
      case WorkspaceSection.rules:
        return _buildRulesView();
      case WorkspaceSection.channel:
        if (_selectedChannel == null) {
          return _buildWelcomeView();
        }
        return _buildChannelView(_selectedChannel!);
    }
  }

  Widget _buildWelcomeView() {
    final fandom = _fandom!;
    final channels = _channelsData?.channels ?? const [];
    final firstTextChannel = channels
        .where((c) => c.type == 'TEXT' && !c.isAnnouncement)
        .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.25),
                      AppTheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        fandom.category,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Chào mừng đến với ${fandom.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fandom.description ??
                          'Không gian sinh hoạt cộng đồng chính thức dành cho các thành viên.',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _activeSection = WorkspaceSection.rules;
                            });
                          },
                          icon: const Icon(Icons.gavel_outlined, size: 18),
                          label: const Text('Xem Nội quy Cộng đồng'),
                        ),
                        if (firstTextChannel != null)
                          OutlinedButton.icon(
                            onPressed: () => _selectChannel(firstTextChannel),
                            icon:
                                const Icon(Icons.chat_bubble_outline, size: 18),
                            label: Text('Vào #${firstTextChannel.name}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Cấu trúc Không gian Fandom',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildInfoCard(
                    icon: Icons.campaign_outlined,
                    title: 'Kênh Thông báo',
                    description:
                        'Cập nhật tin tức chính thức một chiều từ Chủ Fandom (${fandom.ownerName}).',
                  ),
                  _buildInfoCard(
                    icon: Icons.forum_outlined,
                    title: 'Kênh Thảo luận',
                    description:
                        'Nhắn tin thời gian thực, chia sẻ hình ảnh và tương tác cùng ${fandom.memberCount} thành viên.',
                  ),
                  _buildInfoCard(
                    icon: Icons.podcasts,
                    title: 'Phòng Thoại (Voice)',
                    description:
                        'Giao lưu âm thanh trực tiếp hoặc giơ tay phát biểu trên sân khấu.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary, size: 26),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesView() {
    final fandom = _fandom!;
    final channels = _channelsData?.channels ?? const [];
    final firstTextChannel = channels
        .where((c) => c.type == 'TEXT' && !c.isAnnouncement)
        .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.gavel, color: AppTheme.primary, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nội quy & Quy định Cộng đồng',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng đọc kỹ quy định của ${fandom.name} trước khi tham gia nhắn tin và phát biểu trên các kênh.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Divider(height: 32, color: AppTheme.surfaceLight),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.surfaceLight),
                  ),
                  child: Text(
                    (fandom.rulesTos != null &&
                            fandom.rulesTos!.trim().isNotEmpty)
                        ? fandom.rulesTos!
                        : '1. Tôn trọng Chủ Fandom và toàn bộ thành viên trong cộng đồng.\n'
                            '2. Không gửi tin nhắn rác (spam), quảng cáo hoặc nội dung vi phạm pháp luật.\n'
                            '3. Thảo luận đúng chủ đề của từng kênh.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!_rulesAcknowledged)
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _rulesAcknowledged = true;
                          });
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'Tôi đã đọc và đồng ý tuân thủ nội quy',
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.greenAccent),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified,
                              color: Colors.greenAccent,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Đã xác nhận tuân thủ nội quy',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (firstTextChannel != null)
                        ElevatedButton.icon(
                          onPressed: () => _selectChannel(firstTextChannel),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text('Vào kênh #${firstTextChannel.name}'),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelView(ChannelModel channel) {
    final canManage =
        channel.canManageChannel || (_channelsData?.canManageChannels ?? false);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(
              bottom: BorderSide(color: AppTheme.surfaceLight, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                channel.type == 'VOICE'
                    ? Icons.volume_up_outlined
                    : (channel.isAnnouncement
                        ? Icons.campaign_outlined
                        : Icons.tag),
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          channel.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (channel.slowModeSeconds > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Chế độ chậm: ${channel.slowModeSeconds}s',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (channel.topic != null && channel.topic!.isNotEmpty)
                      Text(
                        channel.topic!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (channel.type == 'TEXT')
                IconButton(
                  key: const Key('channel_pinned_messages_button'),
                  tooltip: 'Tin nhắn đã ghim',
                  icon: const Icon(
                    Icons.push_pin_outlined,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => _showPinnedMessagesDialog(channel),
                ),
              if (canManage) ...[
                IconButton(
                  tooltip: 'Chỉnh sửa kênh',
                  icon: const Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () =>
                      _showCreateOrEditChannelDialog(existing: channel),
                ),
                IconButton(
                  tooltip: 'Xóa kênh',
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.error,
                  ),
                  onPressed: () => _confirmDeleteChannel(channel),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: channel.type == 'VOICE'
              ? _buildVoiceChannelBody(channel)
              : _buildTextChannelBody(channel),
        ),
        if (channel.type == 'TEXT') _buildTextChannelFooter(channel),
      ],
    );
  }

  Widget _buildTextChannelBody(ChannelModel channel) {
    final messages = _messagesByChannel[channel.id] ?? const [];
    final hasMore = _hasMoreByChannel[channel.id] == true;
    final nextCursor = _nextCursorByChannel[channel.id];

    if (_isLoadingMessages && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                child: Icon(
                  channel.isAnnouncement ? Icons.campaign_outlined : Icons.tag,
                  size: 34,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Chào mừng bạn đến với kênh #${channel.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                channel.topic ??
                    'Đây là điểm khởi đầu của kênh #${channel.name}. Hãy gửi tin nhắn đầu tiên!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _messageScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: messages.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasMore && index == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _isLoadingMessages
                    ? null
                    : () => _fetchChannelMessages(
                          channel.id,
                          beforeId: nextCursor,
                        ),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Tải thêm tin nhắn cũ'),
              ),
            ),
          );
        }
        final msgIndex = hasMore ? index - 1 : index;
        return _buildMessageItem(channel, messages[msgIndex]);
      },
    );
  }

  Widget _buildMessageItem(ChannelModel channel, MessageModel message) {
    final sender = message.sender;
    final timeStr =
        '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}';
    final canModerate = channel.canModerateChat;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
            backgroundImage: sender.avatarUrl != null
                ? NetworkImage(sender.avatarUrl!)
                : null,
            child: sender.avatarUrl == null
                ? Text(
                    sender.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.replyTo != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: AppTheme.primary, width: 3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.reply_rounded,
                          size: 14,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '@${message.replyTo!.senderDisplayName}: ${message.replyTo!.content}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sender.displayName,
                      style: TextStyle(
                        color: sender.isOwner ? AppTheme.primary : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (sender.isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Chủ Fandom',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (message.isPinned)
                      const Icon(
                        Icons.push_pin,
                        size: 13,
                        color: Colors.amberAccent,
                      ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (message.isEdited && !message.isRecalled)
                      const Text(
                        '(đã chỉnh sửa)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (message.isRecalled)
                  const Text(
                    'Tin nhắn đã bị thu hồi.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (message.content.isNotEmpty)
                  SelectableText(
                    message.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                if (!message.isRecalled && message.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final att in message.attachments)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            att.url,
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              padding: const EdgeInsets.all(12),
                              color: AppTheme.surfaceLight,
                              child: Text(
                                att.filename ?? att.url,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (!message.isRecalled && message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in message.reactions.entries)
                        if (entry.value is List &&
                            (entry.value as List).isNotEmpty)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _handleToggleReaction(
                              channel,
                              message,
                              entry.key,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                '${entry.key} ${(entry.value as List).length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
                if (!message.isRecalled) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (channel.canSendMessages)
                        InkWell(
                          key: Key('message_reply_${message.id}'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            setState(() {
                              _replyingToMessage = message;
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              'Trả lời',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      for (final emoji in const ['❤️', '🔥', '👍'])
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () =>
                              _handleToggleReaction(channel, message, emoji),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _showEditMessageDialog(channel, message),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Chỉnh sửa',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _handleRecallMessage(channel, message),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Thu hồi',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      if (canModerate)
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () =>
                              _handleTogglePinMessage(channel, message),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              message.isPinned ? 'Bỏ ghim' : 'Ghim',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextChannelFooter(ChannelModel channel) {
    if (!channel.canSendMessages) {
      final reasonText = channel.isAnnouncement
          ? 'Chỉ Chủ Fandom và Ban quản trị mới có quyền đăng thông báo tại kênh này.'
          : 'Bạn hiện không có quyền gửi tin nhắn trong kênh này.';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.surfaceLight, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                reasonText,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.surfaceLight, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyingToMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                  left: BorderSide(color: AppTheme.primary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đang trả lời @${_replyingToMessage!.sender.displayName}: ${_replyingToMessage!.content}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _replyingToMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
          if (_pendingAttachments.isNotEmpty) ...[
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingAttachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final item = _pendingAttachments[idx];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.url,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _pendingAttachments.removeAt(idx);
                            });
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (channel.canAttachFiles)
                IconButton(
                  tooltip: 'Đính kèm hình ảnh',
                  icon: _isUploadingAttachment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppTheme.textSecondary,
                        ),
                  onPressed: _isUploadingAttachment
                      ? null
                      : _handlePickAndUploadAttachment,
                ),
              Expanded(
                child: TextField(
                  key: const Key('channel_message_input'),
                  controller: _messageController,
                  cursorColor: AppTheme.primary,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  onSubmitted: (_) => _handleSendMessage(channel),
                  decoration: InputDecoration(
                    hintText: 'Nhắn tin tới #${channel.name}...',
                    hintStyle: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.surfaceLight,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('channel_send_button'),
                tooltip: 'Gửi tin nhắn',
                icon: _isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, color: AppTheme.primary),
                onPressed: _isSendingMessage
                    ? null
                    : () => _handleSendMessage(channel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceChannelBody(ChannelModel channel) {
    final isStage = channel.voiceRoomType == 'STAGE_ROOM';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.surfaceLight),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isStage ? Icons.podcasts : Icons.headset_mic_outlined,
                size: 48,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                channel.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isStage
                    ? 'Chế độ Sân khấu (Stage Room): Thính giả cần giơ tay để được cấp quyền phát biểu.'
                    : 'Chế độ Đàm thoại tự do (Open Mic): Thành viên có quyền thoại có thể bật mic trò chuyện.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              if (channel.canConnectVoice)
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.call_outlined),
                  label: Text(
                    channel.canSpeakVoice
                        ? 'Tham gia phòng thoại (Có quyền bật Mic)'
                        : 'Tham gia với tư cách Thính giả',
                  ),
                )
              else
                const Text(
                  'Bạn không có quyền kết nối vào phòng thoại này.',
                  style: TextStyle(color: AppTheme.error, fontSize: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
