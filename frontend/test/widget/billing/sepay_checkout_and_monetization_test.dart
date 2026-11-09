import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/models/fandom_model.dart';
import 'package:frontend/providers/fandom_provider.dart';
import 'package:frontend/screens/workspace/fandom_management_dialog.dart';
import 'package:frontend/screens/workspace/sepay_checkout_dialog.dart';

class FakeBillingFandomProvider extends FandomProvider {
  PaymentOrderModel currentOrder;
  FandomMembershipsDataModel membershipsData;
  FandomLedgerModel ledgerData;
  int simulateCallCount = 0;
  int manualResolveCallCount = 0;

  FakeBillingFandomProvider({
    required this.currentOrder,
    required this.membershipsData,
    required this.ledgerData,
  });

  @override
  Future<List<FandomMemberModel>> fetchMembers(
    String identifier, {
    String? search,
    String statusFilter = 'ACTIVE',
    int limit = 50,
    int offset = 0,
  }) async =>
      [];

  @override
  Future<List<RoleModel>> fetchRoles(String identifier) async => [];

  @override
  Future<List<FandomInviteModel>> fetchInvites(String identifier) async => [];

  @override
  Future<FandomMembershipsDataModel> fetchMemberships(String identifier) async {
    return membershipsData;
  }

  @override
  Future<FandomLedgerModel?> fetchFandomLedger(
    String identifier, {
    String? statusFilter,
  }) async {
    return ledgerData;
  }

  @override
  Future<Map<String, dynamic>> createPaymentOrder(
    String identifier,
    String roleId,
  ) async {
    return {'success': true, 'order': currentOrder};
  }

  @override
  Future<PaymentOrderModel?> fetchPaymentOrder(String orderCode) async {
    return currentOrder;
  }

  @override
  Future<Map<String, dynamic>> simulateSepayWebhook({
    required String orderCode,
    int? transferAmount,
    String? customContent,
    String gateway = 'MBBank',
  }) async {
    simulateCallCount++;
    final paid = currentOrder.paidAmountVnd + (transferAmount ?? currentOrder.remainingAmountVnd);
    final isFull = paid >= currentOrder.amountVnd && customContent == null;
    final newStatus = customContent != null
        ? currentOrder.status
        : (isFull ? 'PAID' : 'UNDERPAID');
    final newRemaining =
        currentOrder.amountVnd > paid ? currentOrder.amountVnd - paid : 0;

    final tx = PaymentTransactionModel(
      id: 'tx-$simulateCallCount',
      sepayTransactionId: 900000 + simulateCallCount,
      orderId: currentOrder.id,
      orderCode: orderCode,
      gateway: gateway,
      transactionDate: '2026-11-09 23:00:00',
      accountNumber: currentOrder.accountNumber,
      transferAmount: transferAmount ?? currentOrder.remainingAmountVnd,
      code: customContent != null ? null : orderCode,
      content: customContent ?? 'CHUYEN TIEN $orderCode',
      reconciliationStatus: customContent != null
          ? 'UNMATCHED_ORDER'
          : (isFull ? 'MATCHED' : 'UNDERPAID'),
      auditNote: isFull ? 'Đối soát 3 bên khớp hoàn hảo' : 'Chuyển thiếu tiền',
    );

    currentOrder = PaymentOrderModel(
      id: currentOrder.id,
      orderCode: currentOrder.orderCode,
      userId: currentOrder.userId,
      fandomId: currentOrder.fandomId,
      roleId: currentOrder.roleId,
      roleName: currentOrder.roleName,
      amountVnd: currentOrder.amountVnd,
      paidAmountVnd: customContent != null ? currentOrder.paidAmountVnd : paid,
      remainingAmountVnd:
          customContent != null ? currentOrder.remainingAmountVnd : newRemaining,
      durationDays: currentOrder.durationDays,
      bankCode: currentOrder.bankCode,
      accountNumber: currentOrder.accountNumber,
      accountName: currentOrder.accountName,
      qrUrl: currentOrder.qrUrl,
      status: newStatus,
      expiresAt: currentOrder.expiresAt,
      transactions: [...currentOrder.transactions, tx],
    );

    return {
      'success': true,
      'data': {
        'message': isFull
            ? 'Đối soát 3 bên khớp hoàn hảo đơn $orderCode'
            : 'Đã ghi nhận vết giao dịch',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> resolveTransactionManually(
    String identifier,
    String transactionId, {
    required String orderCode,
    String? note,
  }) async {
    manualResolveCallCount++;
    return {
      'success': true,
      'transaction': PaymentTransactionModel(
        id: transactionId,
        sepayTransactionId: 999888,
        orderCode: orderCode,
        gateway: 'MBBank',
        transactionDate: '2026-11-09 23:05:00',
        accountNumber: '0389123456',
        transferAmount: 50000,
        content: 'CHUYEN KHOAN SAI MA',
        reconciliationStatus: 'MANUAL_MATCHED',
        auditNote: note,
      ),
    };
  }
}

void main() {
  final sampleTier = MembershipTierModel(
    id: 'tier-1',
    fandomId: 'f-1',
    name: 'Fan Cứng Kim Cương',
    tierLevel: 1,
    priceFiatVnd: 100000,
    durationDays: 30,
  );

  FakeBillingFandomProvider buildFakeProvider() {
    final initialOrder = PaymentOrderModel(
      id: 'ord-100',
      orderCode: 'DH88889999',
      userId: 'u-fan',
      fandomId: 'f-1',
      roleId: 'tier-1',
      roleName: 'Fan Cứng Kim Cương',
      amountVnd: 100000,
      paidAmountVnd: 0,
      remainingAmountVnd: 100000,
      durationDays: 30,
      bankCode: 'MBBank',
      accountNumber: '0389123456',
      accountName: 'CHU FANDOM VIP',
      qrUrl: 'https://qr.sepay.vn/img?acc=0389123456&bank=MBBank&amount=100000&des=DH88889999',
      status: 'PENDING',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );

    final memberships = FandomMembershipsDataModel(
      fandomId: 'f-1',
      bankConfigured: true,
      bankAccount: FandomBankAccountModel(
        id: 'ba-1',
        fandomId: 'f-1',
        bankCode: 'MBBank',
        accountNumber: '0389123456',
        accountName: 'CHU FANDOM VIP',
      ),
      tiers: [sampleTier],
    );

    final ledger = FandomLedgerModel(
      fandomId: 'f-1',
      totalRevenueVnd: 200000,
      paidOrdersCount: 2,
      discrepantTransactionsCount: 1,
      orders: [initialOrder],
      transactions: [
        PaymentTransactionModel(
          id: 'tx-unmatched-1',
          sepayTransactionId: 777111,
          gateway: 'MBBank',
          transactionDate: '2026-11-09 22:55:00',
          accountNumber: '0389123456',
          transferAmount: 100000,
          content: 'CHUYEN TIEN QUEN GHI MA DH',
          reconciliationStatus: 'UNMATCHED_ORDER',
          auditNote: 'Không tìm thấy đơn hàng khớp mã',
        ),
      ],
    );

    return FakeBillingFandomProvider(
      currentOrder: initialOrder,
      membershipsData: memberships,
      ledgerData: ledger,
    );
  }

  testWidgets(
    'SepayCheckoutDialog renders DH order code and transitions PENDING -> UNDERPAID -> PAID via Sandbox Simulator',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProvider = buildFakeProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<FandomProvider>.value(
          value: fakeProvider,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: SepayCheckoutDialog(
                fandomIdentifier: 'f-1',
                fandomName: 'Fandom Sơn Tùng M-TP',
                tier: sampleTier,
                initialOrder: fakeProvider.currentOrder,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Verify PENDING state and default SePay DH order code
      expect(find.byKey(const Key('banner_order_pending')), findsOneWidget);
      expect(find.text('DH88889999'), findsOneWidget);

      // 2. Simulate 50% underpayment (50.000đ / 100.000đ)
      final underpayBtn = find.byKey(const Key('btn_simulate_underpay'));
      await tester.ensureVisible(underpayBtn);
      await tester.pump();
      await tester.tap(underpayBtn);
      await tester.pump();

      expect(find.byKey(const Key('banner_order_underpaid')), findsOneWidget);
      expect(find.textContaining('UNDERPAID'), findsWidgets);

      // 3. Simulate paying the remaining 50.000đ -> Order becomes PAID!
      final fullPayBtn = find.byKey(const Key('btn_simulate_full_pay'));
      await tester.ensureVisible(fullPayBtn);
      await tester.pump();
      await tester.tap(fullPayBtn);
      await tester.pump();

      expect(find.byKey(const Key('banner_order_paid')), findsOneWidget);
      expect(find.text('Hoàn tất & Mở khóa đặc quyền'), findsOneWidget);
    },
  );

  testWidgets(
    'FandomManagementDialog 5th tab Kinh doanh displays Bank config, Membership Tiers, and Audit Trail manual resolution',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProvider = buildFakeProvider();
      final fandom = FandomDetailModel(
        id: 'f-1',
        name: 'Fandom Sơn Tùng M-TP',
        slug: 'son-tung-mtp',
        category: 'Âm nhạc',
        admissionMode: 'OPEN',
        memberCount: 15,
        ownerId: 'u-owner',
        ownerName: 'Chủ Fandom',
        isOwner: true,
        isMember: true,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<FandomProvider>.value(
          value: fakeProvider,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: FandomManagementDialog(fandom: fandom),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to 5th tab: Kinh doanh
      final monetizationTab = find.byKey(const Key('tab_monetization'));
      expect(monetizationTab, findsOneWidget);
      await tester.tap(monetizationTab);
      await tester.pumpAndSettle();

      // Verify Bank Account, Tier, and Audit Trail Ledger are rendered
      expect(find.byKey(const Key('input_bank_account_number')), findsOneWidget);
      expect(find.text('Fan Cứng Kim Cương'), findsOneWidget);
      expect(find.textContaining('UNMATCHED_ORDER'), findsOneWidget);

      // Click manual reconciliation on the unmatched transaction
      final resolveBtn = find.byKey(const Key('btn_resolve_tx_tx-unmatched-1'));
      await tester.ensureVisible(resolveBtn);
      await tester.tap(resolveBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('input_resolve_order_code')),
        'DH88889999',
      );
      await tester.tap(find.byKey(const Key('btn_confirm_manual_resolve')));
      await tester.pumpAndSettle();

      expect(fakeProvider.manualResolveCallCount, 1);
    },
  );
}
