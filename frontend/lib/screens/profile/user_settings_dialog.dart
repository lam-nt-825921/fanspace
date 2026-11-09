/// Modal dialog for personal profile settings, bank account, security, my fandoms, and blacklist.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/theme/theme_toggle_button.dart';
import 'tabs/profile_appearance_tab.dart';
import 'tabs/profile_bank_tab.dart';
import 'tabs/profile_blacklist_tab.dart';
import 'tabs/profile_my_fandoms_tab.dart';
import 'tabs/profile_security_tab.dart';

class UserSettingsDialog extends StatefulWidget {
  final int initialTab;

  const UserSettingsDialog({
    super.key,
    this.initialTab = 0,
  });

  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UserSettingsDialog(initialTab: initialTab),
    );
  }

  @override
  State<UserSettingsDialog> createState() => _UserSettingsDialogState();
}

class _UserSettingsDialogState extends State<UserSettingsDialog> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 700;

    return Dialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 880 : 520,
          maxHeight: size.height * 0.86,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border(
                    bottom: BorderSide(color: palette.border),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.settings,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Cài đặt & Quản lý Tài khoản',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const ThemeToggleButton(compact: true),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.close, color: palette.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isWide
                    ? Row(
                        children: [
                          SizedBox(
                            width: 220,
                            child: Container(
                              color: palette.surfaceElevated,
                              child: ListView(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                children: [
                                  _buildSidebarItem(
                                    0,
                                    Icons.person_outline,
                                    'Hồ sơ cá nhân',
                                  ),
                                  _buildSidebarItem(
                                    1,
                                    Icons.account_balance_outlined,
                                    'Tài khoản ngân hàng',
                                  ),
                                  _buildSidebarItem(
                                    2,
                                    Icons.security_outlined,
                                    'Bảo mật & Phiên',
                                  ),
                                  _buildSidebarItem(
                                    3,
                                    Icons.rocket_launch_outlined,
                                    'Fandom của tôi',
                                  ),
                                  _buildSidebarItem(
                                    4,
                                    Icons.block_outlined,
                                    'Danh sách chặn',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: palette.border,
                          ),
                          Expanded(child: _buildTabContent()),
                        ],
                      )
                    : Column(
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                _buildChipTab(0, 'Hồ sơ'),
                                _buildChipTab(1, 'Ngân hàng'),
                                _buildChipTab(2, 'Bảo mật'),
                                _buildChipTab(3, 'Fandoms'),
                                _buildChipTab(4, 'Blacklist'),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: palette.border),
                          Expanded(child: _buildTabContent()),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String label) {
    final palette = context.palette;
    final isSelected = _selectedTab == index;

    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppTheme.primary : palette.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipTab(int index, String label) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          if (val) setState(() => _selectedTab = index);
        },
        selectedColor: AppTheme.primary.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return const ProfileAppearanceTab();
      case 1:
        return const ProfileBankTab();
      case 2:
        return const ProfileSecurityTab();
      case 3:
        return const ProfileMyFandomsTab();
      case 4:
        return const ProfileBlacklistTab();
      default:
        return const SizedBox();
    }
  }
}
