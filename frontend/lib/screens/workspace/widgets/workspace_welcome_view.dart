/// Welcome overview and community rules acknowledgment views for FandomWorkspaceScreen.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/channel_model.dart';
import '../../../models/fandom_model.dart';

class WorkspaceWelcomeView extends StatelessWidget {
  final FandomDetailModel fandom;
  final List<ChannelModel> channels;
  final VoidCallback onViewRules;
  final ValueChanged<ChannelModel> onSelectChannel;

  const WorkspaceWelcomeView({
    super.key,
    required this.fandom,
    required this.channels,
    required this.onViewRules,
    required this.onSelectChannel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final firstTextChannel = channels
        .where((c) => c.type == 'TEXT' && !c.isAnnouncement)
        .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.18),
                      palette.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        fandom.category,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Chào mừng đến với ${fandom.name}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fandom.description ??
                          'Không gian sinh hoạt cộng đồng chính thức dành cho các thành viên.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: onViewRules,
                          icon: const Icon(Icons.gavel_outlined, size: 18),
                          label: const Text('Xem Nội quy Cộng đồng'),
                        ),
                        if (firstTextChannel != null)
                          OutlinedButton.icon(
                            onPressed: () => onSelectChannel(firstTextChannel),
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                            ),
                            label: Text('Vào #${firstTextChannel.name}'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => GoRouter.maybeOf(context)
                              ?.go('/fandoms/${fandom.slug}'),
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('Trang giới thiệu Fandom'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Cấu trúc Không gian Fandom',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildInfoCard(
                    context: context,
                    icon: Icons.campaign_outlined,
                    title: 'Kênh Thông báo',
                    description:
                        'Cập nhật tin tức chính thức một chiều từ Chủ Fandom (${fandom.ownerName}).',
                  ),
                  _buildInfoCard(
                    context: context,
                    icon: Icons.forum_outlined,
                    title: 'Kênh Thảo luận',
                    description:
                        'Nhắn tin thời gian thực, chia sẻ hình ảnh và tương tác cùng ${fandom.memberCount} thành viên.',
                  ),
                  _buildInfoCard(
                    context: context,
                    icon: Icons.podcasts,
                    title: 'Phòng Thoại (Voice)',
                    description:
                        'Giao lưu âm thanh trực tiếp hoặc giơ tay phát biểu trên sân khấu.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final palette = context.palette;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary, size: 26),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceRulesView extends StatelessWidget {
  final FandomDetailModel fandom;
  final List<ChannelModel> channels;
  final bool rulesAcknowledged;
  final VoidCallback onAcknowledgeRules;
  final ValueChanged<ChannelModel> onSelectChannel;

  const WorkspaceRulesView({
    super.key,
    required this.fandom,
    required this.channels,
    required this.rulesAcknowledged,
    required this.onAcknowledgeRules,
    required this.onSelectChannel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final firstTextChannel = channels
        .where((c) => c.type == 'TEXT' && !c.isAnnouncement)
        .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.gavel, color: AppTheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nội quy & Quy định Cộng đồng',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng đọc kỹ quy định của ${fandom.name} trước khi tham gia nhắn tin và phát biểu trên các kênh.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                  ),
                ),
                Divider(height: 32, color: palette.border),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    (fandom.rulesTos != null &&
                            fandom.rulesTos!.trim().isNotEmpty)
                        ? fandom.rulesTos!
                        : '1. Tôn trọng Chủ Fandom và toàn bộ thành viên trong cộng đồng.\n'
                            '2. Không gửi tin nhắn rác (spam), quảng cáo hoặc nội dung vi phạm pháp luật.\n'
                            '3. Thảo luận đúng chủ đề của từng kênh.',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!rulesAcknowledged)
                      ElevatedButton.icon(
                        onPressed: onAcknowledgeRules,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'Tôi đã đọc và đồng ý tuân thủ nội quy',
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.success),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified,
                              color: AppTheme.success,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Đã xác nhận tuân thủ nội quy',
                              style: TextStyle(
                                color: AppTheme.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (firstTextChannel != null)
                        ElevatedButton.icon(
                          onPressed: () => onSelectChannel(firstTextChannel),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text('Vào kênh #${firstTextChannel.name}'),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
