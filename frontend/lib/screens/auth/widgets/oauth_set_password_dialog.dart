import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class OAuthSetPasswordDialog extends StatefulWidget {
  final String email;

  const OAuthSetPasswordDialog({
    super.key,
    required this.email,
  });

  static Future<bool?> show(BuildContext context, {required String email}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => OAuthSetPasswordDialog(email: email),
    );
  }

  @override
  State<OAuthSetPasswordDialog> createState() => _OAuthSetPasswordDialogState();
}

class _OAuthSetPasswordDialogState extends State<OAuthSetPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _otpSent = false;
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _localError = null);
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendEmailOtp(
      email: widget.email,
      purpose: 'OAUTH_SET_PASSWORD',
    );
    if (ok) {
      setState(() => _otpSent = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mã OTP đã được gửi tới ${widget.email}.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _localError = auth.errorMessage);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _localError = null);

    final auth = context.read<AuthProvider>();
    final ok = await auth.oauthSetPassword(
      newPassword: _passwordController.text,
      otpCode: _otpController.text.trim(),
    );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thiết lập mật khẩu thành công! Giờ đây bạn có thể đăng nhập bằng mật khẩu.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _localError = auth.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final auth = context.watch<AuthProvider>();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: surfaceColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.password_rounded, color: AppTheme.primary, size: 32),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Thiết lập mật khẩu cá nhân',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 6),

                Text(
                  'Bảo mật danh tính bằng mã OTP gửi tới email Google:\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // OTP send/input row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          hintText: 'Mã OTP (6 số)',
                          prefixIcon: Icon(Icons.pin, size: 20),
                          counterText: '',
                        ),
                        validator: (val) {
                          if (val == null || val.length != 6) {
                            return 'Cần nhập đủ 6 số';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: auth.isLoading ? null : _sendOtp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      child: Text(_otpSent ? 'Gửi lại' : 'Gửi mã'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'Mật khẩu mới (tối thiểu 8 ký tự)',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.length < 8) {
                      return 'Mật khẩu phải từ 8 ký tự trở lên.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    hintText: 'Xác nhận lại mật khẩu',
                    prefixIcon: Icon(Icons.check_circle_outline, size: 20),
                  ),
                  validator: (val) {
                    if (val != _passwordController.text) {
                      return 'Mật khẩu xác nhận không trùng khớp.';
                    }
                    return null;
                  },
                ),

                if (_localError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _localError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 22),

                ElevatedButton(
                  onPressed: auth.isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: auth.isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Lưu mật khẩu mới'),
                ),
                const SizedBox(height: 8),

                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Đóng',
                    style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
