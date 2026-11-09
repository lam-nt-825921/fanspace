/// Members directory & moderation tab inside FandomManagementDialog.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';
import 'dialogs/member_moderation_dialogs.dart';
import 'dialogs/role_form_dialog.dart';

class FandomMembersTab extends StatelessWidget {
  final FandomDetailModel fandom;
  final List<FandomMemberModel> members;
  final List<RoleModel> roles;
  final bool isLoading;
  final String statusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusFilterChanged;
  final VoidCallback onRefreshMembers;

  const FandomMembersTab({
    super.key,
    required this.fandom,
    required this.members,
    required this.roles,
    required this.isLoading,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onStatusFilterChanged,
    required this.onRefreshMembers,
  });

  Future<void> _toggleMuteMember(
    BuildContext context,
    FandomMemberModel member,
  ) async {
    final provider = context.read<FandomProvider>();
    if (member.isMuted) {
      final res = await provider.unmuteMember(fandom.id, member.userId);
      if (res['success'] == true) {
        onRefreshMembers();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['error']?.toString() ?? 'Không thể bỏ tắt tiếng.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } else {
      await MuteMemberDialog.show(
        context,
        fandomId: fandom.id,
        member: member,
        onMuted: onRefreshMembers,
      );
    }
  }

  Future<void> _showKickConfirmDialog(
    BuildContext context,
    FandomMemberModel member,
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
          'Trục xuất: ${member.displayName}',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Thành viên này sẽ bị xóa khỏi Fandom nhưng vẫn có thể gia nhập lại sau này. Bạn có chắc chắn muốn kick?',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_kick'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Trục xuất'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final provider = context.read<FandomProvider>();
      final res = await provider.kickMember(fandom.id, member.userId);
      if (res['success'] == true) {
        onRefreshMembers();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['error']?.toString() ?? 'Không thể trục xuất thành viên.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleBanMember(
    BuildContext context,
    FandomMemberModel member,
  ) async {
    final provider = context.read<FandomProvider>();
    final palette = context.palette;

    if (member.isBanned) {
      final res = await provider.unbanMember(fandom.id, member.userId);
      if (res['success'] == true) {
        onRefreshMembers();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error']?.toString() ?? 'Không thể gỡ cấm.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.border),
          ),
          title: Text(
            'Cấm vĩnh viễn: ${member.displayName}',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Thành viên này sẽ bị trục xuất ngay lập tức và bị chặn gia nhập lại vĩnh viễn (kể cả có mã mời). Bạn có chắc chắn muốn cấm?',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              key: const Key('btn_confirm_ban'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cấm vĩnh viễn'),
            ),
          ],
        ),
      );

      if (confirmed == true && context.mounted) {
        final res = await provider.banMember(fandom.id, member.userId);
        if (res['success'] == true) {
          onRefreshMembers();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['error']?.toString() ?? 'Không thể cấm thành viên.',
              ),
              backgroundColor: AppTheme.error,
            ),
          );
        }
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
              Expanded(
                child: TextField(
                  key: const Key('input_search_members'),
                  style: TextStyle(color: palette.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên thành viên...',
                    hintStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                    filled: true,
                    fillColor: palette.surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                key: const Key('dropdown_member_status_filter'),
                value: statusFilter,
                dropdownColor: palette.surfaceElevated,
                style: TextStyle(color: palette.textPrimary, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Hoạt động')),
                  DropdownMenuItem(
                    value: 'MUTED',
                    child: Text('Bị tắt tiếng'),
                  ),
                  DropdownMenuItem(value: 'BANNED', child: Text('Bị cấm')),
                  DropdownMenuItem(value: 'ALL', child: Text('Tất cả')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    onStatusFilterChanged(val);
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : members.isEmpty
                  ? Center(
                      child: Text(
                        'Không tìm thấy thành viên nào.',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: members.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final member = members[index];
                        final isSelfOrOwner = member.userId == fandom.ownerId;

                        return Container(
                          decoration: BoxDecoration(
                            color: palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: palette.border),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.14),
                                backgroundImage: member.avatarUrl != null
                                    ? NetworkImage(member.avatarUrl!)
                                    : null,
                                child: member.avatarUrl == null
                                    ? Text(
                                        member.displayName.isNotEmpty
                                            ? member.displayName[0]
                                                .toUpperCase()
                                            : 'U',
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
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          member.displayName,
                                          style: TextStyle(
                                            color: palette.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '@${member.username}',
                                          style: TextStyle(
                                            color: palette.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (member.isMuted)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'MUTED',
                                              style: TextStyle(
                                                color: Colors.orange,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (member.isBanned)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.error
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'BANNED',
                                              style: TextStyle(
                                                color: AppTheme.error,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (member.roles.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: member.roles.map((r) {
                                          final roleColor =
                                              parseRoleColor(r.colorHex);
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.surface,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border:
                                                  Border.all(color: roleColor),
                                            ),
                                            child: Text(
                                              r.name,
                                              style: TextStyle(
                                                color: roleColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isSelfOrOwner) ...[
                                IconButton(
                                  key: Key('btn_assign_roles_${member.userId}'),
                                  tooltip: 'Gán vai trò',
                                  icon: const Icon(
                                    Icons.badge_outlined,
                                    size: 18,
                                    color: AppTheme.primary,
                                  ),
                                  onPressed: () => AssignMemberRolesDialog.show(
                                    context,
                                    fandomId: fandom.id,
                                    member: member,
                                    availableRoles: roles,
                                    onSaved: onRefreshMembers,
                                  ),
                                ),
                                IconButton(
                                  key: Key('btn_mute_${member.userId}'),
                                  tooltip: member.isMuted
                                      ? 'Bỏ tắt tiếng'
                                      : 'Tắt tiếng (Mute)',
                                  icon: Icon(
                                    member.isMuted
                                        ? Icons.volume_up
                                        : Icons.volume_off,
                                    size: 18,
                                    color: member.isMuted
                                        ? AppTheme.success
                                        : Colors.orange,
                                  ),
                                  onPressed: () =>
                                      _toggleMuteMember(context, member),
                                ),
                                IconButton(
                                  key: Key('btn_kick_${member.userId}'),
                                  tooltip: 'Trục xuất (Kick)',
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                    size: 18,
                                    color: Colors.amber,
                                  ),
                                  onPressed: () =>
                                      _showKickConfirmDialog(context, member),
                                ),
                                IconButton(
                                  key: Key('btn_ban_${member.userId}'),
                                  tooltip: member.isBanned
                                      ? 'Gỡ cấm (Unban)'
                                      : 'Cấm vĩnh viễn (Ban)',
                                  icon: Icon(
                                    member.isBanned
                                        ? Icons.lock_open
                                        : Icons.block,
                                    size: 18,
                                    color: AppTheme.error,
                                  ),
                                  onPressed: () =>
                                      _toggleBanMember(context, member),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Tùy chọn kiểm duyệt thành viên',
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: palette.textSecondary,
                                  ),
                                  color: palette.surfaceElevated,
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'roles':
                                        AssignMemberRolesDialog.show(
                                          context,
                                          fandomId: fandom.id,
                                          member: member,
                                          availableRoles: roles,
                                          onSaved: onRefreshMembers,
                                        );
                                      case 'mute':
                                        _toggleMuteMember(context, member);
                                      case 'kick':
                                        _showKickConfirmDialog(context, member);
                                      case 'ban':
                                        _toggleBanMember(context, member);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'roles',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.badge_outlined,
                                          size: 18,
                                        ),
                                        title: Text('Gán vai trò (Roles)'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'mute',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          member.isMuted
                                              ? Icons.volume_up
                                              : Icons.volume_off,
                                          size: 18,
                                        ),
                                        title: Text(
                                          member.isMuted
                                              ? 'Bỏ tắt tiếng'
                                              : 'Tắt tiếng (Mute)',
                                        ),
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'kick',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.person_remove_outlined,
                                          size: 18,
                                          color: Colors.amber,
                                        ),
                                        title: Text('Trục xuất (Kick)'),
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    PopupMenuItem(
                                      value: 'ban',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          member.isBanned
                                              ? Icons.lock_open
                                              : Icons.block,
                                          size: 18,
                                          color: AppTheme.error,
                                        ),
                                        title: Text(
                                          member.isBanned
                                              ? 'Gỡ cấm (Unban)'
                                              : 'Cấm vĩnh viễn (Ban)',
                                          style: const TextStyle(
                                            color: AppTheme.error,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
