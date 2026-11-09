import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fandom_provider.dart';
import '../auth/widgets/theme_toggle_button.dart';
import '../profile/user_card_dialog.dart';
import '../workspace/fandom_management_dialog.dart';
import 'dialogs/join_by_invite_dialog.dart';
import 'dialogs/my_fandoms_quick_switcher_dialog.dart';
import 'widgets/fandom_media_gallery.dart';

class FandomDetailScreen extends StatefulWidget {
  final String slug;
  final FandomDetailModel? initialFandom;

  const FandomDetailScreen({
    super.key,
    required this.slug,
    this.initialFandom,
  });

  @override
  State<FandomDetailScreen> createState() => _FandomDetailScreenState();
}

class _FandomDetailScreenState extends State<FandomDetailScreen> {
  FandomDetailModel? _fandom;
  bool _isLoading = true;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFandom != null) {
      _fandom = widget.initialFandom;
      _isLoading = false;
    } else {
      _loadFandom();
    }
  }

  Future<void> _loadFandom() async {
    final fandomProvider = Provider.of<FandomProvider>(context, listen: false);
    final detail = await fandomProvider.getFandomPreview(widget.slug);
    if (mounted) {
      setState(() {
        _fandom = detail;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleJoin() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đăng nhập tài khoản để tham gia Fandom.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    if (_fandom != null && !_fandom!.isPublic) {
      JoinByInviteDialog.show(context, onJoinedSuccess: _loadFandom);
      return;
    }

    setState(() => _isActionLoading = true);
    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.joinFandom(widget.slug);

    if (!mounted) return;
    setState(() => _isActionLoading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Thao tác thành công.'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadFandom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Không thể tham gia Fandom.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận rời Fandom?'),
        content: Text(
          'Bạn có chắc chắn muốn rời khỏi Fandom "${_fandom?.name ?? ''}" không?',
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

    setState(() => _isActionLoading = true);
    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.leaveFandom(widget.slug);

    if (!mounted) return;
    setState(() => _isActionLoading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đã rời khỏi Fandom.'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadFandom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Không thể rời Fandom.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleCancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy yêu cầu tham gia?'),
        content: const Text(
          'Bạn có chắc chắn muốn rút lại đơn xin gia nhập đang chờ duyệt không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hủy đơn'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionLoading = true);
    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.cancelJoinRequest(widget.slug);

    if (!mounted) return;
    setState(() => _isActionLoading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đã hủy yêu cầu tham gia.'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadFandom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Không thể hủy yêu cầu.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = context.watch<AuthProvider>();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_fandom == null) {
      return Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          leading: IconButton(
            key: const Key('fandom_detail_back_button'),
            tooltip: 'Quay lại trang chủ',
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBack,
          ),
          title: const Text('Không tìm thấy Fandom'),
          actions: [
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined, size: 18),
              label: const Text('Về Trang chủ'),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: palette.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Không tìm thấy thông tin Fandom.',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Quay về Khám phá Cộng đồng'),
              ),
            ],
          ),
        ),
      );
    }

    final fandom = _fandom!;
    final isOwner = fandom.isOwner ||
        (auth.isAuthenticated &&
            auth.currentUser?.id.toString() == fandom.ownerId);

    return Scaffold(
      backgroundColor: palette.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  key: const Key('fandom_detail_back_button'),
                  tooltip: 'Quay lại trang chủ',
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _navigateBack,
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.explore_outlined, size: 16),
                  label: const Text(
                    'Trang chủ',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (auth.isAuthenticated)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => MyFandomsQuickSwitcherDialog.show(context),
                    icon: const Icon(Icons.workspaces_rounded, size: 16),
                    label: const Text(
                      'Fandom của tôi',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 18,
                child: PopupMenuButton<String>(
                  tooltip: 'Tùy chọn Fandom',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  onSelected: (val) {
                    if (val == 'workspace') {
                      context.go('/fandoms/${fandom.slug}/space');
                    } else if (val == 'settings') {
                      showDialog<void>(
                        context: context,
                        builder: (_) => FandomManagementDialog(
                          fandom: fandom,
                          onFandomUpdated: (updated) {
                            setState(() => _fandom = updated);
                          },
                        ),
                      );
                    } else if (val == 'invite') {
                      JoinByInviteDialog.show(
                        context,
                        onJoinedSuccess: _loadFandom,
                      );
                    } else if (val == 'owner') {
                      UserCardDialog.show(
                        context,
                        identifier: fandom.ownerId.isNotEmpty
                            ? fandom.ownerId
                            : (fandom.ownerUsername ?? fandom.ownerName),
                        fallbackName: fandom.ownerName,
                      );
                    } else if (val == 'leave') {
                      _handleLeave();
                    }
                  },
                  itemBuilder: (_) => [
                    if (isOwner || fandom.isMember)
                      const PopupMenuItem(
                        value: 'workspace',
                        child: Row(
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            SizedBox(width: 8),
                            Text('Vào Không gian Chat'),
                          ],
                        ),
                      ),
                    if (isOwner)
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.settings_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Quản trị & Cài đặt Fandom'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'invite',
                      child: Row(
                        children: [
                          Icon(
                            Icons.vpn_key_outlined,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                          SizedBox(width: 8),
                          Text('Nhập mã mời Fandom'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'owner',
                      child: Row(
                        children: [
                          Icon(Icons.person_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Xem Hồ sơ Chủ Fandom'),
                        ],
                      ),
                    ),
                    if (fandom.isMember && !isOwner) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'leave',
                        child: Row(
                          children: [
                            Icon(
                              Icons.exit_to_app,
                              size: 18,
                              color: AppTheme.error,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Rời khỏi Fandom',
                              style: TextStyle(color: AppTheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 18,
                child: ThemeToggleButton(),
              ),
              const SizedBox(width: 12),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (fandom.bannerUrl != null && fandom.bannerUrl!.isNotEmpty)
                    Image.network(
                      fandom.bannerUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _defaultBanner(),
                    )
                  else
                    _defaultBanner(),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.black87,
                        ],
                        stops: [0.0, 0.4, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            color: AppTheme.primary,
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (fandom.avatarUrl != null &&
                                  fandom.avatarUrl!.isNotEmpty)
                              ? Image.network(
                                  fandom.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _avatarFallback(fandom.name),
                                )
                              : _avatarFallback(fandom.name),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fandom.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 6),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '@${fandom.slug}',
                                style: const TextStyle(
                                  color: Color(0xFFF9A8D4),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges & Stats Row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              fandom.category,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: fandom.admissionMode == 'OPEN'
                                  ? AppTheme.success.withValues(alpha: 0.12)
                                  : AppTheme.warning.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: fandom.admissionMode == 'OPEN'
                                    ? AppTheme.success
                                    : AppTheme.warning,
                              ),
                            ),
                            child: Text(
                              fandom.admissionMode == 'OPEN'
                                  ? 'Gia nhập Tự do'
                                  : 'Cần xét duyệt',
                              style: TextStyle(
                                color: fandom.admissionMode == 'OPEN'
                                    ? AppTheme.success
                                    : AppTheme.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _StatChip(
                            icon: Icons.people_alt_outlined,
                            label: '${fandom.memberCount} Thành viên',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Creator / Owner Card
                      InkWell(
                        onTap: () {
                          UserCardDialog.show(
                            context,
                            identifier: fandom.ownerId.isNotEmpty
                                ? fandom.ownerId
                                : (fandom.ownerUsername ?? fandom.ownerName),
                            fallbackName: fandom.ownerName,
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: palette.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppTheme.primary,
                                backgroundImage:
                                    (fandom.ownerAvatarUrl != null &&
                                            fandom.ownerAvatarUrl!.isNotEmpty)
                                        ? NetworkImage(fandom.ownerAvatarUrl!)
                                        : null,
                                child: (fandom.ownerAvatarUrl == null ||
                                        fandom.ownerAvatarUrl!.isEmpty)
                                    ? Text(
                                        fandom.ownerName.isNotEmpty
                                            ? fandom.ownerName[0].toUpperCase()
                                            : 'U',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
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
                                          'Chủ sở hữu / Người sáng lập: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: palette.textSecondary,
                                          ),
                                        ),
                                        Flexible(
                                          child: Text(
                                            fandom.ownerName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: palette.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fandom.ownerUsername != null
                                          ? '@${fandom.ownerUsername} • Bấm để xem thẻ hồ sơ'
                                          : 'Bấm để xem thẻ hồ sơ tóm tắt',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Xem hồ sơ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.touch_app_outlined,
                                      size: 13,
                                      color: AppTheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Primary Action Bar (FR-04)
                      _buildActionSection(context, fandom, isOwner, palette),
                      const SizedBox(height: 28),

                      // Media Gallery (FR-02)
                      FandomMediaGallery(
                        illustrationUrls: fandom.illustrationUrls,
                      ),

                      // Description Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: palette.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Giới thiệu Fandom',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              fandom.description?.isNotEmpty == true
                                  ? fandom.description!
                                  : 'Chưa có mô tả chi tiết cho Fandom này.',
                              style: TextStyle(
                                color: palette.textSecondary,
                                height: 1.5,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Rules / TOS Card
                      if (fandom.rulesTos != null &&
                          fandom.rulesTos!.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: palette.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nội quy & Điều khoản',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                fandom.rulesTos!,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSection(
    BuildContext context,
    FandomDetailModel fandom,
    bool isOwner,
    AppPalette palette,
  ) {
    if (_isActionLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Đang xử lý yêu cầu...',
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (isOwner) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => context.go('/fandoms/${fandom.slug}/space'),
              icon: const Icon(Icons.meeting_room_outlined, size: 20),
              label: const Text(
                'Vào Không gian Fandom (Chủ sở hữu)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => FandomManagementDialog(
                  fandom: fandom,
                  onFandomUpdated: (updated) {
                    setState(() => _fandom = updated);
                  },
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Quản trị'),
          ),
        ],
      );
    }

    if (fandom.isMember) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => context.go('/fandoms/${fandom.slug}/space'),
              icon: const Icon(Icons.forum_outlined, size: 20),
              label: const Text(
                'Vào Không gian Fandom',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error, width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _handleLeave,
            icon: const Icon(Icons.exit_to_app, size: 18),
            label: const Text(
              'Rời Fandom',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }

    if (fandom.isPendingRequest) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warning, width: 1),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.hourglass_top,
                      color: AppTheme.warning,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'ĐANG CHỜ DUYỆT GIA NHẬP',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _handleCancelRequest,
            icon: const Icon(Icons.close, size: 18),
            label: const Text(
              'Hủy yêu cầu',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }

    if (!fandom.isPublic) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () =>
            JoinByInviteDialog.show(context, onJoinedSuccess: _loadFandom),
        icon: const Icon(Icons.key_outlined),
        label: const Text(
          'FANDOM RIÊNG TƯ • NHẬP MÃ MỜI ĐỂ GIA NHẬP',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _handleJoin,
            icon: Icon(
              fandom.admissionMode == 'OPEN'
                  ? Icons.group_add
                  : Icons.assignment_ind_outlined,
            ),
            label: Text(
              fandom.admissionMode == 'OPEN'
                  ? 'THAM GIA FANDOM NGAY'
                  : 'GỬI ĐƠN XÉT DUYỆT GIA NHẬP',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          onPressed: () =>
              JoinByInviteDialog.show(context, onJoinedSuccess: _loadFandom),
          icon: const Icon(Icons.vpn_key_outlined, size: 18),
          label: const Text('Có mã mời?'),
        ),
      ],
    );
  }

  Widget _defaultBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.accent.withValues(alpha: 0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'F',
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
