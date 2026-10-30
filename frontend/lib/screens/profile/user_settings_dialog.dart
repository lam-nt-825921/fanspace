import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fandom_provider.dart';
import '../auth/widgets/active_sessions_dialog.dart';
import '../auth/widgets/email_otp_dialog.dart';
import '../auth/widgets/oauth_set_password_dialog.dart';
import '../home/fandom_detail_screen.dart';

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

  MyFandomsDataModel? _myFandomsData;
  bool _isLoadingFandoms = true;
  String _fandomFilter = 'ALL'; // 'ALL', 'MEMBER', 'OWNER', 'PENDING'

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    _displayNameController = TextEditingController(text: user?.displayName ?? '');
    _avatarUrlController = TextEditingController(text: user?.avatarUrl ?? '');
    _bannerUrlController = TextEditingController(text: user?.bannerUrl ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
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

  // 4. Fandoms Tab (Live Data with unified fandoms, owned filter, and pending requests)
  Widget _buildFandomsTab(BuildContext context, Color textColor, Color subColor, bool isDark) {
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
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fandom của tôi',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Các cộng đồng bạn đang tham gia hoặc sở hữu.',
                      style: TextStyle(fontSize: 13, color: subColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showJoinByInviteDialog(context),
                icon: const Icon(Icons.vpn_key_outlined, size: 16),
                label: const Text('Nhập mã mời', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFandomFilterChip('Tất cả (${allFandoms.length})', 'ALL'),
                const SizedBox(width: 8),
                _buildFandomFilterChip('Chỉ Fandom sở hữu (${ownedOnly.length})', 'OWNER'),
                const SizedBox(width: 8),
                _buildFandomFilterChip('Đang tham gia (${joinedOnly.length})', 'JOINED'),
                const SizedBox(width: 8),
                _buildFandomFilterChip('Chờ duyệt (${pendingRequests.length})', 'PENDING'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Content Area
          Expanded(
            child: _isLoadingFandoms
                ? const Center(child: CircularProgressIndicator())
                : _fandomFilter == 'PENDING'
                    ? _buildPendingRequestsList(pendingRequests, textColor, subColor, isDark)
                    : _buildMembershipsList(
                        _fandomFilter == 'OWNER'
                            ? ownedOnly
                            : (_fandomFilter == 'JOINED' ? joinedOnly : allFandoms),
                        textColor,
                        subColor,
                        isDark,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFandomFilterChip(String label, String filterKey) {
    final isSelected = _fandomFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _fandomFilter = filterKey);
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  Widget _buildMembershipsList(
    List<FandomSummaryModel> items,
    Color textColor,
    Color subColor,
    bool isDark,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined, size: 48, color: subColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              _fandomFilter == 'OWNER'
                  ? 'Bạn chưa sở hữu Fandom nào.'
                  : 'Bạn chưa tham gia Fandom nào.',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Hãy khám phá danh bạ cộng đồng công khai và tham gia nhé!',
              style: TextStyle(color: subColor, fontSize: 12),
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

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primary,
                  backgroundImage: item.avatarUrl != null && item.avatarUrl!.isNotEmpty
                      ? NetworkImage(item.avatarUrl!)
                      : null,
                  child: item.avatarUrl == null || item.avatarUrl!.isEmpty
                      ? Text(
                          item.name.isNotEmpty ? item.name[0].toUpperCase() : 'F',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isOwner
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isOwner ? Colors.amber : Colors.green,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              isOwner ? 'Chủ Fandom (Owner)' : 'Thành viên',
                              style: TextStyle(
                                color: isOwner ? Colors.amberAccent : Colors.greenAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.category,
                              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          ),
                          Text(
                            '• ${item.memberCount} tv',
                            style: TextStyle(color: subColor, fontSize: 11),
                          ),
                          if (createdDateStr.isNotEmpty)
                            Text(
                              '• Tạo: $createdDateStr',
                              style: TextStyle(color: subColor, fontSize: 11),
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
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FandomDetailScreen(slug: item.slug),
                          ),
                        );
                      },
                      child: const Text('Vào Fandom', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    if (!isOwner) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Rời Fandom',
                        icon: const Icon(Icons.exit_to_app, color: AppTheme.error, size: 20),
                        onPressed: () => _handleLeaveFromDialog(item.slug, item.name),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingRequestsList(
    List<FandomJoinRequestItemModel> items,
    Color textColor,
    Color subColor,
    bool isDark,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 48, color: subColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Không có đơn xin gia nhập nào đang chờ duyệt.',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
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

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.amber.withValues(alpha: 0.2),
                  child: const Icon(Icons.hourglass_top, color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.fandomName,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ĐANG CHỜ DUYỆT',
                              style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('Gửi ngày: $dateStr', style: TextStyle(color: subColor, fontSize: 11)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _handleCancelPendingRequest(req.fandomSlug),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Hủy yêu cầu', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLeaveFromDialog(String slug, String fandomName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận rời Fandom?'),
        content: Text('Bạn có chắc chắn muốn rời khỏi Fandom "$fandomName" không?'),
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

    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.leaveFandom(slug);

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đã rời khỏi Fandom.'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadUserFandoms();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Không thể rời Fandom.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _handleCancelPendingRequest(String slug) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy đơn xin gia nhập?'),
        content: const Text('Bạn có chắc chắn muốn hủy đơn xin gia nhập đang chờ duyệt không?'),
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

    final fandomProvider = context.read<FandomProvider>();
    final result = await fandomProvider.cancelJoinRequest(slug);

    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đã hủy đơn xin gia nhập.'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadUserFandoms();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Không thể hủy đơn.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _showJoinByInviteDialog(BuildContext context) async {
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.vpn_key_outlined, color: AppTheme.accent),
              SizedBox(width: 8),
              Text('Gia nhập bằng mã mời'),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nhập mã mời được Chủ Fandom cấp để gia nhập trực tiếp vào Fandom.',
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
                    prefixIcon: Icon(Icons.key_outlined),
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
                        _loadUserFandoms();
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

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
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
