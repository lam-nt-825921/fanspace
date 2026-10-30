import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fandom_provider.dart';
import '../profile/user_card_dialog.dart';

class FandomDetailScreen extends StatefulWidget {
  final String slug;
  const FandomDetailScreen({super.key, required this.slug});

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
    _loadFandom();
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
      _showInviteDialog();
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
        content: Text('Bạn có chắc chắn muốn rời khỏi Fandom "${_fandom?.name ?? ''}" không?'),
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

    if (confirmed != true) return;
    if (!mounted) return;

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
        content: const Text('Bạn có chắc chắn muốn rút lại đơn xin gia nhập đang chờ duyệt không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hủy đơn', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

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

  Future<void> _showInviteDialog() async {
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.key_outlined, color: AppTheme.accent),
              SizedBox(width: 8),
              Text('Nhập mã mời Fandom'),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fandom này là không gian riêng tư. Bạn cần có mã mời hợp lệ do Chủ Fandom cấp để tham gia.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: codeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Mã mời (Invite Code)',
                    hintText: 'VD: VIP2026',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Vui lòng nhập mã mời.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSubmitting = true);

                      final fandomProvider = context.read<FandomProvider>();
                      final res = await fandomProvider.joinByInvite(codeController.text.trim());

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;

                      if (res['success'] == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['message'] ?? 'Gia nhập Fandom thành công!'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                        _loadFandom();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['error'] ?? 'Mã mời không hợp lệ.'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Gia nhập'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_fandom == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('Không tìm thấy thông tin Fandom.'),
        ),
      );
    }

    final fandom = _fandom!;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Banner Sliver AppBar with Real Cloudinary Asset
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
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
                  // Scrim Gradient
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black54, Colors.transparent, Colors.black87],
                        stops: [0.0, 0.4, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  // Real Avatar & Community Title
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
                              BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (fandom.avatarUrl != null && fandom.avatarUrl!.isNotEmpty)
                              ? Image.network(
                                  fandom.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _avatarFallback(fandom.name),
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
                                  shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '@${fandom.slug}',
                                style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
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

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          fandom.category,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: fandom.admissionMode == 'OPEN'
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: fandom.admissionMode == 'OPEN' ? Colors.green : Colors.amber,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          fandom.admissionMode == 'OPEN' ? 'Gia nhập Tự do' : 'Cần xét duyệt',
                          style: TextStyle(
                            color: fandom.admissionMode == 'OPEN' ? Colors.greenAccent : Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Stats Row
                  Row(
                    children: [
                      _StatChip(icon: Icons.people_alt, label: '${fandom.memberCount} Thành viên'),
                      const SizedBox(width: 12),
                      _StatChip(
                        icon: Icons.person_outline,
                        label: 'Chủ Fandom: ${fandom.ownerName}',
                        onTap: () {
                          UserCardDialog.show(
                            context,
                            identifier: fandom.ownerId.isNotEmpty
                                ? fandom.ownerId
                                : (fandom.ownerUsername ?? fandom.ownerName),
                            fallbackName: fandom.ownerName,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Dedicated Creator / Owner Card (Bấm vào để mở thẻ xem nhanh hồ sơ cá nhân)
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
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppTheme.primary,
                            backgroundImage: (fandom.ownerAvatarUrl != null && fandom.ownerAvatarUrl!.isNotEmpty)
                                ? NetworkImage(fandom.ownerAvatarUrl!)
                                : null,
                            child: (fandom.ownerAvatarUrl == null || fandom.ownerAvatarUrl!.isEmpty)
                                ? Text(
                                    fandom.ownerName.isNotEmpty ? fandom.ownerName[0].toUpperCase() : 'U',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
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
                                    const Text('Chủ sở hữu / Người sáng lập: ', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                    Flexible(
                                      child: Text(
                                        fandom.ownerName,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
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
                                  style: const TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Xem hồ sơ', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                SizedBox(width: 4),
                                Icon(Icons.touch_app_outlined, size: 13, color: Colors.white),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Button Area (FR-04)
                  if (_isActionLoading) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Đang xử lý yêu cầu...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ] else if (fandom.isOwner || (auth.isAuthenticated && auth.currentUser?.id.toString() == fandom.ownerId)) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary, width: 1.2),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, color: AppTheme.primary, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Bạn là Chủ sở hữu Fandom này (Owner)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (fandom.isMember) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.8), width: 1),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'ĐÃ THAM GIA • THÀNH VIÊN',
                                    style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error, width: 1.2),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _handleLeave,
                          icon: const Icon(Icons.exit_to_app, size: 18),
                          label: const Text('Rời Fandom', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ] else if (fandom.isPendingRequest) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.8), width: 1),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.hourglass_top, color: Colors.amberAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'ĐANG CHỜ DUYỆT GIA NHẬP',
                                    style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _handleCancelRequest,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Hủy yêu cầu', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ] else if (!fandom.isPublic) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppTheme.surfaceLight,
                        foregroundColor: AppTheme.accent,
                        side: const BorderSide(color: AppTheme.accent, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _showInviteDialog,
                      icon: const Icon(Icons.key_outlined),
                      label: const Text(
                        'FANDOM RIÊNG TƯ • NHẬP MÃ MỜI ĐỂ GIA NHẬP',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _handleJoin,
                      icon: Icon(fandom.admissionMode == 'OPEN' ? Icons.group_add : Icons.assignment_ind_outlined),
                      label: Text(
                        fandom.admissionMode == 'OPEN'
                            ? 'THAM GIA FANDOM NGAY'
                            : 'GỬI ĐƠN XÉT DUYỆT GIA NHẬP',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),

                  // Media Gallery / Illustrations Section (FR-02)
                  if (fandom.illustrationUrls.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.photo_library_outlined, size: 20, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        const Text(
                          'Bộ sưu tập & Đa phương tiện',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${fandom.illustrationUrls.length} tệp',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: fandom.illustrationUrls.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final url = fandom.illustrationUrls[index];
                          final isVideo = _isVideoUrl(url);
                          return _MediaCard(
                            url: url,
                            isVideo: isVideo,
                            onTap: () {
                              if (isVideo) {
                                _openMediaUrl(url);
                              } else {
                                _showImageDialog(context, url);
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Description
                  const Text('Giới thiệu Fandom', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    fandom.description?.isNotEmpty == true
                        ? fandom.description!
                        : 'Chưa có mô tả chi tiết cho Fandom này.',
                    style: const TextStyle(color: AppTheme.textSecondary, height: 1.5, fontSize: 14),
                  ),
                  const SizedBox(height: 24),

                  // Rules / TOS
                  if (fandom.rulesTos != null && fandom.rulesTos!.isNotEmpty) ...[
                    const Text('Nội quy & Điều khoản', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.surfaceLight),
                      ),
                      child: Text(
                        fandom.rulesTos!,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Teaser for Next Phases
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.surfaceLight),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.accent),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Kênh Chat Thời gian thực, Voice Room và Gói Role Membership 4 cấp đang được kích hoạt ở Pha 2 và Pha 3!',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.contains('/video/upload/');
  }

  static Future<void> _openMediaUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.all(24),
                  child: const Text('Không thể tải ảnh.', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
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
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final String url;
  final bool isVideo;
  final VoidCallback onTap;

  const _MediaCard({
    required this.url,
    required this.isVideo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // For Cloudinary videos, derive automatic frame thumbnail if possible
    final String displayUrl = isVideo && url.contains('/video/upload/')
        ? url.replaceFirst('/video/upload/', '/video/upload/so_1/').replaceAll(RegExp(r'\.(mp4|webm|mov)$'), '.jpg')
        : url;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              displayUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: AppTheme.surfaceLight,
                child: Icon(
                  isVideo ? Icons.videocam : Icons.broken_image,
                  color: AppTheme.textSecondary,
                  size: 32,
                ),
              ),
            ),
            if (isVideo) ...[
              Container(color: Colors.black38),
              const Center(
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 26),
                ),
              ),
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, size: 10, color: Colors.white),
                      SizedBox(width: 3),
                      Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _StatChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onTap != null ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: onTap != null
            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 0.8)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onTap != null ? AppTheme.primary : AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: onTap != null ? FontWeight.w600 : FontWeight.normal,
              color: onTap != null ? Colors.white : AppTheme.textSecondary,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.touch_app_outlined, size: 12, color: AppTheme.primary),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: chip,
      );
    }
    return chip;
  }
}
