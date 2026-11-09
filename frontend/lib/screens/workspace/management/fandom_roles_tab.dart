/// Roles and Preset Moderators management tab inside FandomManagementDialog.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';
import 'dialogs/role_form_dialog.dart';

class FandomRolesTab extends StatelessWidget {
  final FandomDetailModel fandom;
  final List<RoleModel> roles;
  final List<FandomMemberModel> members;
  final bool isLoading;
  final VoidCallback onRefreshRoles;
  final VoidCallback onRefreshAll;

  const FandomRolesTab({
    super.key,
    required this.fandom,
    required this.roles,
    required this.members,
    required this.isLoading,
    required this.onRefreshRoles,
    required this.onRefreshAll,
  });

  Future<void> _showDeleteRoleConfirmDialog(
    BuildContext context,
    RoleModel role,
  ) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
        title: Text(
          'Xác nhận xóa vai trò: ${role.name}',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Các thành viên đang giữ vai trò này sẽ bị thu hồi. Bạn có chắc chắn muốn xóa?',
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
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final provider = context.read<FandomProvider>();
      final res = await provider.deleteRole(fandom.id, role.id);
      if (res['success'] == true) {
        onRefreshRoles();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['error']?.toString() ?? 'Không thể xóa vai trò.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                key: const Key('btn_create_role'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Tạo vai trò',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => RoleFormDialog.show(
                  context,
                  fandomId: fandom.id,
                  onSaved: onRefreshRoles,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('btn_assign_preset_mod'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.textPrimary,
                  side: BorderSide(color: palette.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: Colors.orange,
                ),
                label: const Text(
                  'Chỉ định Preset Mod',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => PresetModDialog.show(
                  context,
                  fandom: fandom,
                  members: members,
                  onAssigned: onRefreshAll,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : roles.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có vai trò nào được tạo.',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: roles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final role = roles[index];
                        final roleColor = parseRoleColor(role.colorHex);

                        return Container(
                          decoration: BoxDecoration(
                            color: palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: palette.border),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: roleColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          role.name,
                                          style: TextStyle(
                                            color: palette.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (role.isPresetMod) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'PRESET MOD',
                                              style: TextStyle(
                                                color: Colors.amber,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Cấp bậc ưu tiên: ${role.priority} • Bitmask: ${role.permissionsBitmask}',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('btn_edit_role_${role.id}'),
                                tooltip: 'Chỉnh sửa vai trò',
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: palette.textSecondary,
                                ),
                                onPressed: () => RoleFormDialog.show(
                                  context,
                                  fandomId: fandom.id,
                                  existingRole: role,
                                  onSaved: onRefreshRoles,
                                ),
                              ),
                              IconButton(
                                key: Key('btn_delete_role_${role.id}'),
                                tooltip: 'Xóa vai trò',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppTheme.error,
                                ),
                                onPressed: () =>
                                    _showDeleteRoleConfirmDialog(context, role),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
