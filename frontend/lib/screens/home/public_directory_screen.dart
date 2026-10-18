import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fandom_provider.dart';
import '../auth/login_screen.dart';
import '../auth/widgets/theme_toggle_button.dart';
import '../auth/widgets/active_sessions_dialog.dart';
import '../auth/widgets/email_otp_dialog.dart';
import '../auth/widgets/oauth_set_password_dialog.dart';
import 'create_fandom_screen.dart';
import 'fandom_detail_screen.dart';

class PublicDirectoryScreen extends StatefulWidget {
  const PublicDirectoryScreen({super.key});

  @override
  State<PublicDirectoryScreen> createState() => _PublicDirectoryScreenState();
}

class _PublicDirectoryScreenState extends State<PublicDirectoryScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fandomProvider = Provider.of<FandomProvider>(context, listen: false);
      fandomProvider.fetchCategories();
      fandomProvider.fetchPublicFandoms();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final fandomProvider = context.watch<FandomProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.accent]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.rocket_launch, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text('FanSpace', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          ],
        ),
        actions: [
          if (auth.isAuthenticated) ...[
            // Coin Balance Chip
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${auth.currentUser?.coinBalance ?? 0} Coins',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            // User Avatar Menu
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  auth.logout();
                } else if (value == 'sessions') {
                  ActiveSessionsDialog.show(context);
                } else if (value == 'verify_email') {
                  if (auth.currentUser?.email != null) {
                    EmailOtpDialog.show(context, email: auth.currentUser!.email);
                  }
                } else if (value == 'set_password') {
                  if (auth.currentUser?.email != null) {
                    OAuthSetPasswordDialog.show(context, email: auth.currentUser!.email);
                  }
                } else if (value == 'delete_account') {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xác nhận xóa tài khoản?'),
                      content: const Text('Tài khoản của bạn sẽ bị vô hiệu hóa và đăng xuất khỏi mọi thiết bị.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                          onPressed: () {
                            Navigator.pop(ctx);
                            auth.deleteAccount();
                          },
                          child: const Text('Xóa tài khoản'),
                        ),
                      ],
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(auth.currentUser?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('@${auth.currentUser?.username}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      if (auth.currentUser?.isEmailVerified == false) ...[
                        const SizedBox(height: 4),
                        const Text('⚠️ Chưa xác thực email', style: TextStyle(color: AppTheme.warning, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'sessions',
                  child: Row(
                    children: [
                      Icon(Icons.devices_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Quản lý thiết bị / phiên'),
                    ],
                  ),
                ),
                if (auth.currentUser?.hasPassword == false)
                  const PopupMenuItem(
                    value: 'set_password',
                    child: Row(
                      children: [
                        Icon(Icons.password_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Thiết lập mật khẩu cá nhân'),
                      ],
                    ),
                  ),
                if (auth.currentUser?.isEmailVerified == false)
                  const PopupMenuItem(
                    value: 'verify_email',
                    child: Row(
                      children: [
                        Icon(Icons.mark_email_read_rounded, size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('Xác thực Email ngay'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete_account',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                      SizedBox(width: 8),
                      Text('Xóa tài khoản', style: TextStyle(color: AppTheme.error)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18, color: AppTheme.error),
                      SizedBox(width: 8),
                      Text('Đăng xuất', style: TextStyle(color: AppTheme.error)),
                    ],
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CircleAvatar(
                  backgroundColor: AppTheme.primary,
                  radius: 18,
                  child: Text(
                    (auth.currentUser?.displayName.isNotEmpty == true)
                        ? auth.currentUser!.displayName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
              icon: const Icon(Icons.login, color: AppTheme.primary),
              label: const Text('Đăng nhập', style: TextStyle(color: AppTheme.primary)),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: ThemeToggleButton(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        onPressed: () {
          if (!auth.isAuthenticated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vui lòng đăng nhập để tạo không gian Fandom mới!')),
            );
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateFandomScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Tạo Fandom mới', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await fandomProvider.fetchPublicFandoms();
        },
        child: Column(
          children: [
            // Search Bar & Filter Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              color: AppTheme.surface,
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm Fandom theo tên, slug hoặc idol...',
                      prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                fandomProvider.setSearchQuery('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onSubmitted: (value) => fandomProvider.setSearchQuery(value),
                  ),
                  const SizedBox(height: 10),
                  // Category Chips Scroll
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: fandomProvider.categories.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = fandomProvider.categories[index];
                        final isSelected = fandomProvider.selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) => fandomProvider.selectCategory(cat),
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.background,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppTheme.primary : AppTheme.surfaceLight,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Fandom Cards Grid / List
            Expanded(
              child: fandomProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : fandomProvider.fandoms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.explore_off_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              const Text('Chưa có Fandom nào phù hợp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              const Text('Hãy thử tìm kiếm với từ khóa khác hoặc tạo Fandom đầu tiên!', style: TextStyle(color: AppTheme.textSecondary)),
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            // Responsive: Grid on wide screens, List on mobile
                            final isWide = constraints.maxWidth > 700;
                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: isWide ? 3 : 1,
                                childAspectRatio: isWide ? 1.2 : 1.7,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: fandomProvider.fandoms.length,
                              itemBuilder: (context, index) {
                                final fandom = fandomProvider.fandoms[index];
                                return _FandomCard(fandom: fandom);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FandomCard extends StatelessWidget {
  final FandomSummaryModel fandom;
  const _FandomCard({required this.fandom});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FandomDetailScreen(slug: fandom.slug),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner Header
            Container(
              height: 70,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.8),
                    AppTheme.accent.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        fandom.category,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card Body
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primary,
                        child: Text(
                          fandom.name.isNotEmpty ? fandom.name[0].toUpperCase() : 'F',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fandom.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '@${fandom.slug}',
                              style: const TextStyle(color: AppTheme.accent, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (fandom.description != null && fandom.description!.isNotEmpty)
                    Text(
                      fandom.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.people_alt_outlined, size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${fandom.memberCount} thành viên',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                      const Text(
                        'Khám phá →',
                        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
