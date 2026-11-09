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
import '../../widgets/theme/theme_toggle_button.dart';
import 'dialogs/channel_form_dialog.dart';
import 'dialogs/delete_fandom_confirm_dialog.dart';
import 'dialogs/edit_message_dialog.dart';
import 'dialogs/membership_tiers_dialog.dart';
import 'dialogs/pinned_messages_dialog.dart';
import 'fandom_management_dialog.dart';
import 'widgets/channel_header_bar.dart';
import 'widgets/chat_message_composer.dart';
import 'widgets/chat_message_item.dart';
import 'widgets/voice_channel_view.dart';
import 'widgets/workspace_sidebar.dart';
import 'widgets/workspace_welcome_view.dart';

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
  final Set<String> _collapsedThreadIds = {};
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
    await PinnedMessagesDialog.show(
      context,
      channel: channel,
      pinnedMessages: pinnedMessages,
    );
  }

  Future<void> _showCreateOrEditChannelDialog({ChannelModel? existing}) async {
    await ChannelFormDialog.show(
      context,
      fandomSlug: widget.slug,
      existing: existing,
      onSaved: (saved) async {
        await _loadWorkspaceData();
        _selectChannel(saved);
      },
    );
  }

  Future<void> _showMembershipTiersModal() async {
    if (_fandom == null) return;
    final provider = context.read<FandomProvider>();
    final memData = await provider.fetchMemberships(_fandom!.id);
    if (!mounted) return;

    await MembershipTiersDialog.show(
      context,
      fandom: _fandom!,
      membershipsData: memData,
      onTierActivated: _loadWorkspaceData,
    );
  }

  Future<void> _confirmDeleteChannel(ChannelModel channel) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
        title: Text(
          'Xác nhận xóa kênh',
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa kênh "${channel.name}" không? Hành động này không thể hoàn tác.',
          style: TextStyle(color: palette.textSecondary),
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
      builder: (ctx) => FandomManagementDialog(
        fandom: _fandom!,
        onFandomUpdated: (updated) {
          setState(() {
            _fandom = updated;
          });
        },
        onDeleteRequested: _showConfirmDeleteFandomDialog,
      ),
    );
  }

  Future<void> _showConfirmDeleteFandomDialog() async {
    if (_fandom == null || !_fandom!.isOwner) return;
    await DeleteFandomConfirmDialog.show(context, fandom: _fandom!);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _fandom == null || _channelsData == null) {
      return Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: palette.surface,
          title: Text(
            'Không gian Fandom',
            style: TextStyle(color: palette.textPrimary),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: palette.textPrimary),
            onPressed: () =>
                GoRouter.maybeOf(context)?.go('/fandoms/${widget.slug}'),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => GoRouter.maybeOf(context)?.go('/'),
              icon: const Icon(Icons.home_outlined, size: 18),
              label: const Text('Trang chủ'),
            ),
            const ThemeToggleButton(compact: true),
            const SizedBox(width: 8),
          ],
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
                  style: TextStyle(color: palette.textPrimary, fontSize: 16),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => GoRouter.maybeOf(context)
                          ?.go('/fandoms/${widget.slug}'),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Quay lại trang thông tin Fandom'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => GoRouter.maybeOf(context)?.go('/'),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Về Trang chủ Khám phá'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 760;
    final sidebar = WorkspaceSidebar(
      fandom: _fandom!,
      channelsData: _channelsData!,
      activeSection: _activeSection,
      selectedChannel: _selectedChannel,
      rulesAcknowledged: _rulesAcknowledged,
      isDrawer: !isWide,
      onSelectWelcome: () {
        setState(() {
          _activeSection = WorkspaceSection.welcome;
          _selectedChannel = null;
        });
      },
      onSelectRules: () {
        setState(() {
          _activeSection = WorkspaceSection.rules;
          _selectedChannel = null;
        });
      },
      onOpenMembershipTiers: _showMembershipTiersModal,
      onOpenFandomSettings: _showFandomSettingsDialog,
      onCreateChannel: () => _showCreateOrEditChannelDialog(),
      onSelectChannel: _selectChannel,
    );

    return Scaffold(
      backgroundColor: palette.background,
      appBar: isWide
          ? null
          : AppBar(
              backgroundColor: palette.surface,
              title: Text(
                _fandom!.name,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              actions: [
                if (_fandom!.isOwner)
                  IconButton(
                    key: const Key('btn_fandom_settings'),
                    tooltip: 'Cài đặt Fandom',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: _showFandomSettingsDialog,
                  ),
                const ThemeToggleButton(compact: true),
                TextButton.icon(
                  onPressed: () => GoRouter.maybeOf(context)
                      ?.go('/fandoms/${widget.slug}'),
                  icon: const Icon(Icons.exit_to_app, size: 18),
                  label: const Text('Trang bìa'),
                ),
              ],
            ),
      drawer: isWide
          ? null
          : Drawer(backgroundColor: palette.surface, child: sidebar),
      body: Row(
        children: [
          if (isWide) SizedBox(width: 280, child: sidebar),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_activeSection) {
      case WorkspaceSection.welcome:
        return WorkspaceWelcomeView(
          fandom: _fandom!,
          channels: _channelsData?.channels ?? const [],
          onViewRules: () {
            setState(() {
              _activeSection = WorkspaceSection.rules;
            });
          },
          onSelectChannel: _selectChannel,
        );
      case WorkspaceSection.rules:
        return WorkspaceRulesView(
          fandom: _fandom!,
          channels: _channelsData?.channels ?? const [],
          rulesAcknowledged: _rulesAcknowledged,
          onAcknowledgeRules: () {
            setState(() {
              _rulesAcknowledged = true;
            });
          },
          onSelectChannel: _selectChannel,
        );
      case WorkspaceSection.channel:
        if (_selectedChannel == null) {
          return WorkspaceWelcomeView(
            fandom: _fandom!,
            channels: _channelsData?.channels ?? const [],
            onViewRules: () {
              setState(() {
                _activeSection = WorkspaceSection.rules;
              });
            },
            onSelectChannel: _selectChannel,
          );
        }
        return _buildChannelView(_selectedChannel!);
    }
  }

  Widget _buildChannelView(ChannelModel channel) {
    final canManage =
        channel.canManageChannel || (_channelsData?.canManageChannels ?? false);

    return Column(
      children: [
        ChannelHeaderBar(
          channel: channel,
          canManage: canManage,
          onOpenPinnedMessages: () => _showPinnedMessagesDialog(channel),
          onEditChannel: () =>
              _showCreateOrEditChannelDialog(existing: channel),
          onDeleteChannel: () => _confirmDeleteChannel(channel),
        ),
        Expanded(
          child: channel.type == 'VOICE'
              ? VoiceChannelView(channel: channel)
              : _buildTextChannelBody(channel),
        ),
        if (channel.type == 'TEXT')
          ChatMessageComposer(
            channel: channel,
            messageController: _messageController,
            replyingToMessage: _replyingToMessage,
            pendingAttachments: _pendingAttachments,
            isUploadingAttachment: _isUploadingAttachment,
            isSendingMessage: _isSendingMessage,
            onCancelReply: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
            onRemoveAttachment: (idx) {
              setState(() {
                _pendingAttachments.removeAt(idx);
              });
            },
            onPickAttachment: _handlePickAndUploadAttachment,
            onSendMessage: () => _handleSendMessage(channel),
          ),
      ],
    );
  }

  Widget _buildTextChannelBody(ChannelModel channel) {
    final palette = context.palette;
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
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                channel.topic ??
                    'Đây là điểm khởi đầu của kênh #${channel.name}. Hãy gửi tin nhắn đầu tiên!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group replies into Slack-style collapsible threads under their root parent message
    final byId = <String, MessageModel>{
      for (final m in messages) m.id: m,
    };
    String? resolveRootParentId(MessageModel m) {
      var currentParentId = m.replyToId;
      final visited = <String>{m.id};
      String? foundRoot;
      while (currentParentId != null &&
          byId.containsKey(currentParentId) &&
          !visited.contains(currentParentId)) {
        visited.add(currentParentId);
        foundRoot = currentParentId;
        currentParentId = byId[currentParentId]?.replyToId;
      }
      return foundRoot;
    }

    final repliesByParentId = <String, List<MessageModel>>{};
    final rootMessages = <MessageModel>[];
    for (final m in messages) {
      final rootId = resolveRootParentId(m);
      if (rootId != null) {
        repliesByParentId.putIfAbsent(rootId, () => []).add(m);
      } else {
        rootMessages.add(m);
      }
    }

    return ListView.builder(
      controller: _messageScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: rootMessages.length + (hasMore ? 1 : 0),
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
        final msg = rootMessages[msgIndex];
        final threadReplies = repliesByParentId[msg.id] ?? const [];
        final isExpanded = !_collapsedThreadIds.contains(msg.id);

        return ChatMessageItem(
          channel: channel,
          message: msg,
          threadReplies: threadReplies,
          isThreadExpanded: isExpanded,
          onToggleThread: () {
            setState(() {
              if (_collapsedThreadIds.contains(msg.id)) {
                _collapsedThreadIds.remove(msg.id);
              } else {
                _collapsedThreadIds.add(msg.id);
              }
            });
          },
          onReply: () {
            setState(() {
              _replyingToMessage = msg;
              _collapsedThreadIds.remove(msg.id);
            });
          },
          onToggleReaction: (emoji) =>
              _handleToggleReaction(channel, msg, emoji),
          onEdit: () => EditMessageDialog.show(
            context,
            channel: channel,
            message: msg,
            onMessageUpdated: (updated) =>
                _replaceMessageInChannel(channel.id, updated),
          ),
          onRecall: () => _handleRecallMessage(channel, msg),
          onTogglePin: () => _handleTogglePinMessage(channel, msg),
          onReplyToThreadMessage: (reply) {
            setState(() {
              _replyingToMessage = reply;
              _collapsedThreadIds.remove(msg.id);
            });
          },
          onToggleThreadReaction: (reply, emoji) =>
              _handleToggleReaction(channel, reply, emoji),
          onEditThreadMessage: (reply) => EditMessageDialog.show(
            context,
            channel: channel,
            message: reply,
            onMessageUpdated: (updated) =>
                _replaceMessageInChannel(channel.id, updated),
          ),
          onRecallThreadMessage: (reply) =>
              _handleRecallMessage(channel, reply),
          onPinThreadMessage: (reply) =>
              _handleTogglePinMessage(channel, reply),
        );
      },
    );
  }
}
