/// General settings and Danger Zone tab inside FandomManagementDialog.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';

class FandomGeneralSettingsTab extends StatefulWidget {
  final FandomDetailModel fandom;
  final ValueChanged<FandomDetailModel> onFandomUpdated;
  final VoidCallback? onDeleteRequested;

  const FandomGeneralSettingsTab({
    super.key,
    required this.fandom,
    required this.onFandomUpdated,
    this.onDeleteRequested,
  });

  @override
  State<FandomGeneralSettingsTab> createState() =>
      _FandomGeneralSettingsTabState();
}

class _FandomGeneralSettingsTabState extends State<FandomGeneralSettingsTab> {
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final currentFandom = widget.fandom;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chế độ hiển thị không gian',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: palette.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: palette.border),
            ),
            child: SwitchListTile(
              key: const Key('switch_fandom_visibility'),
              value: currentFandom.isPublic,
              activeThumbColor: AppTheme.primary,
              title: Text(
                currentFandom.isPublic
                    ? 'Chế độ Công khai'
                    : 'Chế độ Riêng tư',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                currentFandom.isPublic
                    ? 'Fandom xuất hiện trên Danh mục Khám phá công khai.'
                    : 'Ẩn khỏi Danh mục Khám phá, chỉ truy cập qua liên kết hoặc mã mời.',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
              onChanged: _isUpdating
                  ? null
                  : (val) async {
                      setState(() => _isUpdating = true);
                      final provider = context.read<FandomProvider>();
                      final messenger = ScaffoldMessenger.of(context);
                      final res = await provider.updateFandomVisibility(
                        currentFandom.id,
                        val,
                      );
                      if (!mounted) return;
                      if (res['success'] == true) {
                        final updated = currentFandom.copyWith(isPublic: val);
                        widget.onFandomUpdated(updated);
                        setState(() => _isUpdating = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              res['message']?.toString() ??
                                  'Đã cập nhật trạng thái hiển thị.',
                            ),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      } else {
                        setState(() => _isUpdating = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              res['error']?.toString() ??
                                  'Không thể cập nhật.',
                            ),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    },
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                GoRouter.maybeOf(context)?.go('/fandoms/${currentFandom.slug}');
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Xem Trang giới thiệu Fandom'),
            ),
          ),
          const SizedBox(height: 24),
          Divider(color: palette.border),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppTheme.error,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Khu vực nguy hiểm',
                style: TextStyle(
                  color: AppTheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Xóa hoàn toàn không gian Fandom này cùng toàn bộ kênh thảo luận, tin nhắn chat và vai trò thành viên. Hành động này không thể hoàn tác.',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            key: const Key('btn_trigger_delete_fandom'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('XÓA VĨNH VIỄN FANDOM NÀY'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDeleteRequested?.call();
            },
          ),
        ],
      ),
    );
  }
}
