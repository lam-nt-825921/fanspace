/// Tab "Kinh doanh & Đối soát SePay" (FR-09) inside FandomManagementDialog.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/fandom_provider.dart';
import 'management/dialogs/monetization_dialogs.dart';

class FandomMonetizationTab extends StatefulWidget {
  final FandomDetailModel fandom;

  const FandomMonetizationTab({
    super.key,
    required this.fandom,
  });

  @override
  State<FandomMonetizationTab> createState() => _FandomMonetizationTabState();
}

class _FandomMonetizationTabState extends State<FandomMonetizationTab> {
  bool _isLoading = true;
  bool _isSavingBank = false;
  FandomMembershipsDataModel? _membershipsData;
  FandomLedgerModel? _ledger;
  final String _ledgerFilter = 'ALL';

  final _bankCodeList = const [
    'MBBank',
    'Vietcombank',
    'Techcombank',
    'ACB',
    'BIDV',
    'VietinBank',
    'VPBank',
    'TPBank',
  ];
  String _selectedBankCode = 'MBBank';
  final _accNumberCtrl = TextEditingController();
  final _accNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMonetizationData();
  }

  @override
  void dispose() {
    _accNumberCtrl.dispose();
    _accNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMonetizationData() async {
    setState(() => _isLoading = true);
    final provider = context.read<FandomProvider>();
    final results = await Future.wait([
      provider.fetchMemberships(widget.fandom.id),
      provider.fetchFandomLedger(
        widget.fandom.id,
        statusFilter: _ledgerFilter == 'ALL' ? null : _ledgerFilter,
      ),
    ]);
    if (!mounted) return;
    final memData = results[0] as FandomMembershipsDataModel;
    final ledgerData = results[1] as FandomLedgerModel?;

    setState(() {
      _membershipsData = memData;
      _ledger = ledgerData;
      if (memData.bankAccount != null) {
        final b = memData.bankAccount!;
        if (_bankCodeList.contains(b.bankCode)) {
          _selectedBankCode = b.bankCode;
        }
        _accNumberCtrl.text = b.accountNumber;
        _accNameCtrl.text = b.accountName;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveBankAccount() async {
    final accNum = _accNumberCtrl.text.trim();
    final accName = _accNameCtrl.text.trim().toUpperCase();
    if (accNum.length < 4 || accName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng nhập đầy đủ số tài khoản và tên chủ tài khoản.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSavingBank = true);
    final res = await context.read<FandomProvider>().upsertBankAccount(
          widget.fandom.id,
          bankCode: _selectedBankCode,
          accountNumber: accNum,
          accountName: accName,
        );
    if (!mounted) return;
    setState(() => _isSavingBank = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã lưu thông tin tài khoản ngân hàng nhận thanh toán!',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadMonetizationData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error']?.toString() ?? 'Lỗi lưu tài khoản.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final tiers = _membershipsData?.tiers ?? const [];
    final ledger = _ledger;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBankConfigCard(context),
          const SizedBox(height: 20),
          _buildMembershipTiersSection(context, tiers),
          const SizedBox(height: 20),
          _buildAuditLedgerSection(context, ledger),
        ],
      ),
    );
  }

  Widget _buildBankConfigCard(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '1. Tài khoản ngân hàng nhận thanh toán',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Hệ thống tự động ghi nhận giao dịch và mở khóa gói hội viên khi thành viên chuyển khoản đúng mã đơn.',
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedBankCode,
                  dropdownColor: palette.surfaceElevated,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: const InputDecoration(labelText: 'Ngân hàng'),
                  items: _bankCodeList
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBankCode = val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('input_bank_account_number'),
                  controller: _accNumberCtrl,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Số tài khoản nhận tiền',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('input_bank_account_name'),
                  controller: _accNameCtrl,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Tên chủ tài khoản',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const Key('btn_save_bank_account'),
              onPressed: _isSavingBank ? null : _saveBankAccount,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(
                _isSavingBank ? 'Đang lưu...' : 'Lưu thông tin tài khoản',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipTiersSection(
    BuildContext context,
    List<MembershipTierModel> tiers,
  ) {
    final palette = context.palette;
    final canCreateMore = tiers.length < 4;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '2. Gói hội viên trả phí • Đã tạo ${tiers.length}/4 gói',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const Key('btn_create_membership_tier'),
                onPressed: canCreateMore
                    ? () => CreateMembershipTierDialog.show(
                          context,
                          fandomId: widget.fandom.id,
                          existingTiersCount: tiers.length,
                          onCreated: _loadMonetizationData,
                        )
                    : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Tạo gói Hội viên'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (tiers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Chưa có gói Hội viên nào. Hãy tạo gói Hội viên để mở khóa kênh VIP và miễn Slow-mode cho Fan.',
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            )
          else
            ...tiers.map(
              (tier) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Tier ${tier.tierLevel}',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier.name,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${formatVndCurrency(tier.priceFiatVnd)} / ${tier.durationDays} ngày',
                            style: const TextStyle(
                              color: AppTheme.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Xóa gói Hội viên',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppTheme.error,
                        size: 20,
                      ),
                      onPressed: () async {
                        await context
                            .read<FandomProvider>()
                            .deleteMembershipTier(widget.fandom.id, tier.id);
                        _loadMonetizationData();
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditLedgerSection(
    BuildContext context,
    FandomLedgerModel? ledger,
  ) {
    final palette = context.palette;
    final txs = ledger?.transactions ?? const [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '3. Lịch sử giao dịch & Đối soát doanh thu',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadMonetizationData,
                icon: Icon(Icons.refresh, color: palette.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildKpiBadge(
                context,
                'Tổng doanh thu khớp',
                formatVndCurrency(ledger?.totalRevenueVnd ?? 0),
                AppTheme.success,
              ),
              const SizedBox(width: 10),
              _buildKpiBadge(
                context,
                'Đơn hoàn tất',
                '${ledger?.paidOrdersCount ?? 0} đơn',
                AppTheme.primary,
              ),
              const SizedBox(width: 10),
              _buildKpiBadge(
                context,
                'Giao dịch cần kiểm tra',
                '${ledger?.discrepantTransactionsCount ?? 0} giao dịch',
                AppTheme.warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (txs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Chưa có giao dịch thanh toán nào phát sinh.',
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            )
          else
            ...txs.map(
              (tx) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: tx.isDiscrepant
                        ? AppTheme.warning.withValues(alpha: 0.7)
                        : palette.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Giao dịch #${tx.sepayTransactionId} • +${formatVndCurrency(tx.transferAmount)}',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tx.isDiscrepant
                                ? AppTheme.warning.withValues(alpha: 0.16)
                                : AppTheme.success.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tx.reconciliationStatus,
                            style: TextStyle(
                              color: tx.isDiscrepant
                                  ? AppTheme.warning
                                  : AppTheme.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (tx.isDiscrepant)
                          OutlinedButton.icon(
                            key: Key('btn_resolve_tx_${tx.id}'),
                            onPressed: () =>
                                ManualResolveTransactionDialog.show(
                              context,
                              fandomId: widget.fandom.id,
                              transaction: tx,
                              onResolved: _loadMonetizationData,
                            ),
                            icon: const Icon(
                              Icons.build_circle_outlined,
                              size: 15,
                            ),
                            label: const Text(
                              'Đối soát thủ công',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nội dung CK: "${tx.content}" • Mã đơn: ${tx.orderCode ?? "Chưa khớp"}',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (tx.auditNote != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ghi chú kiểm toán: ${tx.auditNote}',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiBadge(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final palette = context.palette;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
