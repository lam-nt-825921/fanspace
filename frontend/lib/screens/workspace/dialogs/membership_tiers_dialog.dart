/// Dialog listing VIP Membership Tiers for a Fandom and launching SePay checkout.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/fandom_model.dart';
import '../sepay_checkout_dialog.dart';

class MembershipTiersDialog extends StatelessWidget {
  final FandomDetailModel fandom;
  final FandomMembershipsDataModel membershipsData;
  final Future<void> Function() onTierActivated;

  const MembershipTiersDialog({
    super.key,
    required this.fandom,
    required this.membershipsData,
    required this.onTierActivated,
  });

  static Future<void> show(
    BuildContext context, {
    required FandomDetailModel fandom,
    required FandomMembershipsDataModel membershipsData,
    required Future<void> Function() onTierActivated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MembershipTiersDialog(
        fandom: fandom,
        membershipsData: membershipsData,
        onTierActivated: onTierActivated,
      ),
    );
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
          const Icon(Icons.workspace_premium_rounded, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Gói Hội viên VIP • ${fandom.name}',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: membershipsData.tiers.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Fandom này hiện chưa mở bán gói Hội viên trả phí nào.',
                  style: TextStyle(color: palette.textSecondary),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: membershipsData.tiers.map((tier) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: tier.isOwned
                              ? AppTheme.success
                              : palette.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      tier.name,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (tier.isOwned)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.success
                                              .withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Đang sở hữu',
                                          style: TextStyle(
                                            color: AppTheme.success,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${tier.priceFiatVnd}đ / ${tier.durationDays} ngày • Mở khóa kênh VIP & Miễn Slow-mode',
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            key: Key('btn_buy_tier_${tier.id}'),
                            onPressed: () async {
                              final parentNavigator = Navigator.of(context);
                              parentNavigator.pop();
                              final activated = await showDialog<bool>(
                                context: parentNavigator.context,
                                builder: (_) => SepayCheckoutDialog(
                                  fandomIdentifier: fandom.id,
                                  fandomName: fandom.name,
                                  tier: tier,
                                ),
                              );
                              if (activated == true) {
                                await onTierActivated();
                              }
                            },
                            icon: const Icon(Icons.qr_code_2, size: 16),
                            label: Text(
                              tier.isOwned ? 'Gia hạn' : 'Đăng ký ngay',
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
