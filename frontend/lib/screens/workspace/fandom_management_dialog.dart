import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/fandom_provider.dart';

/// Modal dialog for managing Fandom settings, members, roles, and invite links (FR-08).
class FandomManagementDialog extends StatefulWidget {
  final FandomDetailModel fandom;
  final ValueChanged<FandomDetailModel>? onFandomUpdated;
  final VoidCallback? onDeleteRequested;

  const FandomManagementDialog({
    super.key,
    required this.fandom,
    this.onFandomUpdated,
    this.onDeleteRequested,
  });

  @override
  State<FandomManagementDialog> createState() => _FandomManagementDialogState();
}

class _FandomManagementDialogState extends State<FandomManagementDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late FandomDetailModel _currentFandom;

  // Members state
  List<FandomMemberModel> _members = [];
  bool _isLoadingMembers = false;
  String _memberSearchQuery = '';
  String _memberStatusFilter = 'ACTIVE';

  // Roles state
  List<RoleModel> _roles = [];
  bool _isLoadingRoles = false;

  // Invites state
  List<FandomInviteModel> _invites = [];
  bool _isLoadingInvites = false;

  @override
  void initState() {
    super.initState();
    _currentFandom = widget.fandom;
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      if (_tabController.index == 1) _loadMembers();
      if (_tabController.index == 2) _loadRoles();
      if (_tabController.index == 3) _loadInvites();
    }
  }

  Future<void> _loadAllData() async {
    _loadMembers();
    _loadRoles();
    _loadInvites();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoadingMembers = true);
    final provider = context.read<FandomProvider>();
    final members = await provider.fetchMembers(
      _currentFandom.id,
      search: _memberSearchQuery,
      statusFilter: _memberStatusFilter,
    );
    if (!mounted) return;
    setState(() {
      _members = members;
      _isLoadingMembers = false;
    });
  }

  Future<void> _loadRoles() async {
    setState(() => _isLoadingRoles = true);
    final provider = context.read<FandomProvider>();
    final roles = await provider.fetchRoles(_currentFandom.id);
    if (!mounted) return;
    setState(() {
      _roles = roles;
      _isLoadingRoles = false;
    });
  }

  Future<void> _loadInvites() async {
    setState(() => _isLoadingInvites = true);
    final provider = context.read<FandomProvider>();
    final invites = await provider.fetchInvites(_currentFandom.id);
    if (!mounted) return;
    setState(() {
      _invites = invites;
      _isLoadingInvites = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppTheme.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cài đặt Fandom: ${_currentFandom.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Tab Bar
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                tabs: const [
                  Tab(key: Key('tab_settings'), icon: Icon(Icons.tune, size: 18), text: 'Cài đặt'),
                  Tab(key: Key('tab_members'), icon: Icon(Icons.people_outline, size: 18), text: 'Thành viên'),
                  Tab(key: Key('tab_roles'), icon: Icon(Icons.security, size: 18), text: 'Vai trò'),
                  Tab(key: Key('tab_invites'), icon: Icon(Icons.link, size: 18), text: 'Mã mời'),
                ],
              ),
              const Divider(color: AppTheme.surfaceLight, height: 1),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSettingsTab(),
                    _buildMembersTab(),
                    _buildRolesTab(),
                    _buildInvitesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Cài đặt (General Settings & Danger Zone)
  // ---------------------------------------------------------------------------
  Widget _buildSettingsTab() {
    bool isUpdating = false;

    return StatefulBuilder(
      builder: (ctx, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chế độ hiển thị không gian',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Material(
                color: AppTheme.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppTheme.surfaceLight),
                ),
                child: SwitchListTile(
                  key: const Key('switch_fandom_visibility'),
                  value: _currentFandom.isPublic,
                  activeColor: AppTheme.primary,
                  title: Text(
                    _currentFandom.isPublic ? 'Công khai (Public)' : 'Riêng tư (Private)',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _currentFandom.isPublic
                        ? 'Fandom xuất hiện trên Danh mục Khám phá công khai.'
                        : 'Ẩn khỏi Danh mục Khám phá (chỉ truy cập qua link/mã mời).',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  onChanged: isUpdating
                      ? null
                      : (val) async {
                          setLocalState(() => isUpdating = true);
                          final provider = context.read<FandomProvider>();
                          final res = await provider.updateFandomVisibility(_currentFandom.id, val);
                          if (!mounted) return;
                          if (res['success'] == true) {
                            final updated = _currentFandom.copyWith(isPublic: val);
                            setState(() => _currentFandom = updated);
                            widget.onFandomUpdated?.call(updated);
                            setLocalState(() => isUpdating = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res['message'] ?? 'Đã cập nhật trạng thái hiển thị.'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          } else {
                            setLocalState(() => isUpdating = false);
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
              const SizedBox(height: 28),
              const Divider(color: AppTheme.surfaceLight),
              const SizedBox(height: 16),
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
                key: const Key('btn_trigger_delete_fandom'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text('XÓA VĨNH VIỄN FANDOM NÀY'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onDeleteRequested?.call();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: Quản lý thành viên (Members & Moderation)
  // ---------------------------------------------------------------------------
  Widget _buildMembersTab() {
    return Column(
      children: [
        // Filter and Search Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('input_search_members'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên thành viên...',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: AppTheme.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.surfaceLight),
                    ),
                  ),
                  onChanged: (val) {
                    _memberSearchQuery = val;
                    _loadMembers();
                  },
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                key: const Key('dropdown_member_status_filter'),
                value: _memberStatusFilter,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Hoạt động')),
                  DropdownMenuItem(value: 'MUTED', child: Text('Bị tắt tiếng')),
                  DropdownMenuItem(value: 'BANNED', child: Text('Bị cấm')),
                  DropdownMenuItem(value: 'ALL', child: Text('Tất cả')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _memberStatusFilter = val);
                    _loadMembers();
                  }
                },
              ),
            ],
          ),
        ),

        // Members List
        Expanded(
          child: _isLoadingMembers
              ? const Center(child: CircularProgressIndicator())
              : _members.isEmpty
                  ? const Center(
                      child: Text(
                        'Không tìm thấy thành viên nào.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final member = _members[index];
                        final isSelfOrOwner = member.userId == _currentFandom.ownerId;

                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.surfaceLight),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.surfaceLight,
                                backgroundImage: member.avatarUrl != null
                                    ? NetworkImage(member.avatarUrl!)
                                    : null,
                                child: member.avatarUrl == null
                                    ? Text(
                                        member.displayName.isNotEmpty
                                            ? member.displayName[0].toUpperCase()
                                            : 'U',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          member.displayName,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '@${member.username}',
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        ),
                                        if (member.isMuted) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('MUTED', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                        if (member.isBanned) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('BANNED', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: member.roles.map((r) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.surface,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: _parseColor(r.colorHex),
                                            ),
                                          ),
                                          child: Text(
                                            r.name,
                                            style: TextStyle(
                                              color: _parseColor(r.colorHex),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                              // Moderation actions
                              if (!isSelfOrOwner) ...[
                                IconButton(
                                  key: Key('btn_assign_roles_${member.userId}'),
                                  tooltip: 'Gán vai trò',
                                  icon: const Icon(Icons.badge_outlined, size: 18, color: AppTheme.primary),
                                  onPressed: () => _showAssignRolesDialog(member),
                                ),
                                IconButton(
                                  key: Key('btn_mute_${member.userId}'),
                                  tooltip: member.isMuted ? 'Bỏ tắt tiếng' : 'Tắt tiếng (Mute)',
                                  icon: Icon(
                                    member.isMuted ? Icons.volume_up : Icons.volume_off,
                                    size: 18,
                                    color: member.isMuted ? AppTheme.success : Colors.orange,
                                  ),
                                  onPressed: () => _toggleMuteMember(member),
                                ),
                                IconButton(
                                  key: Key('btn_kick_${member.userId}'),
                                  tooltip: 'Trục xuất (Kick)',
                                  icon: const Icon(Icons.person_remove_outlined, size: 18, color: Colors.amber),
                                  onPressed: () => _showKickConfirmDialog(member),
                                ),
                                IconButton(
                                  key: Key('btn_ban_${member.userId}'),
                                  tooltip: member.isBanned ? 'Gỡ cấm (Unban)' : 'Cấm vĩnh viễn (Ban)',
                                  icon: Icon(
                                    member.isBanned ? Icons.lock_open : Icons.block,
                                    size: 18,
                                    color: AppTheme.error,
                                  ),
                                  onPressed: () => _toggleBanMember(member),
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

  // ---------------------------------------------------------------------------
  // TAB 3: Quản lý vai trò (Roles Management & Preset Mods)
  // ---------------------------------------------------------------------------
  Widget _buildRolesTab() {
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Tạo vai trò', style: TextStyle(fontSize: 12)),
                onPressed: () => _showCreateOrEditRoleDialog(),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('btn_assign_preset_mod'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.surfaceLight),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.verified_user_outlined, size: 16, color: Colors.orange),
                label: const Text('Chỉ định Preset Mod', style: TextStyle(fontSize: 12)),
                onPressed: _showPresetModDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingRoles
              ? const Center(child: CircularProgressIndicator())
              : _roles.isEmpty
                  ? const Center(
                      child: Text(
                        'Chưa có vai trò nào được tạo.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _roles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final role = _roles[index];
                        final roleColor = _parseColor(role.colorHex);

                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.surfaceLight),
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
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        if (role.isPresetMod) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('PRESET MOD', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Cấp bậc ưu tiên: ${role.priority} • Bitmask: ${role.permissionsBitmask}',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('btn_edit_role_${role.id}'),
                                tooltip: 'Chỉnh sửa vai trò',
                                icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textSecondary),
                                onPressed: () => _showCreateOrEditRoleDialog(existingRole: role),
                              ),
                              IconButton(
                                key: Key('btn_delete_role_${role.id}'),
                                tooltip: 'Xóa vai trò',
                                icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                onPressed: () => _showDeleteRoleConfirmDialog(role),
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

  // ---------------------------------------------------------------------------
  // TAB 4: Quản lý mã mời (Invite Links Management)
  // ---------------------------------------------------------------------------
  Widget _buildInvitesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                key: const Key('btn_create_invite'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add_link, size: 16),
                label: const Text('Tạo mã mời mới', style: TextStyle(fontSize: 12)),
                onPressed: _showCreateInviteDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingInvites
              ? const Center(child: CircularProgressIndicator())
              : _invites.isEmpty
                  ? const Center(
                      child: Text(
                        'Chưa có mã mời nào đang hoạt động.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _invites.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final invite = _invites[index];

                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.surfaceLight),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  invite.code,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Đã dùng: ${invite.usesCount} / ${invite.maxUses ?? 'Vô hạn'}',
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      invite.expiresAt != null
                                          ? 'Hết hạn: ${_formatDate(invite.expiresAt!)}'
                                          : 'Thời hạn: Vĩnh viễn',
                                      style: TextStyle(
                                        color: invite.isExpired ? AppTheme.error : AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('btn_copy_invite_${invite.code}'),
                                tooltip: 'Sao chép mã',
                                icon: const Icon(Icons.copy, size: 18, color: AppTheme.primary),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: invite.code));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Đã sao chép mã mời: ${invite.code}'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                key: Key('btn_revoke_invite_${invite.code}'),
                                tooltip: 'Thu hồi mã mời',
                                icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                onPressed: () => _revokeInvite(invite),
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

  // ---------------------------------------------------------------------------
  // Dialog Actions Implementation
  // ---------------------------------------------------------------------------

  Future<void> _showCreateOrEditRoleDialog({RoleModel? existingRole}) async {
    final nameController = TextEditingController(text: existingRole?.name ?? '');
    final colorController = TextEditingController(text: existingRole?.colorHex ?? '#808080');
    final priorityController = TextEditingController(text: (existingRole?.priority ?? 10).toString());
    int currentBitmask = existingRole?.permissionsBitmask ?? 0;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                existingRole == null ? 'Tạo vai trò mới' : 'Chỉnh sửa vai trò',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Tên vai trò', hintText: 'VD: VIP Fan, Điều hành viên'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('input_role_color'),
                              controller: colorController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(labelText: 'Mã màu HEX', hintText: '#E91E63'),
                              onChanged: (_) => setLocalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _parseColor(colorController.text),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('input_role_priority'),
                        controller: priorityController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Độ ưu tiên (Priority)', hintText: '1 - 1000'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Phân quyền hạn (Bitmask)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...FandomPermissionBit.allPermissions.map((perm) {
                        final bit = perm['bit'] as int;
                        final name = perm['name'] as String;
                        final desc = perm['desc'] as String;
                        final isGranted = (currentBitmask & bit) != 0;

                        return CheckboxListTile(
                          dense: true,
                          value: isGranted,
                          activeColor: AppTheme.primary,
                          title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          subtitle: Text(desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                          onChanged: (val) {
                            setLocalState(() {
                              if (val == true) {
                                currentBitmask |= bit;
                              } else {
                                currentBitmask &= ~bit;
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
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  key: const Key('btn_save_role'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          final priority = int.tryParse(priorityController.text.trim()) ?? 0;
                          final color = colorController.text.trim();

                          setLocalState(() => isSaving = true);
                          final provider = context.read<FandomProvider>();

                          Map<String, dynamic> res;
                          if (existingRole == null) {
                            res = await provider.createRole(
                              _currentFandom.id,
                              name: name,
                              colorHex: color.startsWith('#') ? color : '#$color',
                              priority: priority,
                              permissionsBitmask: currentBitmask,
                            );
                          } else {
                            res = await provider.updateRole(
                              _currentFandom.id,
                              existingRole.id,
                              name: name,
                              colorHex: color.startsWith('#') ? color : '#$color',
                              priority: priority,
                              permissionsBitmask: currentBitmask,
                            );
                          }

                          if (!mounted) return;
                          if (res['success'] == true) {
                            Navigator.of(ctx).pop();
                            _loadRoles();
                          } else {
                            setLocalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res['error'] ?? 'Thao tác thất bại.'), backgroundColor: AppTheme.error),
                            );
                          }
                        },
                  child: const Text('Lưu vai trò'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteRoleConfirmDialog(RoleModel role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Xác nhận xóa vai trò: ${role.name}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: const Text('Các thành viên đang giữ vai trò này sẽ bị thu hồi. Bạn có chắc chắn muốn xóa?', style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final provider = context.read<FandomProvider>();
      final res = await provider.deleteRole(_currentFandom.id, role.id);
      if (res['success'] == true) {
        _loadRoles();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? 'Không thể xóa vai trò.'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _showPresetModDialog() async {
    String? selectedUserId;
    String selectedType = 'CHAT_MODERATOR';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text('Bổ nhiệm Moderator định sẵn', style: TextStyle(color: Colors.white, fontSize: 16)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('dropdown_select_mod_user'),
                      isExpanded: true,
                      value: selectedUserId,
                      dropdownColor: AppTheme.surface,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Chọn thành viên'),
                      items: _members
                          .where((m) => m.userId != _currentFandom.ownerId && !m.isBanned)
                          .map((m) => DropdownMenuItem(value: m.userId, child: Text('${m.displayName} (@${m.username})')))
                          .toList(),
                      onChanged: (val) => setLocalState(() => selectedUserId = val),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('dropdown_preset_type'),
                      isExpanded: true,
                      value: selectedType,
                      dropdownColor: AppTheme.surface,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Loại vai trò'),
                      items: const [
                        DropdownMenuItem(value: 'CO_HOST', child: Text('Co-Host (Phó Fandom)')),
                        DropdownMenuItem(value: 'CHAT_MODERATOR', child: Text('Chat Moderator (Kiểm duyệt Chat)')),
                        DropdownMenuItem(value: 'VOICE_MODERATOR', child: Text('Voice Moderator (Kiểm duyệt Voice)')),
                      ],
                      onChanged: (val) => setLocalState(() => selectedType = val ?? 'CHAT_MODERATOR'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                ElevatedButton(
                  key: const Key('btn_confirm_preset_mod'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: selectedUserId == null
                      ? null
                      : () async {
                          final provider = context.read<FandomProvider>();
                          final res = await provider.assignPresetMod(
                            _currentFandom.id,
                            userId: selectedUserId!,
                            presetType: selectedType,
                          );
                          if (!mounted) return;
                          if (res['success'] == true) {
                            Navigator.of(ctx).pop();
                            _loadAllData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã bổ nhiệm vai trò Mod thành công!'), backgroundColor: AppTheme.success),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res['error'] ?? 'Không thể bổ nhiệm.'), backgroundColor: AppTheme.error),
                            );
                          }
                        },
                  child: const Text('Bổ nhiệm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignRolesDialog(FandomMemberModel member) async {
    final selectedRoleIds = member.roles.map((r) => r.id).toSet();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Text('Gán vai trò: ${member.displayName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
              content: SizedBox(
                width: 400,
                child: _roles.isEmpty
                    ? const Text('Chưa có vai trò nào được tạo.', style: TextStyle(color: AppTheme.textSecondary))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _roles.length,
                        itemBuilder: (c, i) {
                          final role = _roles[i];
                          final isSelected = selectedRoleIds.contains(role.id);

                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: AppTheme.primary,
                            title: Text(role.name, style: TextStyle(color: _parseColor(role.colorHex), fontWeight: FontWeight.bold)),
                            subtitle: Text('Độ ưu tiên: ${role.priority}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                            onChanged: (val) {
                              setLocalState(() {
                                if (val == true) {
                                  selectedRoleIds.add(role.id);
                                } else {
                                  selectedRoleIds.remove(role.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                ElevatedButton(
                  key: const Key('btn_confirm_save_member_roles'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () async {
                    final provider = context.read<FandomProvider>();
                    final res = await provider.assignMemberRoles(
                      _currentFandom.id,
                      member.userId,
                      selectedRoleIds.toList(),
                    );
                    if (!mounted) return;
                    if (res['success'] == true) {
                      Navigator.of(ctx).pop();
                      _loadMembers();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res['error'] ?? 'Không thể lưu vai trò.'), backgroundColor: AppTheme.error),
                      );
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleMuteMember(FandomMemberModel member) async {
    final provider = context.read<FandomProvider>();

    if (member.isMuted) {
      final res = await provider.unmuteMember(_currentFandom.id, member.userId);
      if (res['success'] == true) {
        _loadMembers();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? 'Không thể bỏ tắt tiếng.'), backgroundColor: AppTheme.error),
        );
      }
    } else {
      int durationHours = 24;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Tắt tiếng: ${member.displayName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
            content: DropdownButtonFormField<int>(
              isExpanded: true,
              value: durationHours,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Thời lượng tắt tiếng'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 giờ')),
                DropdownMenuItem(value: 24, child: Text('24 giờ (1 ngày)')),
                DropdownMenuItem(value: 72, child: Text('72 giờ (3 ngày)')),
                DropdownMenuItem(value: 168, child: Text('7 ngày (1 tuần)')),
              ],
              onChanged: (val) => durationHours = val ?? 24,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
              ElevatedButton(
                key: const Key('btn_confirm_mute'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final res = await provider.muteMember(
                    _currentFandom.id,
                    member.userId,
                    durationHours: durationHours,
                  );
                  if (res['success'] == true) {
                    _loadMembers();
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res['error'] ?? 'Không thể tắt tiếng.'), backgroundColor: AppTheme.error),
                    );
                  }
                },
                child: const Text('Tắt tiếng'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _showKickConfirmDialog(FandomMemberModel member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Trục xuất: ${member.displayName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: const Text('Thành viên này sẽ bị xóa khỏi Fandom nhưng vẫn có thể gia nhập lại sau này. Bạn có chắc chắn muốn kick?', style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
            ElevatedButton(
              key: const Key('btn_confirm_kick'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Trục xuất'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final provider = context.read<FandomProvider>();
      final res = await provider.kickMember(_currentFandom.id, member.userId);
      if (res['success'] == true) {
        _loadMembers();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? 'Không thể trục xuất thành viên.'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _toggleBanMember(FandomMemberModel member) async {
    final provider = context.read<FandomProvider>();

    if (member.isBanned) {
      final res = await provider.unbanMember(_currentFandom.id, member.userId);
      if (res['success'] == true) {
        _loadMembers();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? 'Không thể gỡ cấm.'), backgroundColor: AppTheme.error),
        );
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Cấm vĩnh viễn: ${member.displayName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
            content: const Text('Thành viên này sẽ bị trục xuất ngay lập tức và bị chặn gia nhập lại vĩnh viễn (kể cả có mã mời). Bạn có chắc chắn muốn cấm?', style: TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
              ElevatedButton(
                key: const Key('btn_confirm_ban'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Cấm vĩnh viễn'),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        final res = await provider.banMember(_currentFandom.id, member.userId);
        if (res['success'] == true) {
          _loadMembers();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['error'] ?? 'Không thể cấm thành viên.'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  Future<void> _showCreateInviteDialog() async {
    int? selectedUses;
    int? selectedHours;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text('Tạo liên kết / Mã mời mới', style: TextStyle(color: Colors.white, fontSize: 16)),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int?>(
                      key: const Key('dropdown_invite_max_uses'),
                      isExpanded: true,
                      value: selectedUses,
                      dropdownColor: AppTheme.surface,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Số lượt sử dụng tối đa'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Không giới hạn')),
                        DropdownMenuItem(value: 1, child: Text('1 lần (Dùng 1 lần duy nhất)')),
                        DropdownMenuItem(value: 10, child: Text('10 lần')),
                        DropdownMenuItem(value: 50, child: Text('50 lần')),
                        DropdownMenuItem(value: 100, child: Text('100 lần')),
                      ],
                      onChanged: (val) => setLocalState(() => selectedUses = val),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      key: const Key('dropdown_invite_expires_hours'),
                      isExpanded: true,
                      value: selectedHours,
                      dropdownColor: AppTheme.surface,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Thời hạn hiệu lực'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Vĩnh viễn (Không hết hạn)')),
                        DropdownMenuItem(value: 1, child: Text('1 giờ')),
                        DropdownMenuItem(value: 24, child: Text('24 giờ (1 ngày)')),
                        DropdownMenuItem(value: 168, child: Text('7 ngày (1 tuần)')),
                        DropdownMenuItem(value: 720, child: Text('30 ngày')),
                      ],
                      onChanged: (val) => setLocalState(() => selectedHours = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
                ElevatedButton(
                  key: const Key('btn_confirm_create_invite'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () async {
                    final provider = context.read<FandomProvider>();
                    final res = await provider.createInvite(
                      _currentFandom.id,
                      maxUses: selectedUses,
                      expiresInHours: selectedHours,
                    );
                    if (!mounted) return;
                    if (res['success'] == true) {
                      Navigator.of(ctx).pop();
                      _loadInvites();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Đã tạo mã mời: ${(res['invite'] as FandomInviteModel).code}'), backgroundColor: AppTheme.success),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res['error'] ?? 'Không thể tạo mã mời.'), backgroundColor: AppTheme.error),
                      );
                    }
                  },
                  child: const Text('Tạo mã'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _revokeInvite(FandomInviteModel invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Thu hồi mã mời: ${invite.code}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: const Text('Sau khi thu hồi, mã mời này sẽ không thể dùng để gia nhập Fandom được nữa.', style: TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
            ElevatedButton(
              key: const Key('btn_confirm_revoke_invite'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Thu hồi'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final provider = context.read<FandomProvider>();
      final res = await provider.revokeInvite(_currentFandom.id, invite.code);
      if (res['success'] == true) {
        _loadInvites();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['error'] ?? 'Không thể thu hồi mã mời.'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppTheme.primary;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
