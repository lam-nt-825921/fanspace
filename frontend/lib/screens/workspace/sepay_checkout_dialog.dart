/// SePay VietQR checkout dialog with real-time 3-way reconciliation status and Sandbox webhook simulator.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fandom_model.dart';
import '../../providers/fandom_provider.dart';
import 'management/dialogs/monetization_dialogs.dart';

class SepayCheckoutDialog extends StatefulWidget {
  final String fandomIdentifier;
  final String fandomName;
  final MembershipTierModel tier;
  final PaymentOrderModel? initialOrder;

  const SepayCheckoutDialog({
    super.key,
    required this.fandomIdentifier,
    required this.fandomName,
    required this.tier,
    this.initialOrder,
  });

  @override
  State<SepayCheckoutDialog> createState() => _SepayCheckoutDialogState();
}

class _SepayCheckoutDialogState extends State<SepayCheckoutDialog> {
  PaymentOrderModel? _order;
  bool _isLoading = true;
  bool _isSimulating = false;
  String? _errorMsg;
  String? _feedbackMsg;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  Duration _remainingTtl = const Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    if (widget.initialOrder != null) {
      _order = widget.initialOrder;
      _isLoading = false;
      _updateCountdown();
      _startTimers();
    } else {
      _initOrder();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initOrder() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final provider = context.read<FandomProvider>();
    final res = await provider.createPaymentOrder(
      widget.fandomIdentifier,
      widget.tier.id,
    );
    if (!mounted) return;
    if (res['success'] == true && res['order'] is PaymentOrderModel) {
      setState(() {
        _order = res['order'] as PaymentOrderModel;
        _isLoading = false;
      });
      _updateCountdown();
      _startTimers();
    } else {
      setState(() {
        _errorMsg = res['error']?.toString() ?? 'Không thể khởi tạo đơn hàng.';
        _isLoading = false;
      });
    }
  }

  void _startTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _order == null) return;
      _updateCountdown();
    });

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _order == null || _order!.isCompleted) return;
      _refreshOrder();
    });
  }

  void _updateCountdown() {
    if (_order == null) return;
    final diff = _order!.expiresAt.difference(DateTime.now());
    setState(() {
      _remainingTtl = diff.isNegative ? Duration.zero : diff;
    });
  }

  Future<void> _refreshOrder() async {
    if (_order == null) return;
    final updated = await context
        .read<FandomProvider>()
        .fetchPaymentOrder(_order!.orderCode);
    if (!mounted || updated == null) return;
    setState(() {
      _order = updated;
    });
  }

  Future<void> _runSandboxSimulation({
    int? transferAmount,
    String? customContent,
  }) async {
    if (_order == null) return;
    setState(() {
      _isSimulating = true;
      _feedbackMsg = null;
    });
    final provider = context.read<FandomProvider>();
    final res = await provider.simulateSepayWebhook(
      orderCode: _order!.orderCode,
      transferAmount: transferAmount,
      customContent: customContent,
      gateway: _order!.bankCode,
    );
    await _refreshOrder();
    if (!mounted) return;
    setState(() {
      _isSimulating = false;
      if (res['success'] == true) {
        final data = res['data'];
        _feedbackMsg = data is Map<String, dynamic>
            ? data['message']?.toString()
            : 'Đã gửi Webhook SePay giả lập.';
      } else {
        _feedbackMsg = res['error']?.toString();
      }
    });
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMsg != null
                  ? _buildErrorView(context)
                  : _buildCheckoutBody(context),
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context) {
    final palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
        const SizedBox(height: 12),
        Text(
          _errorMsg!,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textPrimary, fontSize: 15),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Đóng'),
        ),
      ],
    );
  }

  Widget _buildCheckoutBody(BuildContext context) {
    final palette = context.palette;
    final order = _order!;
    final isPaid = order.isCompleted;
    final isUnderpaid = order.isUnderpaid;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thanh toán Gói Hội viên • ${widget.fandomName}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Gói ${order.roleName} • Thời hạn ${order.durationDays} ngày',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(isPaid),
                icon: Icon(Icons.close, color: palette.textSecondary),
              ),
            ],
          ),
          Divider(color: palette.border, height: 24),

          _buildReconciliationBanner(context, order),
          const SizedBox(height: 16),

          if (!isPaid)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 210,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: Image.network(
                          order.qrUrl,
                          key: const Key('sepay_qr_image'),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 88,
                                  color: Colors.black87,
                                ),
                                Text(
                                  'Mã QR Chuyển khoản',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hết hạn sau: ${_formatDuration(_remainingTtl)}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),

                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(
                          context,
                          'Ngân hàng thụ hưởng',
                          order.bankCode,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(
                          context,
                          'Số tài khoản',
                          order.accountNumber,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(
                          context,
                          'Chủ tài khoản',
                          order.accountName,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(
                          context,
                          isUnderpaid
                              ? 'Số tiền cần chuyển thêm'
                              : 'Số tiền thanh toán',
                          formatVndCurrency(order.remainingAmountVnd),
                          highlight: true,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'NỘI DUNG CHUYỂN KHOẢN BẮT BUỘC:',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.primary),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  order.orderCode,
                                  key: const Key('sepay_order_code_text'),
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Sao chép mã đơn hàng',
                                icon: const Icon(
                                  Icons.copy_rounded,
                                  size: 18,
                                  color: AppTheme.primary,
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: order.orderCode),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã sao chép mã ${order.orderCode}',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 18),

          if (!isPaid) _buildSandboxSimulatorBox(context, order),

          if (_feedbackMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _feedbackMsg!,
                key: const Key('sepay_feedback_message'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ],

          if (order.transactions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Lịch sử giao dịch của đơn hàng:',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...order.transactions.map(
              (tx) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '#${tx.sepayTransactionId} • +${formatVndCurrency(tx.transferAmount)} • ${tx.reconciliationStatus}',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      tx.transactionDate,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isPaid)
                TextButton.icon(
                  onPressed: _refreshOrder,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Kiểm tra trạng thái'),
                ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                key: const Key('btn_finish_checkout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isPaid ? AppTheme.success : AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(isPaid),
                icon: Icon(
                  isPaid ? Icons.verified_rounded : Icons.close_rounded,
                  size: 18,
                ),
                label: Text(
                  isPaid ? 'Hoàn tất & Mở khóa đặc quyền' : 'Đóng cửa sổ',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReconciliationBanner(
    BuildContext context,
    PaymentOrderModel order,
  ) {
    final palette = context.palette;

    if (order.isCompleted) {
      return Container(
        key: const Key('banner_order_paid'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.success),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Thanh toán thành công! Đã nhận ${formatVndCurrency(order.paidAmountVnd)} và kích hoạt gói "${order.roleName}".',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (order.isUnderpaid) {
      return Container(
        key: const Key('banner_order_underpaid'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Thanh toán chưa đủ • Trạng thái UNDERPAID: Đã nhận ${formatVndCurrency(order.paidAmountVnd)} / ${formatVndCurrency(order.amountVnd)}. '
                'Vui lòng chuyển bổ sung ${formatVndCurrency(order.remainingAmountVnd)} kèm mã ${order.orderCode}.',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const Key('banner_order_pending'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Đang chờ hệ thống xác nhận chuyển khoản cho mã đơn ${order.orderCode}...',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSandboxSimulatorBox(
    BuildContext context,
    PaymentOrderModel order,
  ) {
    final palette = context.palette;
    final halfAmount = (order.remainingAmountVnd / 2).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
                Icons.fact_check_outlined,
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Xác nhận chuyển khoản nhanh',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Chọn hình thức xác nhận thanh toán cho đơn hàng hiện tại:',
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                key: const Key('btn_simulate_full_pay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSimulating
                    ? null
                    : () => _runSandboxSimulation(
                          transferAmount: order.remainingAmountVnd,
                        ),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: Text(
                  'Đã chuyển đủ ${formatVndCurrency(order.remainingAmountVnd)}',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('btn_simulate_underpay'),
                onPressed: _isSimulating || halfAmount <= 0
                    ? null
                    : () => _runSandboxSimulation(transferAmount: halfAmount),
                icon: const Icon(Icons.call_split_rounded, size: 16),
                label: Text(
                  'Chuyển một phần ${formatVndCurrency(halfAmount)}',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('btn_simulate_wrong_memo'),
                onPressed: _isSimulating
                    ? null
                    : () => _runSandboxSimulation(
                          transferAmount: order.remainingAmountVnd,
                          customContent: 'CHUYEN KHOAN QUEN GHI MA DON',
                        ),
                icon: const Icon(Icons.help_outline_rounded, size: 16),
                label: const Text('Ghi nhầm nội dung chuyển khoản'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
  }) {
    final palette = context.palette;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: highlight ? AppTheme.success : palette.textPrimary,
              fontSize: highlight ? 15 : 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
