import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _securityKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _securityKeyController.dispose();
    super.dispose();
  }

  Future<void> _handleAdminLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng nhập Quản trị viên thành công! Chào mừng tới Governance Console.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/admin/permissions');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Xác thực tài khoản Admin không thành công.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Title(
      title: 'Admin Governance Console | FanSpace Security',
      color: AppTheme.primary,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Deep Navy Slate
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                color: const Color(0xFF1E293B),
                elevation: 8,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Shield Icon & Security Badge
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.admin_panel_settings, size: 36, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        const Text(
                          'CỔNG QUẢN TRỊ HỆ THỐNG',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'FanSpace Security & Governance Console',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Email Field
                        const Text('Email quản trị viên', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'admin@fanspace.vn',
                            hintStyle: const TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF94A3B8), size: 20),
                            fillColor: const Color(0xFF0F172A),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) => val == null || val.isEmpty ? 'Vui lòng nhập email admin.' : null,
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        const Text('Mật khẩu quản trị', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: '••••••••••••',
                            hintStyle: const TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF94A3B8), size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            fillColor: const Color(0xFF0F172A),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) => val == null || val.isEmpty ? 'Vui lòng nhập mật khẩu.' : null,
                        ),
                        const SizedBox(height: 16),

                        // Security Code (Optional 2FA Token)
                        const Text('Mã xác thực bảo mật 2FA (Tùy chọn)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _securityKeyController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Để trống hoặc nhập mã 6 số',
                            hintStyle: const TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: const Icon(Icons.security, color: Color(0xFF94A3B8), size: 20),
                            fillColor: const Color(0xFF0F172A),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Login Button
                        ElevatedButton(
                          onPressed: auth.isLoading ? null : _handleAdminLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Đăng nhập Quản trị',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                        ),
                        const SizedBox(height: 16),

                        // Quick bypass for exploring permissions directly in demo mode
                        OutlinedButton.icon(
                          onPressed: () {
                            context.go('/admin/permissions');
                          },
                          icon: const Icon(Icons.explore_outlined, size: 18, color: Color(0xFF38BDF8)),
                          label: const Text(
                            'Xem Bảng Phân Quyền Trực Tiếp (Demo Mode)',
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF38BDF8)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Back to Home
                        Center(
                          child: TextButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF94A3B8)),
                            label: const Text('Quay lại trang cộng đồng', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
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
