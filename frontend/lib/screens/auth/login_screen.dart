import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import 'widgets/theme_toggle_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng nhập thành công! Chào mừng bạn trở lại.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Auto navigation is handled reactively by AuthGuard in main.dart
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final auth = context.read<AuthProvider>();
    // If running web, we can either trigger GIS or get auth redirect URL
    final authUrl = await auth.getGoogleAuthUrl();
    if (authUrl != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang khởi tạo cổng đăng nhập Google an toàn...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // In a real browser or web redirect, launchUrl(authUrl)
    }
  }

  String _formatLockout(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final auth = context.watch<AuthProvider>();

    return Title(
      title: 'Đăng nhập | FanSpace - Mạng Xã Hội Fandom',
      color: AppTheme.primary,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
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
              constraints: const BoxConstraints(maxWidth: 440),
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
                                colors: [AppTheme.primary, AppTheme.accent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.rocket_launch_rounded, size: 38, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Title
                        Text(
                          'Đăng nhập FanSpace',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Vào không gian fandom và kết nối thời gian thực',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: subColor),
                        ),
                        const SizedBox(height: 24),

                        // Lockout Warning Banner
                        if (auth.isLockedOut) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_clock_rounded, color: AppTheme.error, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Tài khoản bị tạm khóa 15 phút',
                                        style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Mở khóa sau: ${_formatLockout(auth.lockoutSeconds)}',
                                        style: const TextStyle(color: AppTheme.error, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        // Email / Username Field
                        Text(
                          'Email hoặc Tên đăng nhập',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'user@example.com hoặc username',
                            prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập Email hoặc Username.';
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
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          decoration: InputDecoration(
                            hintText: 'Nhập mật khẩu của bạn',
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
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),

                        // Remember Me & Forgot Password
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: AppTheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('Ghi nhớ', style: TextStyle(fontSize: 13, color: subColor)),
                              ],
                            ),
                            TextButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tính năng đặt lại mật khẩu qua mã OTP Email đang được xử lý.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: const Text('Quên mật khẩu?', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Login Button
                        ElevatedButton(
                          onPressed: (auth.isLoading || auth.isLockedOut) ? null : _handleLogin,
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
                              : const Text('Đăng nhập', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(height: 24),

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
                        const SizedBox(height: 20),

                        // Google Sign In Button
                        OutlinedButton.icon(
                          onPressed: auth.isLoading ? null : _handleGoogleSignIn,
                          icon: const Icon(
                            Icons.g_mobiledata_rounded,
                            size: 28,
                            color: Color(0xFFEA4335),
                          ),
                          label: const Text(
                            'Tiếp tục với Google',
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
                        const SizedBox(height: 24),

                        // Register Switch Link
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Chưa có tài khoản?',
                              style: TextStyle(fontSize: 13, color: subColor),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                );
                              },
                              child: const Text(
                                'Đăng ký ngay',
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
