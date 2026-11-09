/// Password-authenticated confirmation dialog for permanently deleting a Fandom.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';

class DeleteFandomConfirmDialog extends StatefulWidget {
  final FandomDetailModel fandom;

  const DeleteFandomConfirmDialog({
    super.key,
    required this.fandom,
  });

  static Future<void> show(
    BuildContext context, {
    required FandomDetailModel fandom,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteFandomConfirmDialog(fandom: fandom),
    );
  }

  @override
  State<DeleteFandomConfirmDialog> createState() =>
      _DeleteFandomConfirmDialogState();
}

class _DeleteFandomConfirmDialogState extends State<DeleteFandomConfirmDialog> {
  final TextEditingController _passwordController = TextEditingController();
  String? _localError;
  bool _isDeleting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirmDelete() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _localError = 'Vui lòng nhập mật khẩu xác nhận.');
      return;
    }

    setState(() {
      _isDeleting = true;
      _localError = null;
    });

    final provider = context.read<FandomProvider>();
    final res = await provider.deleteFandom(widget.fandom.slug, password);

    if (!mounted) return;
    if (res['success'] == true) {
      final router = GoRouter.maybeOf(context);
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            res['message']?.toString() ?? 'Fandom đã được xóa thành công.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      router?.go('/');
    } else {
      setState(() {
        _isDeleting = false;
        _localError =
            res['error']?.toString() ?? 'Xác nhận xóa thất bại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      title: Row(
        children: [
          const Icon(Icons.delete_forever, color: AppTheme.error, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Xác nhận xóa Fandom',
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                  height: 1.45,
                ),
                children: [
                  const TextSpan(
                    text: 'Bạn có chắc chắn muốn xóa Fandom ',
                  ),
                  TextSpan(
                    text: '"${widget.fandom.name}"',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const TextSpan(
                    text:
                        '? Toàn bộ kênh, tin nhắn chat và danh sách thành viên sẽ bị xóa vĩnh viễn.\n\nVui lòng nhập mật khẩu tài khoản của bạn để xác nhận:',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                labelText: 'Mật khẩu tài khoản của bạn',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _localError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: _isDeleting ? null : _handleConfirmDelete,
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Xác nhận xóa'),
        ),
      ],
    );
  }
}
