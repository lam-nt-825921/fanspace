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
