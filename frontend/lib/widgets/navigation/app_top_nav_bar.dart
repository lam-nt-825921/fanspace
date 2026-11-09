import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/widgets/theme_toggle_button.dart';
import '../../screens/home/dialogs/join_by_invite_dialog.dart';
import '../../screens/home/dialogs/my_fandoms_quick_switcher_dialog.dart';
import '../../screens/profile/user_card_dialog.dart';
import '../../screens/profile/user_settings_dialog.dart';

/// Unified top navigation bar providing consistent page-to-page navigation and user action options.
class AppTopNavBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBackButton;
  final Key? backButtonKey;
  final VoidCallback? onBack;
  final String fallbackRoute;
  final List<Widget>? extraActions;

  const AppTopNavBar({
    super.key,
    this.title,
    this.showBackButton = false,
    this.backButtonKey,
    this.onBack,
    this.fallbackRoute = '/',
    this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(62);

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = context.watch<AuthProvider?>();
    final isAuthenticated = auth?.isAuthenticated == true;
    final isWide = MediaQuery.of(context).size.width >= 820;

    return AppBar(
      backgroundColor: palette.surface,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: palette.border),
      ),
      leading: showBackButton
          ? IconButton(
              key: backButtonKey,
              tooltip: 'Quay lại',
              icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
              onPressed: () => _handleBack(context),
            )
          : null,
      title: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.go('/'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.rocket_launch,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'FanSpace',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (title != null && title!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
          if (isWide) ...[
            const SizedBox(width: 20),
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.explore_outlined, size: 17),
              label: const Text('Khám phá'),
              style: TextButton.styleFrom(
                foregroundColor: palette.textPrimary,
              ),
            ),
            if (isAuthenticated)
              TextButton.icon(
                onPressed: () => MyFandomsQuickSwitcherDialog.show(context),
                icon: const Icon(Icons.workspaces_rounded, size: 17),
                label: const Text('Fandom của tôi'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.textPrimary,
                ),
              ),
            TextButton.icon(
              onPressed: () =>
                  JoinByInviteDialog.show(context, navigateOnSuccess: true),
              icon: const Icon(Icons.vpn_key_outlined, size: 17),
              label: const Text('Nhập mã mời'),
              style: TextButton.styleFrom(
                foregroundColor: palette.textPrimary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...?extraActions,
        if (!isWide)
          PopupMenuButton<String>(
            tooltip: 'Menu điều hướng nhanh',
            icon: Icon(Icons.apps_rounded, color: palette.textPrimary),
            onSelected: (val) {
              if (val == 'home') {
                context.go('/');
              } else if (val == 'my_fandoms') {
                MyFandomsQuickSwitcherDialog.show(context);
              } else if (val == 'join_invite') {
                JoinByInviteDialog.show(context, navigateOnSuccess: true);
              } else if (val == 'create_fandom') {
                if (!isAuthenticated) {
                  context.go('/login');
                } else {
                  context.push('/fandoms/create');
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'home',
                child: Row(
                  children: [
                    Icon(Icons.explore_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Khám phá Cộng đồng'),
                  ],
                ),
              ),
              if (isAuthenticated)
                const PopupMenuItem(
                  value: 'my_fandoms',
                  child: Row(
                    children: [
                      Icon(Icons.workspaces_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Fandom của tôi'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'join_invite',
                child: Row(
                  children: [
                    Icon(Icons.vpn_key_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Nhập mã mời Fandom'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'create_fandom',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Tạo Fandom mới'),
                  ],
                ),
              ),
            ],
          ),
        if (isAuthenticated && auth != null) ...[
          _buildUserPopupMenu(context, auth, palette),
        ] else ...[
          IconButton(
            tooltip: 'Cổng Quản trị Admin',
            icon: const Icon(
              Icons.shield_outlined,
              color: AppTheme.primary,
            ),
            onPressed: () => context.push('/admin/login'),
          ),
          TextButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.login, color: AppTheme.primary, size: 18),
            label: const Text(
              'Đăng nhập',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (isWide)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ElevatedButton(
                onPressed: () => context.go('/register'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                child: const Text('Đăng ký'),
              ),
            ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: ThemeToggleButton(),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildUserPopupMenu(
    BuildContext context,
    AuthProvider auth,
    AppPalette palette,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Tài khoản',
      onSelected: (value) {
        if (value == 'view_card') {
          if (auth.currentUser != null) {
            UserCardDialog.show(context, identifier: auth.currentUser!.id);
          }
        } else if (value == 'my_fandoms') {
          MyFandomsQuickSwitcherDialog.show(context);
        } else if (value == 'settings') {
          UserSettingsDialog.show(context);
        } else if (value == 'admin_portal') {
          context.push('/admin/permissions');
        } else if (value == 'logout') {
          auth.logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                auth.currentUser?.displayName ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              Text(
                '@${auth.currentUser?.username}',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'view_card',
          child: Row(
            children: [
              Icon(Icons.badge_outlined, color: AppTheme.accent, size: 18),
              SizedBox(width: 10),
              Text('Hồ sơ của tôi'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'my_fandoms',
          child: Row(
            children: [
              Icon(Icons.workspaces_rounded, color: AppTheme.primary, size: 18),
              SizedBox(width: 10),
              Text('Fandom của tôi'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(
                Icons.settings_outlined,
                color: AppTheme.primary,
                size: 18,
              ),
              SizedBox(width: 10),
              Text(
                'Tất cả cài đặt',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (auth.currentUser?.isAdmin == true)
          const PopupMenuItem(
            value: 'admin_portal',
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Color(0xFF2563EB),
                  size: 18,
                ),
                SizedBox(width: 10),
                Text('Quản trị hệ thống'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppTheme.error),
              SizedBox(width: 10),
              Text('Đăng xuất', style: TextStyle(color: AppTheme.error)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: CircleAvatar(
          backgroundColor: AppTheme.primary,
          radius: 17,
          backgroundImage: (auth.currentUser?.avatarUrl != null &&
                  auth.currentUser!.avatarUrl!.isNotEmpty)
              ? NetworkImage(auth.currentUser!.avatarUrl!)
              : null,
          child: (auth.currentUser?.avatarUrl == null ||
                  auth.currentUser!.avatarUrl!.isEmpty)
              ? Text(
                  (auth.currentUser?.displayName.isNotEmpty == true)
                      ? auth.currentUser!.displayName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
