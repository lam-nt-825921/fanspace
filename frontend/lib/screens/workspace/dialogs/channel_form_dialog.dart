/// Dialog for creating or editing a Fandom communication channel (Text or Voice).
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';

class ChannelFormDialog extends StatefulWidget {
  final String fandomSlug;
  final ChannelModel? existing;
  final Future<void> Function(ChannelModel saved) onSaved;

  const ChannelFormDialog({
    super.key,
    required this.fandomSlug,
    this.existing,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomSlug,
    ChannelModel? existing,
    required Future<void> Function(ChannelModel saved) onSaved,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChannelFormDialog(
        fandomSlug: fandomSlug,
        existing: existing,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<ChannelFormDialog> createState() => _ChannelFormDialogState();
}

class _ChannelFormDialogState extends State<ChannelFormDialog> {
  final ApiClient _api = ApiClient();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _topicCtrl;
  late final TextEditingController _slowModeCtrl;

  late String _selectedType;
  late bool _isAnnouncement;
  late bool _isMembershipOnly;
  late String _voiceRoomType;
  String? _dialogError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _topicCtrl = TextEditingController(text: existing?.topic ?? '');
    _slowModeCtrl = TextEditingController(
      text: (existing?.slowModeSeconds ?? 0).toString(),
    );
    _selectedType = existing?.type ?? 'TEXT';
    _isAnnouncement = existing?.isAnnouncement ?? false;
    _isMembershipOnly = existing?.isMembershipOnly ?? false;
    _voiceRoomType = existing?.voiceRoomType ?? 'OPEN_MIC';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _topicCtrl.dispose();
    _slowModeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.length < 2) {
      setState(() {
        _dialogError = 'Tên kênh phải có ít nhất 2 ký tự.';
      });
      return;
    }
    final slowSec = int.tryParse(_slowModeCtrl.text.trim()) ?? 0;

    setState(() {
      _isSubmitting = true;
      _dialogError = null;
    });

    try {
      ChannelModel result;
      if (widget.existing == null) {
        final res = await _api.dio.post(
          '/api/v1/fandoms/${widget.fandomSlug}/channels',
          data: {
            'name': trimmedName,
            'type': _selectedType,
            'topic': _topicCtrl.text.trim().isEmpty
                ? null
                : _topicCtrl.text.trim(),
            'is_announcement':
                _selectedType == 'TEXT' ? _isAnnouncement : false,
            'is_membership_only': _isMembershipOnly,
            'slow_mode_seconds': _selectedType == 'TEXT' ? slowSec : 0,
            'voice_room_type':
                _selectedType == 'VOICE' ? _voiceRoomType : null,
          },
        );
        result = ChannelModel.fromJson(res.data as Map<String, dynamic>);
      } else {
        final res = await _api.dio.put(
          '/api/v1/fandoms/${widget.fandomSlug}/channels/${widget.existing!.id}',
          data: {
            'name': trimmedName,
            'topic': _topicCtrl.text.trim(),
            'is_announcement':
                _selectedType == 'TEXT' ? _isAnnouncement : null,
            'is_membership_only': _isMembershipOnly,
            'slow_mode_seconds': _selectedType == 'TEXT' ? slowSec : null,
            'voice_room_type':
                _selectedType == 'VOICE' ? _voiceRoomType : null,
          },
        );
        result = ChannelModel.fromJson(res.data as Map<String, dynamic>);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onSaved(result);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : null;
      setState(() {
        _dialogError = detail ?? 'Không thể lưu kênh.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        widget.existing == null
            ? 'Tạo kênh giao tiếp mới'
            : 'Chỉnh sửa cấu hình kênh',
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_dialogError != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _dialogError!,
                    style: const TextStyle(color: AppTheme.error, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.existing == null) ...[
                Text(
                  'Loại kênh',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
                  selected: {_selectedType},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedType = val.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Tên kênh',
                  hintText: 'Ví dụ: chat-chung, góc-fanart',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _topicCtrl,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Chủ đề / Mô tả kênh',
                  hintText: 'Giới thiệu ngắn về mục đích của kênh',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const Key('switch_channel_membership_only'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Kênh đặc quyền Hội viên VIP',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Chỉ thành viên đã đăng ký Gói Hội viên hoặc Quản trị viên mới được truy cập',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                value: _isMembershipOnly,
                onChanged: (val) {
                  setState(() => _isMembershipOnly = val);
                },
              ),
              const SizedBox(height: 8),
              if (_selectedType == 'TEXT') ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Kênh thông báo một chiều',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Chỉ Chủ Fandom và Ban quản trị được phép gửi tin nhắn',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: _isAnnouncement,
                  onChanged: (val) {
                    setState(() => _isAnnouncement = val);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _slowModeCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Giới hạn tốc độ nhắn tin (Slow-mode giây)',
                    hintText: '0 = Không giới hạn',
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _voiceRoomType,
                  isExpanded: true,
                  dropdownColor: palette.surfaceElevated,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
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
                      setState(() => _voiceRoomType = val);
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
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: Text(widget.existing == null ? 'Tạo kênh' : 'Lưu thay đổi'),
        ),
      ],
    );
  }
}
