/// My Fandoms tab inside UserSettingsDialog with direct Chat/Detail navigation and action options.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';
import '../../home/dialogs/join_by_invite_dialog.dart';

class ProfileMyFandomsTab extends StatefulWidget {
  const ProfileMyFandomsTab({super.key});

  @override
  State<ProfileMyFandomsTab> createState() => _ProfileMyFandomsTabState();
}

class _ProfileMyFandomsTabState extends State<ProfileMyFandomsTab> {
  MyFandomsDataModel? _myFandomsData;
  bool _isLoadingFandoms = true;
  String _fandomFilter = 'ALL'; // 'ALL', 'OWNER', 'JOINED', 'PENDING'

  @override
  void initState() {
    super.initState();
    _loadUserFandoms();
  }

  Future<void> _loadUserFandoms() async {
    setState(() => _isLoadingFandoms = true);
    final fandomProvider = context.read<FandomProvider>();
    final data = await fandomProvider.fetchMyFandoms();
    if (mounted) {
      setState(() {
        _myFandomsData = data;
        _isLoadingFandoms = false;
      });
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Future<void> _handleLeaveFromDialog(String slug, String fandomName) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Xác nhận rời Fandom?'),
        content: Text(
          'Bạn có chắc chắn muốn rời khỏi Fandom "$fandomName" không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rời Fandom'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.leaveFandom(slug);

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Đã rời khỏi Fandom.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadUserFandoms();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['error']?.toString() ?? 'Không thể rời Fandom.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleCancelPendingRequest(String slug) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        title: const Text('Hủy đơn xin gia nhập?'),
        content: const Text(
          'Bạn có chắc chắn muốn hủy đơn xin gia nhập đang chờ duyệt không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Hủy đơn',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.cancelJoinRequest(slug);

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Đã hủy đơn xin gia nhập.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadUserFandoms();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Không thể hủy đơn.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final myFandoms = _myFandomsData;
    final allFandoms = myFandoms?.allFandoms ?? [];
    final ownedOnly = myFandoms?.managed ?? [];
    final joinedOnly = myFandoms?.joined ?? [];
    final pendingRequests = myFandoms?.pendingRequests ?? [];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fandom của tôi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Các cộng đồng bạn đang tham gia hoặc sở hữu.',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  GoRouter.maybeOf(context)?.go('/create-fandom');
                },
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text(
                  'Tạo Fandom',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  JoinByInviteDialog.show(
                    context,
                    navigateOnSuccess: false,
                    onJoinedSuccess: () {
                      if (mounted) _loadUserFandoms();
                    },
                  );
                },
                icon: const Icon(Icons.vpn_key_outlined, size: 16),
                label: const Text(
                  'Nhập mã mời',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFandomFilterChip(
                  context,
                  'Tất cả • ${allFandoms.length}',
                  'ALL',
                ),
                const SizedBox(width: 8),
                _buildFandomFilterChip(
                  context,
                  'Đang sở hữu • ${ownedOnly.length}',
                  'OWNER',
                ),
                const SizedBox(width: 8),
                _buildFandomFilterChip(
                  context,
                  'Đang tham gia • ${joinedOnly.length}',
                  'JOINED',
                ),
                const SizedBox(width: 8),
                _buildFandomFilterChip(
                  context,
                  'Chờ duyệt • ${pendingRequests.length}',
                  'PENDING',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _isLoadingFandoms
                ? const Center(child: CircularProgressIndicator())
                : _fandomFilter == 'PENDING'
                    ? _buildPendingRequestsList(context, pendingRequests)
                    : _buildMembershipsList(
                        context,
                        _fandomFilter == 'OWNER'
                            ? ownedOnly
                            : (_fandomFilter == 'JOINED'
                                ? joinedOnly
                                : allFandoms),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFandomFilterChip(
    BuildContext context,
    String label,
    String filterKey,
  ) {
    final palette = context.palette;
    final isSelected = _fandomFilter == filterKey;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _fandomFilter = filterKey);
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.16),
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.primary : palette.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : palette.border,
        ),
      ),
    );
  }

  Widget _buildMembershipsList(
    BuildContext context,
    List<FandomSummaryModel> items,
  ) {
    final palette = context.palette;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 48,
              color: palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              _fandomFilter == 'OWNER'
                  ? 'Bạn chưa sở hữu Fandom nào.'
                  : 'Bạn chưa tham gia Fandom nào.',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hãy khám phá danh bạ cộng đồng công khai hoặc nhập mã mời!',
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final isOwner = _myFandomsData?.isOwner(item.id) ?? false;
        final createdDateStr = _formatDate(item.createdAt);

        return Container(
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary,
                backgroundImage:
                    item.avatarUrl != null && item.avatarUrl!.isNotEmpty
                        ? NetworkImage(item.avatarUrl!)
                        : null,
                child: item.avatarUrl == null || item.avatarUrl!.isEmpty
                    ? Text(
                        item.name.isNotEmpty
                            ? item.name[0].toUpperCase()
                            : 'F',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isOwner
                                ? Colors.amber.withValues(alpha: 0.18)
                                : AppTheme.success.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isOwner ? Colors.amber : AppTheme.success,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            isOwner ? 'Chủ Fandom' : 'Thành viên',
                            style: TextStyle(
                              color: isOwner ? Colors.amber : AppTheme.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surfaceLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '• ${item.memberCount} tv',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (createdDateStr.isNotEmpty)
                          Text(
                            '• Tạo: $createdDateStr',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      GoRouter.maybeOf(context)
                          ?.go('/fandoms/${item.slug}/space');
                    },
                    icon: const Icon(Icons.forum_outlined, size: 15),
                    label: const Text(
                      'Vào Chat',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      GoRouter.maybeOf(context)?.go('/fandoms/${item.slug}');
                    },
                    child: const Text(
                      'Trang bìa',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Tùy chọn Fandom',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                    color: palette.surfaceElevated,
                    onSelected: (value) {
                      switch (value) {
                        case 'space':
                          Navigator.of(context).pop();
                          GoRouter.maybeOf(context)
                              ?.go('/fandoms/${item.slug}/space');
                        case 'detail':
                          Navigator.of(context).pop();
                          GoRouter.maybeOf(context)
                              ?.go('/fandoms/${item.slug}');
                        case 'leave':
                          _handleLeaveFromDialog(item.slug, item.name);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'space',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.forum_outlined, size: 18),
                          title: Text('Vào Không gian Chat'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'detail',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline, size: 18),
                          title: Text('Xem Trang giới thiệu'),
                        ),
                      ),
                      if (!isOwner) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'leave',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.exit_to_app,
                              size: 18,
                              color: AppTheme.error,
                            ),
                            title: Text(
                              'Rời khỏi Fandom',
                              style: TextStyle(color: AppTheme.error),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingRequestsList(
    BuildContext context,
    List<FandomJoinRequestItemModel> items,
  ) {
    final palette = context.palette;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 48,
              color: palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Không có đơn xin gia nhập nào đang chờ duyệt.',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = items[index];
        final dateStr = _formatDate(req.createdAt);

        return Container(
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.amber.withValues(alpha: 0.2),
                child: const Icon(
                  Icons.hourglass_top,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.fandomName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ĐANG CHỜ DUYỆT',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (dateStr.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Gửi ngày: $dateStr',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.textSecondary,
                  side: BorderSide(color: palette.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _handleCancelPendingRequest(req.fandomSlug),
                icon: const Icon(Icons.close, size: 14),
                label: const Text(
                  'Hủy yêu cầu',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
