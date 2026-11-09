import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fandom_provider.dart';
import '../../widgets/navigation/app_top_nav_bar.dart';
import 'dialogs/join_by_invite_dialog.dart';
import 'widgets/directory_filter_bar.dart';
import 'widgets/fandom_card.dart';

/// Public Fandom discovery directory screen.
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
      final fandomProvider =
          Provider.of<FandomProvider>(context, listen: false);
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
    final palette = context.palette;
    final auth = context.watch<AuthProvider>();
    final fandomProvider = context.watch<FandomProvider>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: const AppTopNavBar(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          if (!auth.isAuthenticated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Vui lòng đăng nhập để tạo không gian Fandom mới!',
                ),
              ),
            );
            context.go('/login');
            return;
          }
          context.push('/fandoms/create');
        },
        icon: const Icon(Icons.add),
        label: const Text(
          'Tạo Fandom mới',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => fandomProvider.fetchPublicFandoms(),
        child: Column(
          children: [
            DirectoryFilterBar(
              searchController: _searchController,
              fandomProvider: fandomProvider,
              authProvider: auth,
            ),
            Expanded(
              child: fandomProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : fandomProvider.fandoms.isEmpty
                      ? _buildEmptyState(context, palette, auth)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final int crossAxisCount =
                                constraints.maxWidth >= 1040
                                    ? 3
                                    : (constraints.maxWidth >= 680 ? 2 : 1);
                            return GridView.builder(
                              padding: const EdgeInsets.all(20),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisExtent: 256,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: fandomProvider.fandoms.length,
                              itemBuilder: (context, index) {
                                final fandom = fandomProvider.fandoms[index];
                                return FandomCard(fandom: fandom);
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

  Widget _buildEmptyState(
    BuildContext context,
    AppPalette palette,
    AuthProvider auth,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_off_outlined,
              size: 64,
              color: palette.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              'Chưa có Fandom nào phù hợp',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hãy thử tìm kiếm với từ khóa khác, nhập mã mời Fandom riêng tư hoặc tạo Fandom đầu tiên!',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      JoinByInviteDialog.show(context, navigateOnSuccess: true),
                  icon: const Icon(Icons.vpn_key_outlined, size: 16),
                  label: const Text('Nhập mã mời Fandom'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (!auth.isAuthenticated) {
                      context.go('/login');
                    } else {
                      context.push('/fandoms/create');
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tạo Fandom mới'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
