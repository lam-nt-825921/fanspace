import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fandom_provider.dart';

class FandomDetailScreen extends StatefulWidget {
  final String slug;
  const FandomDetailScreen({super.key, required this.slug});

  @override
  State<FandomDetailScreen> createState() => _FandomDetailScreenState();
}

class _FandomDetailScreenState extends State<FandomDetailScreen> {
  FandomDetailModel? _fandom;
  bool _isLoading = true;

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
          // Banner Sliver AppBar
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent.withValues(alpha: 0.9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white,
                        child: Text(
                          fandom.name.isNotEmpty ? fandom.name[0].toUpperCase() : 'F',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
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
                  // Title & Badge Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fandom.name,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${fandom.slug}',
                              style: const TextStyle(color: AppTheme.accent, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
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
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Stats Row
                  Row(
                    children: [
                      _StatChip(icon: Icons.people_alt, label: '${fandom.memberCount} Thành viên'),
                      const SizedBox(width: 12),
                      _StatChip(icon: Icons.person_outline, label: 'Chủ: ${fandom.ownerName}'),
                      const SizedBox(width: 12),
                      _StatChip(
                        icon: fandom.admissionMode == 'OPEN' ? Icons.lock_open : Icons.lock_outline,
                        label: fandom.admissionMode == 'OPEN' ? 'Tự do' : 'Cần xét duyệt',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action Button
                  if (fandom.isOwner || (auth.isAuthenticated && auth.currentUser?.id.toString() == fandom.ownerId)) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, color: AppTheme.primary),
                            SizedBox(width: 8),
                            Text(
                              'Bạn là Chủ sở hữu Fandom này (Owner)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppTheme.primary,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              fandom.admissionMode == 'OPEN'
                                  ? 'Đã tham gia Fandom thành công!'
                                  : 'Đã gửi yêu cầu xét duyệt gia nhập đến Chủ Fandom!',
                            ),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      },
                      icon: const Icon(Icons.group_add),
                      label: Text(
                        fandom.admissionMode == 'OPEN' ? 'THAM GIA FANDOM NGAY' : 'GỬI ĐƠN XÉT DUYỆT GIA NHẬP',
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),

                  // Description
                  const Text('Giới thiệu Fandom', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    fandom.description?.isNotEmpty == true
                        ? fandom.description!
                        : 'Chưa có mô tả chi tiết cho Fandom này.',
                    style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // Rules / TOS
                  if (fandom.rulesTos != null && fandom.rulesTos!.isNotEmpty) ...[
                    const Text('Nội quy & Điều khoản', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        fandom.rulesTos!,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
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
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
