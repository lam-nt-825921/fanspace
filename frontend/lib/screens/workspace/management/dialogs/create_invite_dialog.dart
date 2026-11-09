/// Dialog for creating Fandom invite codes with usage limits and expiration.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/fandom_model.dart';
import '../../../../providers/fandom_provider.dart';

class CreateInviteDialog extends StatefulWidget {
  final String fandomId;
  final VoidCallback onCreated;

  const CreateInviteDialog({
    super.key,
    required this.fandomId,
    required this.onCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required VoidCallback onCreated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CreateInviteDialog(
        fandomId: fandomId,
        onCreated: onCreated,
      ),
    );
  }

  @override
  State<CreateInviteDialog> createState() => _CreateInviteDialogState();
}

class _CreateInviteDialogState extends State<CreateInviteDialog> {
  int? _selectedUses;
  int? _selectedHours;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        'Tạo liên kết / Mã mời mới',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int?>(
              key: const Key('dropdown_invite_max_uses'),
              isExpanded: true,
              initialValue: _selectedUses,
              dropdownColor: palette.surfaceElevated,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Số lượt sử dụng tối đa',
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Không giới hạn')),
                DropdownMenuItem(
                  value: 1,
                  child: Text('1 lượt duy nhất'),
                ),
                DropdownMenuItem(value: 10, child: Text('10 lượt')),
                DropdownMenuItem(value: 50, child: Text('50 lượt')),
                DropdownMenuItem(value: 100, child: Text('100 lượt')),
              ],
              onChanged: (val) => setState(() => _selectedUses = val),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              key: const Key('dropdown_invite_expires_hours'),
              isExpanded: true,
              initialValue: _selectedHours,
              dropdownColor: palette.surfaceElevated,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Thời hạn hiệu lực',
              ),
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('Vĩnh viễn'),
                ),
                DropdownMenuItem(value: 1, child: Text('1 giờ')),
                DropdownMenuItem(value: 24, child: Text('24 giờ')),
                DropdownMenuItem(value: 168, child: Text('7 ngày')),
                DropdownMenuItem(value: 720, child: Text('30 ngày')),
              ],
              onChanged: (val) => setState(() => _selectedHours = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_confirm_create_invite'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () async {
            final provider = context.read<FandomProvider>();
            final res = await provider.createInvite(
              widget.fandomId,
              maxUses: _selectedUses,
              expiresInHours: _selectedHours,
            );
            if (!context.mounted) return;
            if (res['success'] == true) {
              Navigator.of(context).pop();
              widget.onCreated();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Đã tạo mã mời: ${(res['invite'] as FandomInviteModel).code}',
                  ),
                  backgroundColor: AppTheme.success,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    res['error']?.toString() ?? 'Không thể tạo mã mời.',
                  ),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          child: const Text('Tạo mã'),
        ),
      ],
    );
  }
}
