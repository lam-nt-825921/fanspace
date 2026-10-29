import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/url_navigation.dart';
import '../../providers/auth_provider.dart';
import 'widgets/theme_toggle_button.dart';
import 'widgets/password_strength_bar.dart';
import 'widgets/email_otp_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeToTos = true;
  String _currentPasswordText = '';

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreeToTos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đồng ý với Điều khoản sử dụng của FanSpace.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final password = _passwordController.text;

    final success = await auth.register(
      email: email,
      username: username,
      displayName: displayName,
      password: password,
    );

    if (!mounted) return;

    if (!success && auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage!),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (success) {
      // Auto prompt email verification OTP dialog
      await EmailOtpDialog.show(
        context,
        email: email,
        purpose: 'VERIFY_EMAIL',
        onSuccess: () {
          if (mounted) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          }
        },
      );
    }
  }

  void _handleGoogleSignIn() {
    final targetUrl = '${AppConstants.baseUrl}/api/v1/auth/google/login';
    openExternalUrlSync(targetUrl);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final auth = context.watch<AuthProvider>();

    return Title(
      title: 'Đăng ký tài khoản | FanSpace - Mạng Xã Hội Fandom',
      color: AppTheme.primary,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: ThemeToggleButton(),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: surfaceColor,
                elevation: isDark ? 4 : 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo icon
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.accent, AppTheme.primary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.person_add_rounded, size: 38, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 18),

                        Text(
                          'Tạo tài khoản FanSpace',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tham gia cộng đồng và ủng hộ fandom bạn yêu thích',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: subColor),
                        ),
                        const SizedBox(height: 24),

                        // Email Field
                        Text(
                          'Địa chỉ Email',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'name@example.com',
                            prefixIcon: Icon(Icons.email_outlined, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập địa chỉ email.';
                            }
                            final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                            if (!emailRegex.hasMatch(value.trim())) {
                              return 'Vui lòng nhập email hợp lệ (ví dụ: user@example.com).';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Username Field
                        Text(
                          'Tên tài khoản (Username)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'fanzone_01',
                            prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập tên tài khoản.';
                            }
                            if (value.length < 3 || value.length > 30) {
                              return 'Tên tài khoản phải từ 3 đến 30 ký tự.';
                            }
                            final usernameRegex = RegExp(r'^[a-zA-Z0-9_-]+$');
                            if (!usernameRegex.hasMatch(value.trim())) {
                              return 'Chỉ chấp nhận chữ cái, số, dấu gạch nối và gạch dưới.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Display Name Field
                        Text(
                          'Tên hiển thị (Display Name)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _displayNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Fan Cứng Sơn Tùng',
                            prefixIcon: Icon(Icons.badge_outlined, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập tên hiển thị.';
                            }
                            if (value.length > 50) {
                              return 'Tên hiển thị không được vượt quá 50 ký tự.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        Text(
                          'Mật khẩu',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          onChanged: (val) => setState(() => _currentPasswordText = val),
                          decoration: InputDecoration(
                            hintText: 'Tối thiểu 8 ký tự',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Vui lòng nhập mật khẩu.';
                            }
                            if (value.length < 8) {
                              return 'Mật khẩu phải có tối thiểu 8 ký tự.';
                            }
                            return null;
                          },
                        ),
                        // Password Strength Bar
                        PasswordStrengthBar(password: _currentPasswordText),
                        const SizedBox(height: 16),

                        // Confirm Password Field
                        Text(
                          'Xác nhận mật khẩu',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleRegister(),
                          decoration: InputDecoration(
                            hintText: 'Nhập lại mật khẩu vừa nhập',
                            prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Vui lòng xác nhận mật khẩu.';
                            }
                            if (value != _passwordController.text) {
                              return 'Mật khẩu xác nhận không trùng khớp.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // TOS Checkbox
                        Row(
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: _agreeToTos,
                                activeColor: AppTheme.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (val) => setState(() => _agreeToTos = val ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tôi đồng ý với Điều khoản dịch vụ và Chính sách bảo mật của FanSpace.',
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),

                        // Submit Button
                        ElevatedButton(
                          onPressed: auth.isLoading ? null : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Đăng ký tài khoản', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(height: 20),

                        // OR Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: subColor.withValues(alpha: 0.3))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'HOẶC',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: subColor),
                              ),
                            ),
                            Expanded(child: Divider(color: subColor.withValues(alpha: 0.3))),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Google Sign In
                        OutlinedButton.icon(
                          onPressed: auth.isLoading ? null : _handleGoogleSignIn,
                          icon: const Icon(
                            Icons.g_mobiledata_rounded,
                            size: 28,
                            color: Color(0xFFEA4335),
                          ),
                          label: const Text(
                            'Đăng ký nhanh qua Google',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(
                              color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Login Switch Link
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Đã có tài khoản?',
                              style: TextStyle(fontSize: 13, color: subColor),
                            ),
                            TextButton(
                              onPressed: () {
                                context.go('/login');
                              },
                              child: const Text(
                                'Đăng nhập ngay',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
