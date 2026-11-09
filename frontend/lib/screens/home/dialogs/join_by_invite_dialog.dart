import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/fandom_provider.dart';

/// Reusable dialog allowing users to join a Public or Private Fandom using an invite code.
class JoinByInviteDialog extends StatefulWidget {
  final VoidCallback? onJoinedSuccess;
  final bool navigateOnSuccess;

  const JoinByInviteDialog({
    super.key,
    this.onJoinedSuccess,
    this.navigateOnSuccess = false,
  });

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onJoinedSuccess,
    bool navigateOnSuccess = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => JoinByInviteDialog(
        onJoinedSuccess: onJoinedSuccess,
        navigateOnSuccess: navigateOnSuccess,
      ),
    );
  }

  @override
  State<JoinByInviteDialog> createState() => _JoinByInviteDialogState();
}

class _JoinByInviteDialogState extends State<JoinByInviteDialog> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đăng nhập trước khi sử dụng mã mời Fandom.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      context.go('/login');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final fandomProvider = context.read<FandomProvider>();
    final res = await fandomProvider.joinByInvite(_codeController.text.trim());

    if (!mounted) return;
    if (res['success'] == true) {
      final slug = res['fandom_slug']?.toString();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Gia nhập Fandom thành công!'),
          backgroundColor: AppTheme.success,
        ),
      );
      widget.onJoinedSuccess?.call();
      if (widget.navigateOnSuccess && slug != null && slug.isNotEmpty) {
        context.go('/fandoms/$slug/space');
      }
    } else {
      setState(() {
        _isSubmitting = false;
        _errorText = res['error']?.toString() ?? 'Mã mời không hợp lệ hoặc đã hết hạn.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.key_outlined, color: AppTheme.accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nhập mã mời Fandom',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập mã mời 8 ký tự do Chủ Fandom cấp để vào ngay không gian Fandom riêng tư hoặc bỏ qua bước chờ duyệt.',
                style: TextStyle(
                  fontSize: 13,
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (_errorText != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _codeController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                decoration: const InputDecoration(
                  labelText: 'Mã mời (Invite Code)',
                  hintText: 'VD: VIP2026X',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                onFieldSubmitted: (_) => _submit(),
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
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login_rounded, size: 18),
          label: const Text('Gia nhập'),
        ),
      ],
    );
  }
}
