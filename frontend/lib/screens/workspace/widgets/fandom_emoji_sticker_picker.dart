/// Dual-tab Fandom-exclusive Emoji & Sticker picker with Membership Tier lock indicators.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';

class FandomEmojiStickerPicker extends StatefulWidget {
  final List<FandomEmojiModel> items;
  final int userHighestTierLevel;
  final ValueChanged<FandomEmojiModel> onSelectEmoji;
  final ValueChanged<FandomEmojiModel> onSelectSticker;
  final VoidCallback? onOpenMembershipTiers;

  const FandomEmojiStickerPicker({
    super.key,
    required this.items,
    this.userHighestTierLevel = 0,
    required this.onSelectEmoji,
    required this.onSelectSticker,
    this.onOpenMembershipTiers,
  });

  static Future<void> show(
    BuildContext context, {
    required List<FandomEmojiModel> items,
    int userHighestTierLevel = 0,
    required ValueChanged<FandomEmojiModel> onSelectEmoji,
    required ValueChanged<FandomEmojiModel> onSelectSticker,
    VoidCallback? onOpenMembershipTiers,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
          child: FandomEmojiStickerPicker(
            items: items,
            userHighestTierLevel: userHighestTierLevel,
            onSelectEmoji: (emoji) {
              Navigator.of(ctx).pop();
              onSelectEmoji(emoji);
            },
            onSelectSticker: (sticker) {
              Navigator.of(ctx).pop();
              onSelectSticker(sticker);
            },
            onOpenMembershipTiers: onOpenMembershipTiers == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    onOpenMembershipTiers();
                  },
          ),
        ),
      ),
    );
  }

  @override
  State<FandomEmojiStickerPicker> createState() =>
      _FandomEmojiStickerPickerState();
}

class _FandomEmojiStickerPickerState extends State<FandomEmojiStickerPicker> {
  FandomEmojiModel? _lockedSelectionPrompt;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emojis = widget.items.where((e) => !e.isSticker).toList();
    final stickers = widget.items.where((e) => e.isSticker).toList();

    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kho Emoji & Sticker Độc Quyền Fandom',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (widget.onOpenMembershipTiers != null)
                    TextButton.icon(
                      key: const Key('btn_picker_upgrade_membership'),
                      onPressed: widget.onOpenMembershipTiers,
                      icon: const Icon(
                        Icons.workspace_premium,
                        size: 16,
                        color: Colors.amber,
                      ),
                      label: const Text(
                        'Mở khóa VIP',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            TabBar(
              labelColor: AppTheme.primary,
              unselectedLabelColor: palette.textSecondary,
              indicatorColor: AppTheme.primary,
              tabs: [
                Tab(
                  key: const Key('tab_picker_emojis'),
                  text: 'Emoji Độc Quyền (${emojis.length})',
                ),
                Tab(
                  key: const Key('tab_picker_stickers'),
                  text: 'Sticker Độc Quyền (${stickers.length})',
                ),
              ],
            ),
            if (_lockedSelectionPrompt != null)
              Container(
                key: const Key('banner_locked_emoji_prompt'),
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cần gói "${_lockedSelectionPrompt!.minTierName}" (Cấp ${_lockedSelectionPrompt!.minTierLevel}) để mở khóa ${_lockedSelectionPrompt!.shortcode}',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.onOpenMembershipTiers != null)
                      TextButton(
                        onPressed: widget.onOpenMembershipTiers,
                        child: const Text('Mua gói ngay'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildGrid(
                    palette,
                    items: emojis,
                    isStickerGrid: false,
                    emptyTitle: 'Chưa có Emoji độc quyền nào',
                    emptySubtitle:
                        'Chủ Fandom có thể tải lên bộ Emoji riêng trong mục Quản lý Kinh doanh.',
                  ),
                  _buildGrid(
                    palette,
                    items: stickers,
                    isStickerGrid: true,
                    emptyTitle: 'Chưa có Sticker độc quyền nào',
                    emptySubtitle:
                        'Chủ Fandom có thể tải lên bộ Sticker lớn trong mục Quản lý Kinh doanh.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    AppPalette palette, {
    required List<FandomEmojiModel> items,
    required bool isStickerGrid,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isStickerGrid
                    ? Icons.sticky_note_2_outlined
                    : Icons.emoji_emotions_outlined,
                size: 42,
                color: palette.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                emptyTitle,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isStickerGrid ? 3 : 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: isStickerGrid ? 0.9 : 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isUnlocked = item.isUnlocked;
        final imgSize = isStickerGrid ? 64.0 : 40.0;

        return InkWell(
          key: Key('picker_item_${item.code}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (!isUnlocked) {
              setState(() {
                _lockedSelectionPrompt = item;
              });
              return;
            }
            if (item.isSticker) {
              widget.onSelectSticker(item);
            } else {
              widget.onSelectEmoji(item);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isUnlocked
                  ? palette.surfaceLight.withValues(alpha: 0.65)
                  : palette.surfaceLight.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isUnlocked
                    ? AppTheme.primary.withValues(alpha: 0.35)
                    : palette.border,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: isUnlocked ? 1.0 : 0.45,
                        child: Image.network(
                          item.imageUrl,
                          width: imgSize,
                          height: imgSize,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(
                            item.isSticker
                                ? Icons.sticky_note_2_rounded
                                : Icons.emoji_emotions_rounded,
                            size: imgSize * 0.75,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.shortcode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isUnlocked)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      key: Key('lock_badge_${item.code}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Text(
                        '🔒 Cấp ${item.minTierLevel}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
