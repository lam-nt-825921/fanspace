/// Dialogs for member role assignment, muting, kicking, and banning.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/fandom_model.dart';
import '../../../../providers/fandom_provider.dart';
import 'role_form_dialog.dart';

class AssignMemberRolesDialog extends StatefulWidget {
  final String fandomId;
  final FandomMemberModel member;
  final List<RoleModel> availableRoles;
  final VoidCallback onSaved;

  const AssignMemberRolesDialog({
    super.key,
    required this.fandomId,
    required this.member,
    required this.availableRoles,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required FandomMemberModel member,
    required List<RoleModel> availableRoles,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AssignMemberRolesDialog(
        fandomId: fandomId,
        member: member,
        availableRoles: availableRoles,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<AssignMemberRolesDialog> createState() =>
      _AssignMemberRolesDialogState();
}

class _AssignMemberRolesDialogState extends State<AssignMemberRolesDialog> {
  late final Set<String> _selectedRoleIds;

  @override
  void initState() {
    super.initState();
    _selectedRoleIds = widget.member.roles.map((r) => r.id).toSet();
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
        'Gán vai trò: ${widget.member.displayName}',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: widget.availableRoles.isEmpty
            ? Text(
                'Chưa có vai trò nào được tạo.',
                style: TextStyle(color: palette.textSecondary),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.availableRoles.length,
                itemBuilder: (c, i) {
                  final role = widget.availableRoles[i];
                  final isSelected = _selectedRoleIds.contains(role.id);

                  return CheckboxListTile(
                    value: isSelected,
                    activeColor: AppTheme.primary,
                    title: Text(
                      role.name,
                      style: TextStyle(
                        color: parseRoleColor(role.colorHex),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Độ ưu tiên: ${role.priority}',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedRoleIds.add(role.id);
                        } else {
                          _selectedRoleIds.remove(role.id);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_confirm_save_member_roles'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () async {
            final provider = context.read<FandomProvider>();
            final res = await provider.assignMemberRoles(
              widget.fandomId,
              widget.member.userId,
              _selectedRoleIds.toList(),
            );
            if (!context.mounted) return;
            if (res['success'] == true) {
              Navigator.of(context).pop();
              widget.onSaved();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    res['error']?.toString() ?? 'Không thể lưu vai trò.',
                  ),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class MuteMemberDialog extends StatefulWidget {
  final String fandomId;
  final FandomMemberModel member;
  final VoidCallback onMuted;

  const MuteMemberDialog({
    super.key,
    required this.fandomId,
    required this.member,
    required this.onMuted,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required FandomMemberModel member,
    required VoidCallback onMuted,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MuteMemberDialog(
        fandomId: fandomId,
        member: member,
        onMuted: onMuted,
      ),
    );
  }

  @override
  State<MuteMemberDialog> createState() => _MuteMemberDialogState();
}

class _MuteMemberDialogState extends State<MuteMemberDialog> {
  int _durationHours = 24;

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
        'Tắt tiếng: ${widget.member.displayName}',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: _durationHours,
        dropdownColor: palette.surfaceElevated,
        style: TextStyle(color: palette.textPrimary),
        decoration: const InputDecoration(labelText: 'Thời lượng tắt tiếng'),
        items: const [
          DropdownMenuItem(value: 1, child: Text('1 giờ')),
          DropdownMenuItem(value: 24, child: Text('24 giờ')),
          DropdownMenuItem(value: 72, child: Text('3 ngày')),
          DropdownMenuItem(value: 168, child: Text('7 ngày')),
        ],
        onChanged: (val) => setState(() => _durationHours = val ?? 24),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_confirm_mute'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () async {
            final provider = context.read<FandomProvider>();
            final messenger = ScaffoldMessenger.maybeOf(context);
            Navigator.of(context).pop();
            final res = await provider.muteMember(
              widget.fandomId,
              widget.member.userId,
              durationHours: _durationHours,
            );
            if (res['success'] == true) {
              widget.onMuted();
            } else {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    res['error']?.toString() ?? 'Không thể tắt tiếng.',
                  ),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          child: const Text('Tắt tiếng'),
        ),
      ],
    );
  }
}
