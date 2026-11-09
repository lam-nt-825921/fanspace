/// Dialogs for creating/editing Fandom roles and assigning Preset Moderators.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/fandom_model.dart';
import '../../../../providers/fandom_provider.dart';

Color parseRoleColor(String hex) {
  try {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return AppTheme.primary;
  }
}

class RoleFormDialog extends StatefulWidget {
  final String fandomId;
  final RoleModel? existingRole;
  final VoidCallback onSaved;

  const RoleFormDialog({
    super.key,
    required this.fandomId,
    this.existingRole,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    RoleModel? existingRole,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => RoleFormDialog(
        fandomId: fandomId,
        existingRole: existingRole,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<RoleFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _colorController;
  late final TextEditingController _priorityController;
  late int _currentBitmask;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingRole?.name ?? '',
    );
    _colorController = TextEditingController(
      text: widget.existingRole?.colorHex ?? '#808080',
    );
    _priorityController = TextEditingController(
      text: (widget.existingRole?.priority ?? 10).toString(),
    );
    _currentBitmask = widget.existingRole?.permissionsBitmask ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final priority = int.tryParse(_priorityController.text.trim()) ?? 0;
    final color = _colorController.text.trim();

    setState(() => _isSaving = true);
    final provider = context.read<FandomProvider>();

    Map<String, dynamic> res;
    if (widget.existingRole == null) {
      res = await provider.createRole(
        widget.fandomId,
        name: name,
        colorHex: color.startsWith('#') ? color : '#$color',
        priority: priority,
        permissionsBitmask: _currentBitmask,
      );
    } else {
      res = await provider.updateRole(
        widget.fandomId,
        widget.existingRole!.id,
        name: name,
        colorHex: color.startsWith('#') ? color : '#$color',
        priority: priority,
        permissionsBitmask: _currentBitmask,
      );
    }

    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.of(context).pop();
      widget.onSaved();
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error']?.toString() ?? 'Thao tác thất bại.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

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
        widget.existingRole == null ? 'Tạo vai trò mới' : 'Chỉnh sửa vai trò',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('input_role_name'),
                controller: _nameController,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Tên vai trò',
                  hintText: 'VD: VIP Fan, Điều hành viên',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_role_color'),
                      controller: _colorController,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Mã màu HEX',
                        hintText: '#E91E63',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: parseRoleColor(_colorController.text),
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.border),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('input_role_priority'),
                controller: _priorityController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Độ ưu tiên (Priority)',
                  hintText: '1 - 1000',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Phân quyền hạn (Bitmask)',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              ...FandomPermissionBit.allPermissions.map((perm) {
                final bit = perm['bit'] as int;
                final name = perm['name'] as String;
                final desc = perm['desc'] as String;
                final isGranted = (_currentBitmask & bit) != 0;

                return CheckboxListTile(
                  dense: true,
                  value: isGranted,
                  activeColor: AppTheme.primary,
                  title: Text(
                    name,
                    style: TextStyle(color: palette.textPrimary, fontSize: 12),
                  ),
                  subtitle: Text(
                    desc,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _currentBitmask |= bit;
                      } else {
                        _currentBitmask &= ~bit;
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_save_role'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _isSaving ? null : _handleSave,
          child: const Text('Lưu vai trò'),
        ),
      ],
    );
  }
}

class PresetModDialog extends StatefulWidget {
  final FandomDetailModel fandom;
  final List<FandomMemberModel> members;
  final VoidCallback onAssigned;

  const PresetModDialog({
    super.key,
    required this.fandom,
    required this.members,
    required this.onAssigned,
  });

  static Future<void> show(
    BuildContext context, {
    required FandomDetailModel fandom,
    required List<FandomMemberModel> members,
    required VoidCallback onAssigned,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PresetModDialog(
        fandom: fandom,
        members: members,
        onAssigned: onAssigned,
      ),
    );
  }

  @override
  State<PresetModDialog> createState() => _PresetModDialogState();
}

class _PresetModDialogState extends State<PresetModDialog> {
  String? _selectedUserId;
  String _selectedType = 'CHAT_MODERATOR';

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
        'Bổ nhiệm Moderator định sẵn',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('dropdown_select_mod_user'),
              isExpanded: true,
              initialValue: _selectedUserId,
              dropdownColor: palette.surfaceElevated,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(labelText: 'Chọn thành viên'),
              items: widget.members
                  .where(
                    (m) => m.userId != widget.fandom.ownerId && !m.isBanned,
                  )
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.userId,
                      child: Text('${m.displayName} • @${m.username}'),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedUserId = val),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('dropdown_preset_type'),
              isExpanded: true,
              initialValue: _selectedType,
              dropdownColor: palette.surfaceElevated,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(labelText: 'Loại vai trò'),
              items: const [
                DropdownMenuItem(
                  value: 'CO_HOST',
                  child: Text('Phó quản trị Fandom'),
                ),
                DropdownMenuItem(
                  value: 'CHAT_MODERATOR',
                  child: Text('Điều phối viên Kênh chat'),
                ),
                DropdownMenuItem(
                  value: 'VOICE_MODERATOR',
                  child: Text('Điều phối viên Kênh thoại'),
                ),
              ],
              onChanged: (val) =>
                  setState(() => _selectedType = val ?? 'CHAT_MODERATOR'),
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
          key: const Key('btn_confirm_preset_mod'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _selectedUserId == null
              ? null
              : () async {
                  final provider = context.read<FandomProvider>();
                  final res = await provider.assignPresetMod(
                    widget.fandom.id,
                    userId: _selectedUserId!,
                    presetType: _selectedType,
                  );
                  if (!context.mounted) return;
                  if (res['success'] == true) {
                    Navigator.of(context).pop();
                    widget.onAssigned();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã bổ nhiệm vai trò Mod thành công!'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          res['error']?.toString() ?? 'Không thể bổ nhiệm.',
                        ),
                        backgroundColor: AppTheme.error,
                      ),
                    );
                  }
                },
          child: const Text('Bổ nhiệm'),
        ),
      ],
    );
  }
}
