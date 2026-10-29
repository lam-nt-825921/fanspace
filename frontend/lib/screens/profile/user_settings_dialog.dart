import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../auth/widgets/active_sessions_dialog.dart';
import '../auth/widgets/email_otp_dialog.dart';
import '../auth/widgets/oauth_set_password_dialog.dart';

class UserSettingsDialog extends StatefulWidget {
  const UserSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const UserSettingsDialog(),
    );
  }

  @override
  State<UserSettingsDialog> createState() => _UserSettingsDialogState();
}

class _UserSettingsDialogState extends State<UserSettingsDialog> {
  int _selectedTab = 0; // 0: Profile, 1: Bank, 2: Security, 3: Fandoms, 4: Blacklist

  // Profile Form Controllers
  late TextEditingController _displayNameController;
  late TextEditingController _avatarUrlController;
  late TextEditingController _bannerUrlController;
  late TextEditingController _bioController;
  bool _isUploadingAvatar = false;
  bool _isUploadingBanner = false;

  // Bank Form Controllers
  final _bankNameController = TextEditingController(text: 'MB Bank (Ngân hàng Quân Đội)');
  final _accountNumberController = TextEditingController(text: '0987654321');
  final _accountNameController = TextEditingController(text: 'NGUYEN VAN A');

  // Change Password Controllers
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();
  bool _isChangingPassword = false;

  // Mock Blacklist
  final List<Map<String, String>> _mockBlacklist = [
    {
      'id': '1',
      'name': 'Spammer Bot 01',
      'username': 'bot_spammer_01',
      'reason': 'Spam tin nhắn quảng cáo không phù hợp',
      'date': '18/10/2026',
    },
    {
      'id': '2',
      'name': 'Toxic User X',
      'username': 'toxic_user_x',
      'reason': 'Vi phạm quy tắc ứng xử cộng đồng',
      'date': '19/10/2026',
    },
  ];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    _displayNameController = TextEditingController(text: user?.displayName ?? '');
    _avatarUrlController = TextEditingController(text: user?.avatarUrl ?? '');
    _bannerUrlController = TextEditingController(text: user?.bannerUrl ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    _bannerUrlController.dispose();
    _bioController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage({required bool isAvatar}) async {
    final auth = context.read<AuthProvider>();
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể đọc dữ liệu tệp được chọn.')),
          );
        }
        return;
      }

      // Max size limit: 5MB
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kích thước ảnh tối đa là 5MB.')),
          );
        }
        return;
      }

      setState(() {
        if (isAvatar) {
          _isUploadingAvatar = true;
        } else {
          _isUploadingBanner = true;
        }
      });

      final url = await auth.uploadMedia(
        bytes: bytes,
        filename: file.name,
        target: isAvatar ? 'USER_AVATAR' : 'USER_BANNER',
      );

      if (!mounted) return;
      setState(() {
        if (isAvatar) {
          _isUploadingAvatar = false;
          if (url != null) {
            _avatarUrlController.text = url;
          }
        } else {
          _isUploadingBanner = false;
          if (url != null) {
            _bannerUrlController.text = url;
          }
        }
      });

      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAvatar ? 'Tải ảnh đại diện thành công!' : 'Tải ảnh bìa thành công!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? 'Tải ảnh thất bại.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingAvatar = false;
        _isUploadingBanner = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tải ảnh: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSaveProfile() async {
    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(
      displayName: _displayNameController.text,
      avatarUrl: _avatarUrlController.text,
      bannerUrl: _bannerUrlController.text,
      bio: _bioController.text,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cập nhật hồ sơ cá nhân thành công!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Không thể cập nhật hồ sơ.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleChangePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isChangingPassword = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.changePassword(
      oldPassword: _oldPasswordController.text,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isChangingPassword = false);

    if (success) {
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đổi mật khẩu thành công!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Đổi mật khẩu không thành công.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 700;

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 850 : 500,
          maxHeight: size.height * 0.85,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              // Dialog Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings, color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Cài đặt & Quản lý Tài khoản',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Dialog Body
              Expanded(
                child: isWide
                    ? Row(
                        children: [
                          // Left Sidebar Tabs
                          SizedBox(
                            width: 220,
                            child: Container(
                              color: isDark ? Colors.black12 : const Color(0xFFF8F9FA),
                              child: ListView(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                children: [
                                  _buildSidebarItem(0, Icons.person_outline, 'Hồ sơ cá nhân'),
                                  _buildSidebarItem(1, Icons.account_balance_outlined, 'Tài khoản ngân hàng'),
                                  _buildSidebarItem(2, Icons.security_outlined, 'Bảo mật & Phiên'),
                                  _buildSidebarItem(3, Icons.rocket_launch_outlined, 'Fandom của tôi'),
                                  _buildSidebarItem(4, Icons.block_outlined, 'Danh sách chặn'),
                                ],
                              ),
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                          // Right Content
                          Expanded(
                            child: _buildTabContent(context, textColor, subColor, isDark),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          // Horizontal Scrollable Tabs on mobile
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          const Divider(height: 1),
                          Expanded(
                            child: _buildTabContent(context, textColor, subColor, isDark),
                          ),
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
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
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
        selectedColor: AppTheme.primary.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, Color textColor, Color subColor, bool isDark) {
    switch (_selectedTab) {
      case 0:
        return _buildProfileTab(context, textColor, subColor, isDark);
      case 1:
        return _buildBankTab(context, textColor, subColor, isDark);
      case 2:
        return _buildSecurityTab(context, textColor, subColor, isDark);
      case 3:
        return _buildFandomsTab(context, textColor, subColor, isDark);
      case 4:
        return _buildBlacklistTab(context, textColor, subColor, isDark);
      default:
        return const SizedBox();
    }
  }

  // 1. Profile Tab
  Widget _buildProfileTab(BuildContext context, Color textColor, Color subColor, bool isDark) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hồ sơ diện mạo cá nhân',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Thông tin diện mạo (ảnh bìa, ảnh đại diện, tiểu sử) sẽ hiển thị công khai trên thẻ hồ sơ của bạn.',
            style: TextStyle(fontSize: 13, color: subColor),
          ),
          const SizedBox(height: 20),

          // --- LIVE BANNER & AVATAR PREVIEW ---
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner Box with Upload Button
                Stack(
                  children: [
                    Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.7),
                            AppTheme.accent.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _bannerUrlController.text.isNotEmpty
                          ? Image.network(
                              _bannerUrlController.text,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(),
                            )
                          : null,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: ElevatedButton.icon(
                        onPressed: _isUploadingBanner ? null : () => _pickAndUploadImage(isAvatar: false),
                        icon: _isUploadingBanner
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt_outlined, size: 16),
                        label: Text(
                          _isUploadingBanner ? 'Đang tải...' : 'Đổi ảnh bìa',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  ],
                ),

                // Avatar and Upload Button Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Avatar overlapping banner
                      Transform.translate(
                        offset: const Offset(0, -30),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                              width: 3.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: AppTheme.primary,
                            backgroundImage: _avatarUrlController.text.isNotEmpty
                                ? NetworkImage(_avatarUrlController.text)
                                : null,
                            child: _avatarUrlController.text.isEmpty
                                ? Text(
                                    (user?.displayName.isNotEmpty == true)
                                        ? user!.displayName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: OutlinedButton.icon(
                          onPressed: _isUploadingAvatar ? null : () => _pickAndUploadImage(isAvatar: true),
                          icon: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_front_outlined, size: 16),
                          label: Text(
                            _isUploadingAvatar ? 'Đang tải...' : 'Đổi ảnh đại diện',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Display Name (max 50)
          Text('Tên hiển thị công khai (tối đa 50 ký tự)', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _displayNameController,
            maxLength: 50,
            decoration: const InputDecoration(
              hintText: 'Nhập tên hiển thị của bạn',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),

          // Username (Read-only)
          Text('Tên tài khoản định danh (@username)', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: '@${user?.username ?? ''}',
            readOnly: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alternate_email, size: 20),
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              filled: true,
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          // Bio (max 250)
          Text('Giới thiệu bản thân / Tiểu sử (tối đa 250 ký tự)', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 250,
            decoration: const InputDecoration(
              hintText: 'Chia sẻ đôi nét về bạn hoặc idol mà bạn yêu thích...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),

          // Advanced / Direct URLs Expansion Tile
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Tùy chỉnh liên kết URL ảnh trực tiếp',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subColor),
              ),
              children: [
                const SizedBox(height: 6),
                Text('URL ảnh đại diện', style: TextStyle(fontSize: 12, color: subColor)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _avatarUrlController,
                  decoration: const InputDecoration(
                    hintText: 'https://res.cloudinary.com/.../avatar.jpg',
                    prefixIcon: Icon(Icons.link, size: 18),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text('URL ảnh bìa', style: TextStyle(fontSize: 12, color: subColor)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _bannerUrlController,
                  decoration: const InputDecoration(
                    hintText: 'https://res.cloudinary.com/.../banner.jpg',
                    prefixIcon: Icon(Icons.link, size: 18),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Save Button
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: auth.isLoading ? null : _handleSaveProfile,
              icon: auth.isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Lưu thay đổi hồ sơ'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Bank Account Tab (Napas VietQR for Owner Monetization)
  Widget _buildBankTab(BuildContext context, Color textColor, Color subColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tài khoản Ngân hàng Thụ hưởng',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Napas 247 VietQR', style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Dùng để nhận tiền doanh thu khi người hâm mộ mua gói Hội viên (Membership) của Fandom.',
            style: TextStyle(fontSize: 13, color: subColor),
          ),
          const SizedBox(height: 24),

          // Bank Card preview
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E3C72).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _bankNameController.text,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  _accountNumberController.text.replaceAllMapped(RegExp(r".{4}"), (match) => "${match.group(0)} "),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CHỦ TÀI KHOẢN', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        Text(
                          _accountNameController.text.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const Text('VIETQR READY', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Bank Form
          Text('Ngân hàng', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _bankNameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.account_balance, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          Text('Số tài khoản ngân hàng', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _accountNumberController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.credit_card, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          Text('Tên chủ tài khoản (in hoa không dấu)', style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _accountNameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã lưu cấu hình tài khoản ngân hàng VietQR!'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Cập nhật tài khoản'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Security Tab (REAL AUTH APIS)
  Widget _buildSecurityTab(BuildContext context, Color textColor, Color subColor, bool isDark) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bảo mật & Quản lý Truy cập',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Quản lý mật khẩu, trạng thái xác thực và các phiên đăng nhập bảo mật.',
            style: TextStyle(fontSize: 13, color: subColor),
          ),
          const SizedBox(height: 20),

          // 1. Email Verification Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: user?.isEmailVerified == true
                    ? AppTheme.success.withValues(alpha: 0.3)
                    : AppTheme.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  user?.isEmailVerified == true ? Icons.mark_email_read : Icons.mail_lock_outlined,
                  color: user?.isEmailVerified == true ? AppTheme.success : AppTheme.warning,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.email ?? '',
                        style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                      ),
                      Text(
                        user?.isEmailVerified == true
                            ? 'Email đã được xác thực an toàn.'
                            : 'Email chưa xác thực. Hãy kích hoạt để bảo vệ tài khoản.',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    ],
                  ),
                ),
                if (user?.isEmailVerified == false)
                  ElevatedButton(
                    onPressed: () {
                      if (user?.email != null) {
                        EmailOtpDialog.show(context, email: user!.email);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Xác thực OTP', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Password Management Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_reset, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      user?.hasPassword == false ? 'Thiết lập Mật khẩu Tài khoản' : 'Đổi Mật khẩu',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (user?.hasPassword == false) ...[
                  Text(
                    'Tài khoản của bạn được khởi tạo bằng Google OAuth2. Bạn có thể thiết lập mật khẩu cá nhân để đăng nhập bằng Email/Password.',
                    style: TextStyle(fontSize: 13, color: subColor),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (user?.email != null) {
                        OAuthSetPasswordDialog.show(context, email: user!.email);
                      }
                    },
                    icon: const Icon(Icons.password, size: 18),
                    label: const Text('Thiết lập mật khẩu ngay'),
                  ),
                ] else ...[
                  Form(
                    key: _passwordFormKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _oldPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu hiện tại',
                            prefixIcon: Icon(Icons.lock_outline, size: 20),
                            isDense: true,
                          ),
                          validator: (val) => val == null || val.isEmpty ? 'Vui lòng nhập mật khẩu cũ.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu mới (tối thiểu 6 ký tự)',
                            prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                            isDense: true,
                          ),
                          validator: (val) {
                            if (val == null || val.length < 6) return 'Mật khẩu mới phải từ 6 ký tự.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Xác nhận mật khẩu mới',
                            prefixIcon: Icon(Icons.vpn_key, size: 20),
                            isDense: true,
                          ),
                          validator: (val) {
                            if (val != _newPasswordController.text) return 'Mật khẩu xác nhận không khớp.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _isChangingPassword ? null : _handleChangePassword,
                            child: _isChangingPassword
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Lưu mật khẩu mới'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Active Sessions Management
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.devices, color: AppTheme.accent, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quản lý Phiên Đăng nhập Thiết bị', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                      Text('Kiểm tra và đăng xuất từ xa khỏi các thiết bị lạ.', style: TextStyle(fontSize: 12, color: subColor)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => ActiveSessionsDialog.show(context),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Xem phiên'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Danger Zone (Delete Account)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vùng Nguy hiểm', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.error)),
                      Text('Vô hiệu hóa vĩnh viễn tài khoản và đăng xuất mọi thiết bị.', style: TextStyle(fontSize: 12, color: subColor)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Xác nhận xóa tài khoản?'),
                        content: const Text('Tài khoản của bạn sẽ bị vô hiệu hóa (Soft Delete) và xóa toàn bộ phiên làm việc.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.of(context).pop();
                              auth.deleteAccount();
                            },
                            child: const Text('Xác nhận xóa'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Xóa tài khoản', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4. Fandoms Tab (Joined & Managed)
  Widget _buildFandomsTab(BuildContext context, Color textColor, Color subColor, bool isDark) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: subColor,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Fandom đang tham gia (3)'),
              Tab(text: 'Fandom đang quản lý (1)'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Joined Fandoms List
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFandomItem(
                      name: 'Sơn Tùng M-TP Fanspace',
                      category: 'Âm nhạc',
                      role: 'Hội viên Vàng',
                      roleColor: Colors.amber,
                      members: 14200,
                      isDark: isDark,
                    ),
                    _buildFandomItem(
                      name: 'T1 League of Legends',
                      category: 'Esports',
                      role: 'Thành viên',
                      roleColor: Colors.blue,
                      members: 28900,
                      isDark: isDark,
                    ),
                    _buildFandomItem(
                      name: 'NewJeans Bunnies VN',
                      category: 'Kpop',
                      role: 'VIP Bunny',
                      roleColor: Colors.purple,
                      members: 8500,
                      isDark: isDark,
                    ),
                  ],
                ),
                // Managed Fandoms List
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFandomItem(
                      name: 'Sơn Tùng M-TP Fanspace',
                      category: 'Âm nhạc',
                      role: 'Chủ Fandom (Owner)',
                      roleColor: AppTheme.accent,
                      members: 14200,
                      isOwner: true,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFandomItem({
    required String name,
    required String category,
    required String role,
    required Color roleColor,
    required int members,
    bool isOwner = false,
    required bool isDark,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: roleColor.withValues(alpha: 0.2),
              child: Icon(Icons.rocket_launch, color: roleColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(role, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text('• $members thành viên', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(isOwner ? 'Quản trị' : 'Truy cập', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // 5. Blacklist Tab
  Widget _buildBlacklistTab(BuildContext context, Color textColor, Color subColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Danh sách chặn (Blacklist)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 4),
                  Text('Các tài khoản bị bạn chặn sẽ không thể gửi tin nhắn hoặc tương tác.', style: TextStyle(fontSize: 12, color: subColor)),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tính năng tìm kiếm tài khoản để thêm vào blacklist.')),
                  );
                },
                icon: const Icon(Icons.person_add_disabled, size: 16),
                label: const Text('Chặn người dùng'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _mockBlacklist.isEmpty
                ? Center(
                    child: Text('Danh sách chặn hiện đang trống.', style: TextStyle(color: subColor)),
                  )
                : ListView.builder(
                    itemCount: _mockBlacklist.length,
                    itemBuilder: (ctx, idx) {
                      final item = _mockBlacklist[idx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.redAccent,
                            child: Icon(Icons.block, color: Colors.white, size: 18),
                          ),
                          title: Text(item['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text('@${item['username']} • Lý do: ${item['reason']}', style: TextStyle(color: subColor, fontSize: 12)),
                          trailing: TextButton(
                            onPressed: () {
                              setState(() => _mockBlacklist.removeAt(idx));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Đã bỏ chặn ${item['name']}.')),
                              );
                            },
                            child: const Text('Bỏ chặn', style: TextStyle(color: AppTheme.error)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
