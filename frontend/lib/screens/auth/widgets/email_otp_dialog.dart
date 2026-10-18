import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class EmailOtpDialog extends StatefulWidget {
  final String email;
  final String purpose;
  final VoidCallback? onSuccess;

  const EmailOtpDialog({
    super.key,
    required this.email,
    this.purpose = 'VERIFY_EMAIL',
    this.onSuccess,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String email,
    String purpose = 'VERIFY_EMAIL',
    VoidCallback? onSuccess,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmailOtpDialog(
        email: email,
        purpose: purpose,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<EmailOtpDialog> createState() => _EmailOtpDialogState();
}

class _EmailOtpDialogState extends State<EmailOtpDialog> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _cooldownSeconds = 60;
  Timer? _cooldownTimer;
  bool _isSubmitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds > 0) {
        setState(() => _cooldownSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  Future<void> _handleVerify() async {
    final code = _otpCode;
    if (code.length != 6) {
      setState(() => _localError = 'Vui lòng nhập đủ 6 chữ số mã OTP.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _localError = null;
    });

    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyEmailOtp(
      email: widget.email,
      code: code,
      purpose: widget.purpose,
    );

    setState(() => _isSubmitting = false);

    if (!mounted) return;

    if (ok) {
      widget.onSuccess?.call();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Xác thực địa chỉ Email thành công!'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _localError = auth.errorMessage ?? 'Mã OTP không chính xác hoặc đã hết hạn.');
    }
  }

  Future<void> _handleResend() async {
    if (_cooldownSeconds > 0) return;

    setState(() {
      _localError = null;
      for (var c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    });

    final auth = context.read<AuthProvider>();
    final ok = await auth.sendEmailOtp(
      email: widget.email,
      purpose: widget.purpose,
    );

    if (ok) {
      _startCooldown();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã gửi lại mã OTP mới tới ${widget.email}.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      setState(() => _localError = auth.errorMessage ?? 'Gửi lại mã OTP thất bại.');
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: surfaceColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: AppTheme.primary, size: 36),
              ),
              const SizedBox(height: 16),

              Text(
                'Xác thực mã OTP Email',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Mã OTP 6 chữ số đã được gửi tới:\n${widget.email}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // 6 PIN boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 44,
                    height: 52,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        fillColor: isDark ? AppTheme.darkSurfaceLight : AppTheme.lightSurfaceLight,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                        ),
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty && index < 5) {
                          _focusNodes[index + 1].requestFocus();
                        } else if (val.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                        if (_otpCode.length == 6) {
                          _handleVerify();
                        }
                      },
                    ),
                  );
                }),
              ),

              // Error display
              if (_localError != null) ...[
                const SizedBox(height: 14),
                Text(
                  _localError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 24),

              // Verify Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleVerify,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Xác thực kích hoạt', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 12),

              // Resend Row & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Bỏ qua / Để sau',
                      style: TextStyle(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _cooldownSeconds > 0 ? null : _handleResend,
                    child: Text(
                      _cooldownSeconds > 0 ? 'Gửi lại sau ($_cooldownSeconds s)' : 'Gửi lại mã OTP',
                      style: TextStyle(
                        color: _cooldownSeconds > 0 ? Colors.grey : AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
