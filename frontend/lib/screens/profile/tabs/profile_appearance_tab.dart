/// Personal profile appearance tab inside UserSettingsDialog.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class ProfileAppearanceTab extends StatefulWidget {
  const ProfileAppearanceTab({super.key});

  @override
  State<ProfileAppearanceTab> createState() => _ProfileAppearanceTabState();
}

class _ProfileAppearanceTabState extends State<ProfileAppearanceTab> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _avatarUrlController;
  late final TextEditingController _bannerUrlController;
  late final TextEditingController _bioController;
  bool _isUploadingAvatar = false;
  bool _isUploadingBanner = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
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
    super.dispose();
  }

  Future<void> _pickAndUploadImage({required bool isAvatar}) async {
    final auth = context.read<AuthProvider>();
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể đọc dữ liệu tệp được chọn.'),
            ),
          );
        }
        return;
      }

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
          if (url != null) _avatarUrlController.text = url;
        } else {
          _isUploadingBanner = false;
          if (url != null) _bannerUrlController.text = url;
        }
      });

      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAvatar
                  ? 'Tải ảnh đại diện thành công!'
                  : 'Tải ảnh bìa thành công!',
            ),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hồ sơ diện mạo cá nhân',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Thông tin diện mạo (ảnh bìa, ảnh đại diện, tiểu sử) sẽ hiển thị công khai trên thẻ hồ sơ của bạn.',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 20),

          Container(
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(15),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.75),
                            AppTheme.accent.withValues(alpha: 0.75),
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
                        onPressed: _isUploadingBanner
                            ? null
                            : () => _pickAndUploadImage(isAvatar: false),
                        icon: _isUploadingBanner
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera_alt_outlined, size: 16),
                        label: Text(
                          _isUploadingBanner ? 'Đang tải...' : 'Đổi ảnh bìa',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.65),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -30),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.surface,
                              width: 3.5,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: AppTheme.primary,
                            backgroundImage:
                                _avatarUrlController.text.isNotEmpty
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
                          onPressed: _isUploadingAvatar
                              ? null
                              : () => _pickAndUploadImage(isAvatar: true),
                          icon: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_front_outlined,
                                  size: 16,
                                ),
                          label: Text(
                            _isUploadingAvatar
                                ? 'Đang tải...'
                                : 'Đổi ảnh đại diện',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
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
          Text(
            'Tên hiển thị công khai (tối đa 50 ký tự)',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
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

          Text(
            'Tên tài khoản định danh (@username)',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: '@${user?.username ?? ''}',
            readOnly: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alternate_email, size: 20),
              fillColor: palette.surfaceElevated,
              filled: true,
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Giới thiệu bản thân / Tiểu sử (tối đa 250 ký tự)',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
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

          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Tùy chỉnh liên kết URL ảnh trực tiếp',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
              children: [
                const SizedBox(height: 6),
                Text(
                  'URL ảnh đại diện',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
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
                Text(
                  'URL ảnh bìa',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
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
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: auth.isLoading ? null : _handleSaveProfile,
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Lưu thay đổi hồ sơ'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
