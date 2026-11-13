/// Dialogs for creating Membership Tiers, managing Fandom Emojis/Stickers, and manually resolving discrepant SePay transactions.
library;

import 'package:file_picker/file_picker.dart';
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
  final MembershipTierModel? existingTier;
  final VoidCallback onCreated;

  const CreateMembershipTierDialog({
    super.key,
    required this.fandomId,
    required this.existingTiersCount,
    this.existingTier,
    required this.onCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required int existingTiersCount,
    MembershipTierModel? existingTier,
    required VoidCallback onCreated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CreateMembershipTierDialog(
        fandomId: fandomId,
        existingTiersCount: existingTiersCount,
        existingTier: existingTier,
        onCreated: onCreated,
      ),
    );
  }

  @override
  State<CreateMembershipTierDialog> createState() =>
      _CreateMembershipTierDialogState();
}

class EditMembershipTierDialog {
  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required MembershipTierModel existingTier,
    required VoidCallback onUpdated,
  }) {
    return CreateMembershipTierDialog.show(
      context,
      fandomId: fandomId,
      existingTiersCount: existingTier.tierLevel,
      existingTier: existingTier,
      onCreated: onUpdated,
    );
  }
}

class _CreateMembershipTierDialogState
    extends State<CreateMembershipTierDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _durationCtrl;
  late int _tierLevel;
  late int _membershipPerksBitmask;
  late bool _bypassSlowmodeRbac;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTier;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _priceCtrl = TextEditingController(
      text: (existing?.priceFiatVnd ?? 50000).toString(),
    );
    _durationCtrl = TextEditingController(
      text: (existing?.durationDays ?? 30).toString(),
    );
    int defaultLevel = existing?.tierLevel ?? (widget.existingTiersCount + 1);
    if (defaultLevel < 1) defaultLevel = 1;
    if (defaultLevel > 4) defaultLevel = 4;
    _tierLevel = defaultLevel;
    _membershipPerksBitmask =
        existing?.membershipPerksBitmask ?? FandomMembershipPerkBit.defaultAll;
    _bypassSlowmodeRbac = existing != null
        ? existing.hasPermission(FandomPermissionBit.bypassSlowmode)
        : false;
  }

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
    final isEdit = widget.existingTier != null;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        isEdit ? 'Chỉnh sửa gói hội viên' : 'Tạo gói hội viên mới',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              DropdownButtonFormField<int>(
                key: const Key('dropdown_tier_level'),
                isExpanded: true,
                initialValue: _tierLevel,
                dropdownColor: palette.surfaceElevated,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Cấp độ gói (Tier 1..4 - Dùng mở khóa Emoji & Kênh)',
                ),
                items: [1, 2, 3, 4]
                    .map(
                      (lvl) => DropdownMenuItem<int>(
                        value: lvl,
                        child: Text('Cấp $lvl (Tier $lvl)'),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _tierLevel = val);
                },
              ),
              const SizedBox(height: 16),
              Material(
                key: const Key('section_membership_perks_bitmask'),
                color: Colors.amber.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Colors.amber.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium_outlined,
                            color: Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Đặc quyền Hội viên Độc quyền (Tách riêng Role)',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Các quyền này chỉ dành riêng cho hệ thống Hội viên (không ảnh hưởng quyền quản trị Role).',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...FandomMembershipPerkBit.allPerks.map((perk) {
                        final bit = perk['bit'] as int;
                        final enabled = (_membershipPerksBitmask & bit) != 0;
                        return CheckboxListTile(
                          key: Key('chk_membership_perk_$bit'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: Colors.amber,
                          title: Text(
                            perk['name'] as String,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            perk['desc'] as String,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          value: enabled,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _membershipPerksBitmask |= bit;
                              } else {
                                _membershipPerksBitmask &= ~bit;
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Miễn Slow-mode toàn hệ thống Fandom',
                  style: TextStyle(color: palette.textPrimary, fontSize: 13),
                ),
                subtitle: Text(
                  'Nếu tắt, chủ Fandom vẫn có thể bật ưu tiên miễn Slow-mode cho từng kênh riêng.',
                  style: TextStyle(color: palette.textSecondary, fontSize: 11),
                ),
                value: _bypassSlowmodeRbac,
                onChanged: (v) => setState(() => _bypassSlowmodeRbac = v),
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
                _bypassSlowmodeRbac ? FandomPermissionBit.bypassSlowmode : 0;
            final provider = context.read<FandomProvider>();
            final messenger = ScaffoldMessenger.maybeOf(context);
            Navigator.of(context).pop();

            final Map<String, dynamic> res;
            if (isEdit) {
              res = await provider.updateMembershipTier(
                widget.fandomId,
                widget.existingTier!.id,
                name: name,
                tierLevel: _tierLevel,
                priceFiatVnd: price,
                durationDays: days,
                permissionsBitmask: bitmask,
                membershipPerksBitmask: _membershipPerksBitmask,
              );
            } else {
              res = await provider.createMembershipTier(
                widget.fandomId,
                name: name,
                tierLevel: _tierLevel,
                priceFiatVnd: price,
                durationDays: days,
                permissionsBitmask: bitmask,
                membershipPerksBitmask: _membershipPerksBitmask,
              );
            }
            if (res['success'] == true) {
              widget.onCreated();
            } else {
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    res['error']?.toString() ?? 'Lỗi lưu gói Hội viên',
                  ),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          },
          child: Text(isEdit ? 'Lưu thay đổi' : 'Tạo gói'),
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

class UpsertFandomEmojiDialog extends StatefulWidget {
  final String fandomId;
  final List<MembershipTierModel> tiers;
  final FandomEmojiModel? existing;
  final VoidCallback onSaved;

  const UpsertFandomEmojiDialog({
    super.key,
    required this.fandomId,
    required this.tiers,
    this.existing,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String fandomId,
    required List<MembershipTierModel> tiers,
    FandomEmojiModel? existing,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => UpsertFandomEmojiDialog(
        fandomId: fandomId,
        tiers: tiers,
        existing: existing,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<UpsertFandomEmojiDialog> createState() =>
      _UpsertFandomEmojiDialogState();
}

class _UpsertFandomEmojiDialogState extends State<UpsertFandomEmojiDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _imageUrlCtrl;
  String _assetType = 'EMOJI';
  int _minTierLevel = 1;
  bool _isUploading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: e?.code ?? '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _imageUrlCtrl = TextEditingController(text: e?.imageUrl ?? '');
    _assetType = e?.assetType.toUpperCase() == 'STICKER' ? 'STICKER' : 'EMOJI';
    _minTierLevel = e?.minTierLevel.clamp(1, 4) ?? 1;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  String _tierLabel(int level) {
    for (final t in widget.tiers) {
      if (t.tierLevel == level) {
        return 'Cấp $level — ${t.name}';
      }
    }
    return 'Cấp $level — Gói Hội viên Tier $level';
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploading) return;
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !mounted) return;

    setState(() => _isUploading = true);
    final res = await context.read<FandomProvider>().uploadFandomEmojiImage(
          widget.fandomId,
          bytes: bytes,
          filename: file.name,
        );
    if (!mounted) return;
    setState(() => _isUploading = false);

    if (res['success'] == true && res['url'] != null) {
      setState(() {
        _imageUrlCtrl.text = res['url'].toString();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['error']?.toString() ?? 'Không thể tải ảnh lên.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().replaceAll(':', '').toLowerCase();
    final name = _nameCtrl.text.trim();
    final imageUrl = _imageUrlCtrl.text.trim();

    if (code.length < 3 || name.isEmpty || imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng nhập mã shortcode (tối thiểu 3 ký tự), tên hiển thị và ảnh Emoji/Sticker.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final provider = context.read<FandomProvider>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    Map<String, dynamic> res;
    if (widget.existing == null) {
      res = await provider.createFandomEmoji(
        widget.fandomId,
        code: code,
        name: name,
        assetType: _assetType,
        imageUrl: imageUrl,
        minTierLevel: _minTierLevel,
      );
    } else {
      res = await provider.updateFandomEmoji(
        widget.fandomId,
        widget.existing!.id,
        code: code,
        name: name,
        assetType: _assetType,
        imageUrl: imageUrl,
        minTierLevel: _minTierLevel,
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] == true) {
      Navigator.of(context).pop();
      widget.onSaved();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null
                ? 'Đã thêm $_assetType độc quyền :$code: thành công!'
                : 'Đã cập nhật $_assetType :$code: thành công!',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(res['error']?.toString() ?? 'Lỗi lưu Emoji/Sticker.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isEdit = widget.existing != null;

    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        isEdit
            ? 'Cập nhật Emoji / Sticker Độc quyền'
            : 'Thêm Emoji / Sticker Độc quyền',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phân loại tài nguyên',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      key: const Key('chip_asset_type_emoji'),
                      label: const Text('😊 Emoji (Nhỏ inline)'),
                      selected: _assetType == 'EMOJI',
                      onSelected: (_) => setState(() => _assetType = 'EMOJI'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      key: const Key('chip_asset_type_sticker'),
                      label: const Text('🎨 Sticker (Ảnh lớn)'),
                      selected: _assetType == 'STICKER',
                      onSelected: (_) => setState(() => _assetType = 'STICKER'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_emoji_code'),
                      controller: _codeCtrl,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Mã Shortcode (vd: star_glow)',
                        prefixText: ':',
                        suffixText: ':',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('input_emoji_name'),
                      controller: _nameCtrl,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Tên hiển thị',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_emoji_image_url'),
                      controller: _imageUrlCtrl,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'URL ảnh (PNG, WEBP, JPG)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const Key('btn_pick_emoji_image'),
                    onPressed: _isUploading ? null : _pickAndUploadImage,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file, size: 16),
                    label: Text(_isUploading ? 'Đang tải...' : 'Tải ảnh'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                key: const Key('dropdown_emoji_min_tier'),
                isExpanded: true,
                initialValue: _minTierLevel,
                dropdownColor: palette.surfaceElevated,
                style: TextStyle(color: palette.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Cấp độ Gói Hội viên mở khóa (Do Chủ Fandom quyết)',
                ),
                items: [1, 2, 3, 4]
                    .map(
                      (lvl) => DropdownMenuItem<int>(
                        value: lvl,
                        child: Text(_tierLabel(lvl)),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _minTierLevel = val);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const Key('btn_submit_upsert_emoji'),
          onPressed: _isSaving ? null : _submit,
          child: Text(
            _isSaving
                ? 'Đang lưu...'
                : (isEdit ? 'Lưu cập nhật' : 'Tạo mới'),
          ),
        ),
      ],
    );
  }
}
