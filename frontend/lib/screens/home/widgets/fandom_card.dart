import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../../profile/user_card_dialog.dart';

/// High-contrast Fandom summary card with contextual action options.
class FandomCard extends StatelessWidget {
  final FandomSummaryModel fandom;

  const FandomCard({super.key, required this.fandom});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: () => context.push('/fandoms/${fandom.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner Header
            SizedBox(
              height: 92,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (fandom.bannerUrl != null && fandom.bannerUrl!.isNotEmpty)
                    Image.network(
                      fandom.bannerUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _defaultBanner(),
                    )
                  else
                    _defaultBanner(),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black54, Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: fandom.admissionMode == 'APPROVAL'
                            ? AppTheme.accent.withValues(alpha: 0.9)
                            : AppTheme.success.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            fandom.admissionMode == 'APPROVAL'
                                ? Icons.lock_outline
                                : Icons.check_circle_outline,
                            size: 11,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fandom.admissionMode == 'APPROVAL'
                                ? 'Cần duyệt'
                                : 'Tự do',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        fandom.category,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.border,
                              width: 1.5,
                            ),
                            color: AppTheme.primary,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (fandom.avatarUrl != null &&
                                  fandom.avatarUrl!.isNotEmpty)
                              ? Image.network(
                                  fandom.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _avatarFallback(),
                                )
                              : _avatarFallback(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fandom.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: palette.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '@${fandom.slug}',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Tùy chọn Fandom',
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: palette.textSecondary,
                          ),
                          onSelected: (val) {
                            if (val == 'detail') {
                              context.push('/fandoms/${fandom.slug}');
                            } else if (val == 'workspace') {
                              context.go('/fandoms/${fandom.slug}/space');
                            } else if (val == 'owner') {
                              UserCardDialog.show(
                                context,
                                identifier: fandom.ownerId,
                                fallbackName: fandom.ownerName,
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'detail',
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Xem Trang giới thiệu'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'workspace',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.forum_outlined,
                                    size: 18,
                                    color: AppTheme.primary,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Vào Không gian Chat'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'owner',
                              child: Row(
                                children: [
                                  Icon(Icons.person_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Xem Hồ sơ Chủ Fandom'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        (fandom.description != null &&
                                fandom.description!.isNotEmpty)
                            ? fandom.description!
                            : 'Không gian sinh hoạt cộng đồng chính thức trên FanSpace.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.people_alt_outlined,
                              size: 15,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${fandom.memberCount} thành viên',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            UserCardDialog.show(
                              context,
                              identifier: fandom.ownerId,
                              fallbackName: fandom.ownerName,
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 12,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  fandom.ownerName,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.85),
            AppTheme.accent.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    return Center(
      child: Text(
        fandom.name.isNotEmpty ? fandom.name[0].toUpperCase() : 'F',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 18,
        ),
      ),
    );
  }
}
