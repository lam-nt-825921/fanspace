/// Dialog for editing an existing chat message in a channel.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/message_model.dart';

class EditMessageDialog extends StatefulWidget {
  final ChannelModel channel;
  final MessageModel message;
  final ValueChanged<MessageModel> onMessageUpdated;

  const EditMessageDialog({
    super.key,
    required this.channel,
    required this.message,
    required this.onMessageUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required ChannelModel channel,
    required MessageModel message,
    required ValueChanged<MessageModel> onMessageUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EditMessageDialog(
        channel: channel,
        message: message,
        onMessageUpdated: onMessageUpdated,
      ),
    );
  }

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  final ApiClient _api = ApiClient();
  late final TextEditingController _editCtrl;
  String? _dialogError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final trimmed = _editCtrl.text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _dialogError = 'Nội dung tin nhắn không được để trống.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _dialogError = null;
    });

    try {
      final res = await _api.dio.put(
        '/api/v1/channels/${widget.channel.id}/messages/${widget.message.id}',
        data: {'content': trimmed},
      );
      final updated = MessageModel.fromJson(res.data as Map<String, dynamic>);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onMessageUpdated(updated);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data is Map
          ? e.response?.data['detail']?.toString()
          : 'Không thể chỉnh sửa tin nhắn.';
      setState(() {
        _dialogError = detail ?? 'Không thể chỉnh sửa tin nhắn.';
        _isSaving = false;
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
        'Chỉnh sửa tin nhắn',
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_dialogError != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _dialogError!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _editCtrl,
              maxLines: 4,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nội dung tin nhắn',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _handleSave,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Lưu'),
        ),
      ],
    );
  }
}
