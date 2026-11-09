import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../../providers/fandom_provider.dart';
import 'join_by_invite_dialog.dart';

/// Quick navigation modal listing all Fandoms the current user owns or has joined.
class MyFandomsQuickSwitcherDialog extends StatefulWidget {
  const MyFandomsQuickSwitcherDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const MyFandomsQuickSwitcherDialog(),
    );
  }

  @override
  State<MyFandomsQuickSwitcherDialog> createState() =>
      _MyFandomsQuickSwitcherDialogState();
}

class _MyFandomsQuickSwitcherDialogState
    extends State<MyFandomsQuickSwitcherDialog> {
  MyFandomsDataModel? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await context.read<FandomProvider>().fetchMyFandoms();
    if (!mounted) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = _data?.allFandoms ?? const [];

    return Dialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.workspaces_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chuyển nhanh Không gian Fandom',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_data != null)
                          Text(
                            'Hạn ngạch sở hữu: ${_data!.quotaUsed}/${_data!.maxQuota} Fandom',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/fandoms/create');
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Tạo Fandom mới'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      JoinByInviteDialog.show(context, navigateOnSuccess: true);
                    },
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: const Text('Nhập mã mời'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/');
                    },
                    icon: const Icon(Icons.explore_outlined, size: 16),
                    label: const Text('Khám phá cộng đồng'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: palette.border, height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.groups_2_outlined,
                                  size: 48,
                                  color: palette.textSecondary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Bạn chưa tham gia hoặc sở hữu Fandom nào.',
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hãy khám phá cộng đồng, nhập mã mời hoặc tạo Fandom của riêng bạn!',
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, idx) {
                              final item = items[idx];
                              final isOwner = _data?.isOwner(item.id) ?? false;
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: palette.background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: palette.border),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: AppTheme.primary,
                                      backgroundImage:
                                          item.avatarUrl?.isNotEmpty == true
                                              ? NetworkImage(item.avatarUrl!)
                                              : null,
                                      child: item.avatarUrl?.isNotEmpty == true
                                          ? null
                                          : Text(
                                              item.name.isNotEmpty
                                                  ? item.name[0].toUpperCase()
                                                  : 'F',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  item.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: palette.textPrimary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isOwner
                                                      ? AppTheme.primary
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : AppTheme.success
                                                            .withValues(
                                                              alpha: 0.15,
                                                            ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isOwner
                                                      ? 'Chủ Fandom'
                                                      : 'Thành viên',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isOwner
                                                        ? AppTheme.primary
                                                        : AppTheme.success,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${item.slug} • ${item.memberCount} thành viên',
                                            style: TextStyle(
                                              color: palette.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        context.go(
                                          '/fandoms/${item.slug}/space',
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.forum_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Vào Không gian'),
                                    ),
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      tooltip: 'Tùy chọn điều hướng',
                                      onSelected: (val) {
                                        Navigator.of(context).pop();
                                        if (val == 'workspace') {
                                          context.go(
                                            '/fandoms/${item.slug}/space',
                                          );
                                        } else if (val == 'detail') {
                                          context.go('/fandoms/${item.slug}');
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'workspace',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.meeting_room_outlined,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Mở Không gian Chat'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'detail',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.info_outline,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Xem Trang giới thiệu'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
