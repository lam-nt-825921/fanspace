/// Fandom internal workspace screen featuring Welcome, Rules, and Channel navigation.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/channel_model.dart';
import '../../models/fandom_model.dart';

/// Active navigation section inside the Fandom workspace.
enum WorkspaceSection {
  welcome,
  rules,
  channel,
}

/// Interactive internal workspace for an active Fandom member or owner.
class FandomWorkspaceScreen extends StatefulWidget {
  final String slug;
  final FandomDetailModel? initialFandom;
  final FandomChannelsDataModel? initialChannelsData;

  const FandomWorkspaceScreen({
    super.key,
    required this.slug,
    this.initialFandom,
    this.initialChannelsData,
  });

  @override
  State<FandomWorkspaceScreen> createState() => _FandomWorkspaceScreenState();
}

class _FandomWorkspaceScreenState extends State<FandomWorkspaceScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _messageController = TextEditingController();

  FandomDetailModel? _fandom;
  FandomChannelsDataModel? _channelsData;
  WorkspaceSection _activeSection = WorkspaceSection.welcome;
  ChannelModel? _selectedChannel;
  bool _rulesAcknowledged = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaceData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fandomRes = await _api.dio.get('/api/v1/fandoms/${widget.slug}/preview');
      final channelsRes = await _api.dio.get('/api/v1/fandoms/${widget.slug}/channels');



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
        _errorMessage =
            detail ?? 'Không thể tải dữ liệu không gian Fandom. Vui lòng thử lại.';
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
    });
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
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Text(
                existing == null ? 'Tạo kênh giao tiếp mới' : 'Chỉnh sửa cấu hình kênh',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                            style: const TextStyle(color: AppTheme.error, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (existing == null) ...[
                        const Text(
                          'Loại kênh',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
                        decoration: const InputDecoration(
                          labelText: 'Tên kênh',
                          hintText: 'Ví dụ: chat-chung, góc-fanart',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: topicCtrl,
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
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Chỉ Chủ Fandom và Ban quản trị được phép gửi tin nhắn',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                          decoration: const InputDecoration(
                            labelText: 'Giới hạn tốc độ nhắn tin (Slow-mode giây)',
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
                              child: Text('Sân khấu phát biểu (Stage Room - Giơ tay)'),
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
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
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
                          final slowSec = int.tryParse(slowModeCtrl.text.trim()) ?? 0;

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
                                  'is_announcement':
                                      selectedType == 'TEXT' ? isAnnouncement : false,
                                  'slow_mode_seconds':
                                      selectedType == 'TEXT' ? slowSec : 0,
                                  'voice_room_type':
                                      selectedType == 'VOICE' ? voiceRoomType : null,
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
                                  'is_announcement':
                                      selectedType == 'TEXT' ? isAnnouncement : null,
                                  'slow_mode_seconds':
                                      selectedType == 'TEXT' ? slowSec : null,
                                  'voice_room_type':
                                      selectedType == 'VOICE' ? voiceRoomType : null,
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
        );
      },
    );
  }

  Future<void> _confirmDeleteChannel(ChannelModel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.dio.delete('/api/v1/fandoms/${widget.slug}/channels/${channel.id}');

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _fandom == null || _channelsData == null) {
      return Scaffold(
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
                const Icon(Icons.lock_outline, size: 56, color: AppTheme.error),
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
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 760;
    final sidebar = _buildSidebar(isDrawer: !isWide);


    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: isWide
          ? null
          : AppBar(
              backgroundColor: AppTheme.surface,
              title: Text(
                _fandom!.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => context.go('/fandoms/${widget.slug}'),
                  icon: const Icon(Icons.exit_to_app, size: 18),
                  label: const Text('Trang bìa'),
                ),
              ],
            ),
      drawer: isWide ? null : Drawer(backgroundColor: AppTheme.surface, child: sidebar),
      body: Row(
        children: [
          if (isWide) SizedBox(width: 280, child: sidebar),
          Expanded(child: _buildMainContent()),
        ],
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
            // Fandom Workspace Header
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

            // Navigation items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
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
          ? const Icon(Icons.timer_outlined, size: 14, color: AppTheme.textSecondary)
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
              // Welcome Banner Card
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
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: Text('Vào #${firstTextChannel.name}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Community Stats & Structure Overview
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
                    (fandom.rulesTos != null && fandom.rulesTos!.trim().isNotEmpty)
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
                        label: const Text('Tôi đã đọc và đồng ý tuân thủ nội quy'),
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
        // Channel Header Bar
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

        // Channel Body
        Expanded(
          child: channel.type == 'VOICE'
              ? _buildVoiceChannelBody(channel)
              : _buildTextChannelBody(channel),
        ),

        // Channel Bottom Composer / Status Bar for TEXT channels
        if (channel.type == 'TEXT') _buildTextChannelFooter(channel),
      ],
    );
  }

  Widget _buildTextChannelBody(ChannelModel channel) {
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
                  'Đây là điểm khởi đầu của kênh #${channel.name}.',
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
      child: Row(
        children: [
          if (channel.canAttachFiles)
            IconButton(
              tooltip: 'Đính kèm hình ảnh',
              icon: const Icon(
                Icons.add_photo_alternate_outlined,
                color: AppTheme.textSecondary,
              ),
              onPressed: () {},
            ),
          Expanded(
            child: TextField(
              key: const Key('channel_message_input'),
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Nhắn tin tới #${channel.name}...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Gửi tin nhắn',
            icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
            onPressed: () {},
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
