/// Invite links management tab inside FandomManagementDialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';
import 'dialogs/create_invite_dialog.dart';

class FandomInvitesTab extends StatelessWidget {
  final FandomDetailModel fandom;
  final List<FandomInviteModel> invites;
  final bool isLoading;
  final VoidCallback onRefreshInvites;

  const FandomInvitesTab({
    super.key,
    required this.fandom,
    required this.invites,
    required this.isLoading,
    required this.onRefreshInvites,
  });

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _revokeInvite(
    BuildContext context,
    FandomInviteModel invite,
  ) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
        title: Text(
          'Thu hồi mã mời: ${invite.code}',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Sau khi thu hồi, mã mời này sẽ không thể dùng để gia nhập Fandom được nữa.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_revoke_invite'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final provider = context.read<FandomProvider>();
      final res = await provider.revokeInvite(fandom.id, invite.code);
      if (res['success'] == true) {
        onRefreshInvites();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['error']?.toString() ?? 'Không thể thu hồi mã mời.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                key: const Key('btn_create_invite'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.add_link, size: 16),
                label: const Text(
                  'Tạo mã mời mới',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => CreateInviteDialog.show(
                  context,
                  fandomId: fandom.id,
                  onCreated: onRefreshInvites,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : invites.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có mã mời nào đang hoạt động.',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: invites.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final invite = invites[index];

                        return Container(
                          decoration: BoxDecoration(
                            color: palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: palette.border),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: palette.border),
                                ),
                                child: Text(
                                  invite.code,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Đã dùng: ${invite.usesCount} / ${invite.maxUses ?? 'Vô hạn'}',
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      invite.expiresAt != null
                                          ? 'Hết hạn: ${_formatDate(invite.expiresAt!)}'
                                          : 'Thời hạn: Vĩnh viễn',
                                      style: TextStyle(
                                        color: invite.isExpired
                                            ? AppTheme.error
                                            : palette.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('btn_copy_invite_${invite.code}'),
                                tooltip: 'Sao chép mã',
                                icon: const Icon(
                                  Icons.copy,
                                  size: 18,
                                  color: AppTheme.primary,
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: invite.code),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã sao chép mã mời: ${invite.code}',
                                      ),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                key: Key('btn_revoke_invite_${invite.code}'),
                                tooltip: 'Thu hồi mã mời',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppTheme.error,
                                ),
                                onPressed: () => _revokeInvite(context, invite),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
