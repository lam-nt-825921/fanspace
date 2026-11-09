/// Dialogs for creating Membership Tiers and manually resolving discrepant SePay transactions.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/fandom_model.dart';
import '../../../../providers/fandom_provider.dart';

String formatVndCurrency(int vnd) {
  final s = vnd.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${buf.toString()}đ';
}

class CreateMembershipTierDialog extends StatefulWidget {
  final String fandomId;
  final int existingTiersCount;
  final VoidCallback onCreated;

  const CreateMembershipTierDialog({
    super.key,
    required this.fandomId,
    required this.existingTiersCount,
    required this.onCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required int existingTiersCount,
    required VoidCallback onCreated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CreateMembershipTierDialog(
        fandomId: fandomId,
        existingTiersCount: existingTiersCount,
        onCreated: onCreated,
      ),
    );
  }

  @override
  State<CreateMembershipTierDialog> createState() =>
      _CreateMembershipTierDialogState();
}

class _CreateMembershipTierDialogState
    extends State<CreateMembershipTierDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController(text: '50000');
  final TextEditingController _durationCtrl = TextEditingController(text: '30');
  bool _bypassSlowmode = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    int tierLevel = widget.existingTiersCount + 1;
    if (tierLevel > 4) tierLevel = 4;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        'Tạo gói hội viên mới',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('input_tier_name'),
                controller: _nameCtrl,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Tên gói hội viên',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_tier_price'),
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Mức giá theo VNĐ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('input_tier_duration'),
                      controller: _durationCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Thời hạn theo ngày',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Đặc quyền Miễn Slow-mode & Mở khóa kênh VIP',
                  style: TextStyle(color: palette.textPrimary, fontSize: 13),
                ),
                value: _bypassSlowmode,
                onChanged: (v) => setState(() => _bypassSlowmode = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_submit_create_tier'),
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
            final days = int.tryParse(_durationCtrl.text.trim()) ?? 30;
            if (name.isEmpty || price < 2000) return;

            final bitmask =
                _bypassSlowmode ? FandomPermissionBit.bypassSlowmode : 0;
            final provider = context.read<FandomProvider>();
            final messenger = ScaffoldMessenger.maybeOf(context);
            Navigator.of(context).pop();
            final res = await provider.createMembershipTier(
              widget.fandomId,
              name: name,
              tierLevel: tierLevel,
              priceFiatVnd: price,
              durationDays: days,
              permissionsBitmask: bitmask,
            );
            if (res['success'] == true) {
              widget.onCreated();
            } else {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(res['error']?.toString() ?? 'Lỗi tạo gói'),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          child: const Text('Tạo gói'),
        ),
      ],
    );
  }
}

class ManualResolveTransactionDialog extends StatefulWidget {
  final String fandomId;
  final PaymentTransactionModel transaction;
  final VoidCallback onResolved;

  const ManualResolveTransactionDialog({
    super.key,
    required this.fandomId,
    required this.transaction,
    required this.onResolved,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required PaymentTransactionModel transaction,
    required VoidCallback onResolved,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ManualResolveTransactionDialog(
        fandomId: fandomId,
        transaction: transaction,
        onResolved: onResolved,
      ),
    );
  }

  @override
  State<ManualResolveTransactionDialog> createState() =>
      _ManualResolveTransactionDialogState();
}

class _ManualResolveTransactionDialogState
    extends State<ManualResolveTransactionDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(
      text: widget.transaction.orderCode ?? widget.transaction.code ?? '',
    );
    _noteCtrl = TextEditingController(
      text: 'Khách chuyển khoản ghi nhầm mã đơn',
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tx = widget.transaction;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        'Đối soát thủ công Giao dịch #${tx.sepayTransactionId}',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Số tiền nhận: ${formatVndCurrency(tx.transferAmount)}\nNội dung gốc: "${tx.content}"',
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('input_resolve_order_code'),
              controller: _codeCtrl,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Mã đơn hàng cần khớp',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('input_resolve_note'),
              controller: _noteCtrl,
              style: TextStyle(color: palette.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Ghi chú xác nhận',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_confirm_manual_resolve'),
          onPressed: () async {
            final targetCode = _codeCtrl.text.trim().toUpperCase();
            if (targetCode.isEmpty) return;
            final provider = context.read<FandomProvider>();
            final messenger = ScaffoldMessenger.maybeOf(context);
            Navigator.of(context).pop();
            final res = await provider.resolveTransactionManually(
              widget.fandomId,
              tx.id,
              orderCode: targetCode,
              note: _noteCtrl.text.trim(),
            );
            if (res['success'] == true) {
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Đã đối soát thủ công và kích hoạt gói Hội viên thành công!',
                  ),
                  backgroundColor: AppTheme.success,
                ),
              );
              widget.onResolved();
            } else {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    res['error']?.toString() ?? 'Không thể đối soát.',
                  ),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          child: const Text('Xác nhận & Kích hoạt Gói'),
        ),
      ],
    );
  }
}
