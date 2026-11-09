/// Modal dialog for managing Fandom settings, members, roles, invite links (FR-08) and monetization (FR-09).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/fandom_provider.dart';
import 'fandom_monetization_tab.dart';
import 'management/fandom_general_settings_tab.dart';
import 'management/fandom_invites_tab.dart';
import 'management/fandom_members_tab.dart';
import 'management/fandom_roles_tab.dart';

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
    _tabController = TabController(length: 5, vsync: this);
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
    final palette = context.palette;

    return Dialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cài đặt Fandom: ${_currentFandom.name}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.textSecondary),
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
              unselectedLabelColor: palette.textSecondary,
              tabs: const [
                Tab(
                  key: Key('tab_settings'),
                  icon: Icon(Icons.tune, size: 18),
                  text: 'Cài đặt',
                ),
                Tab(
                  key: Key('tab_members'),
                  icon: Icon(Icons.people_outline, size: 18),
                  text: 'Thành viên',
                ),
                Tab(
                  key: Key('tab_roles'),
                  icon: Icon(Icons.security, size: 18),
                  text: 'Vai trò',
                ),
                Tab(
                  key: Key('tab_invites'),
                  icon: Icon(Icons.link, size: 18),
                  text: 'Mã mời',
                ),
                Tab(
                  key: Key('tab_monetization'),
                  icon: Icon(Icons.monetization_on_outlined, size: 18),
                  text: 'Kinh doanh',
                ),
              ],
            ),
            Divider(color: palette.border, height: 1),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  FandomGeneralSettingsTab(
                    fandom: _currentFandom,
                    onFandomUpdated: (updated) {
                      setState(() => _currentFandom = updated);
                      widget.onFandomUpdated?.call(updated);
                    },
                    onDeleteRequested: widget.onDeleteRequested,
                  ),
                  FandomMembersTab(
                    fandom: _currentFandom,
                    members: _members,
                    roles: _roles,
                    isLoading: _isLoadingMembers,
                    statusFilter: _memberStatusFilter,
                    onSearchChanged: (val) {
                      _memberSearchQuery = val;
                      _loadMembers();
                    },
                    onStatusFilterChanged: (val) {
                      setState(() => _memberStatusFilter = val);
                      _loadMembers();
                    },
                    onRefreshMembers: _loadMembers,
                  ),
                  FandomRolesTab(
                    fandom: _currentFandom,
                    roles: _roles,
                    members: _members,
                    isLoading: _isLoadingRoles,
                    onRefreshRoles: _loadRoles,
                    onRefreshAll: _loadAllData,
                  ),
                  FandomInvitesTab(
                    fandom: _currentFandom,
                    invites: _invites,
                    isLoading: _isLoadingInvites,
                    onRefreshInvites: _loadInvites,
                  ),
                  FandomMonetizationTab(fandom: _currentFandom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
