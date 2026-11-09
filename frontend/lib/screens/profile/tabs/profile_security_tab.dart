/// Security, OTP verification, password management, and active sessions tab inside UserSettingsDialog.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../auth/widgets/active_sessions_dialog.dart';
import '../../auth/widgets/email_otp_dialog.dart';
import '../../auth/widgets/oauth_set_password_dialog.dart';

class ProfileSecurityTab extends StatefulWidget {
  const ProfileSecurityTab({super.key});

  @override
  State<ProfileSecurityTab> createState() => _ProfileSecurityTabState();
}

class _ProfileSecurityTabState extends State<ProfileSecurityTab> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();
  bool _isChangingPassword = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
          content: Text(
            auth.errorMessage ?? 'Đổi mật khẩu không thành công.',
          ),
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
            'Bảo mật & Quản lý Truy cập',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Quản lý mật khẩu, trạng thái xác thực và các phiên đăng nhập bảo mật.',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: user?.isEmailVerified == true
                    ? AppTheme.success.withValues(alpha: 0.4)
                    : AppTheme.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  user?.isEmailVerified == true
                      ? Icons.mark_email_read
                      : Icons.mail_lock_outlined,
                  color: user?.isEmailVerified == true
                      ? AppTheme.success
                      : AppTheme.warning,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        user?.isEmailVerified == true
                            ? 'Email đã được xác thực an toàn.'
                            : 'Email chưa xác thực. Hãy kích hoạt để bảo vệ tài khoản.',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Xác thực OTP',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.lock_reset,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      user?.hasPassword == false
                          ? 'Thiết lập Mật khẩu Tài khoản'
                          : 'Đổi Mật khẩu',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (user?.hasPassword == false) ...[
                  Text(
                    'Tài khoản của bạn được khởi tạo bằng Google OAuth2. Bạn có thể thiết lập mật khẩu cá nhân để đăng nhập bằng Email/Password.',
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (user?.email != null) {
                        OAuthSetPasswordDialog.show(
                          context,
                          email: user!.email,
                        );
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
                          validator: (val) => val == null || val.isEmpty
                              ? 'Vui lòng nhập mật khẩu cũ.'
                              : null,
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
                            if (val == null || val.length < 6) {
                              return 'Mật khẩu mới phải từ 6 ký tự.';
                            }
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
                            if (val != _newPasswordController.text) {
                              return 'Mật khẩu xác nhận không khớp.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _isChangingPassword
                                ? null
                                : _handleChangePassword,
                            child: _isChangingPassword
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
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

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.devices, color: AppTheme.accent, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quản lý Phiên Đăng nhập Thiết bị',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        'Kiểm tra và đăng xuất từ xa khỏi các thiết bị lạ.',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
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

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.error,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vùng Nguy hiểm',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.error,
                        ),
                      ),
                      Text(
                        'Vô hiệu hóa vĩnh viễn tài khoản và đăng xuất mọi thiết bị.',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: palette.surface,
                        title: const Text('Xác nhận xóa tài khoản?'),
                        content: const Text(
                          'Tài khoản của bạn sẽ bị vô hiệu hóa (Soft Delete) và xóa toàn bộ phiên làm việc.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Hủy'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                            ),
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
                  child: const Text(
                    'Xóa tài khoản',
                    style: TextStyle(
                      color: AppTheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
