import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/fandom_provider.dart';
import '../dialogs/join_by_invite_dialog.dart';

/// Search, category filter, and sort bar for the public Fandom directory.
class DirectoryFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final FandomProvider fandomProvider;
  final AuthProvider authProvider;

  const DirectoryFilterBar({
    super.key,
    required this.searchController,
    required this.fandomProvider,
    required this.authProvider,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm Fandom theo tên, @slug hoặc idol...',
                    prefixIcon: Icon(
                      Icons.search,
                      color: palette.textSecondary,
                    ),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              searchController.clear();
                              fandomProvider.setSearchQuery('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: palette.background,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  onChanged: (value) => fandomProvider.setSearchQuery(value),
                  onSubmitted: (value) => fandomProvider.setSearchQuery(value),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: 'Tác vụ nhanh Fandom',
                onSelected: (val) {
                  if (val == 'create') {
                    if (!authProvider.isAuthenticated) {
                      context.go('/login');
                    } else {
                      context.push('/fandoms/create');
                    }
                  } else if (val == 'invite') {
                    JoinByInviteDialog.show(context, navigateOnSuccess: true);
                  } else if (val == 'refresh') {
                    fandomProvider.fetchPublicFandoms();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'create',
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Tạo Fandom mới',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'invite',
                    child: Row(
                      children: [
                        Icon(
                          Icons.vpn_key_outlined,
                          size: 18,
                          color: AppTheme.accent,
                        ),
                        SizedBox(width: 8),
                        Text('Gia nhập bằng Mã mời'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 18),
                        SizedBox(width: 8),
                        Text('Làm mới danh sách'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Tác vụ',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: fandomProvider.categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = fandomProvider.categories[index];
                      final isSelected =
                          fandomProvider.selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (_) => fandomProvider.selectCategory(cat),
                        selectedColor: AppTheme.primary,
                        backgroundColor: palette.background,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : palette.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.primary
                                : palette.border,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: 'Sắp xếp danh sách',
                onSelected: fandomProvider.setSortBy,
                itemBuilder: (_) => [
                  _sortMenuItem(
                    'popular',
                    'Phổ biến nhất',
                    Icons.trending_up_rounded,
                    fandomProvider.sortBy,
                  ),
                  _sortMenuItem(
                    'newest',
                    'Mới khởi tạo',
                    Icons.fiber_new_outlined,
                    fandomProvider.sortBy,
                  ),
                  _sortMenuItem(
                    'name_asc',
                    'Tên A - Z',
                    Icons.sort_by_alpha_rounded,
                    fandomProvider.sortBy,
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 16,
                        color: palette.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _sortLabel(fandomProvider.sortBy),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: palette.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sortLabel(String sortBy) {
    switch (sortBy) {
      case 'newest':
        return 'Mới nhất';
      case 'name_asc':
        return 'Tên A - Z';
      default:
        return 'Phổ biến';
    }
  }

  PopupMenuItem<String> _sortMenuItem(
    String value,
    String label,
    IconData icon,
    String current,
  ) {
    final selected = value == current;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? AppTheme.primary : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppTheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
