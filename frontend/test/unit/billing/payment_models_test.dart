import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/fandom_model.dart';

void main() {
  group('FR-09 Billing & SePay 3-Way Reconciliation Models Unit Tests', () {
    test('FandomBankAccountModel & MembershipTierModel parse JSON and permissions', () {
      final data = FandomMembershipsDataModel.fromJson({
        'fandom_id': 'f-100',
        'bank_configured': true,
        'bank_account': {
          'id': 'ba-1',
          'fandom_id': 'f-100',
          'bank_code': 'MBBank',
          'account_number': '0389123456',
          'account_name': 'NGUYEN VAN A',
          'is_active': true,
          'updated_at': '2026-11-09T15:00:00Z',
        },
        'tiers': [
          {
            'id': 'role-vip-1',
            'fandom_id': 'f-100',
            'name': 'Fan Cứng VIP',
            'tier_level': 1,
            'color_hex': '#FFD700',
            'priority': 60,
            'permissions_bitmask': FandomPermissionBit.bypassSlowmode |
                FandomPermissionBit.readMessages |
                FandomPermissionBit.sendMessages,
            'price_fiat_vnd': 50000,
            'duration_days': 30,
            'is_owned': true,
            'owned_expires_at': '2026-12-09T15:00:00Z',
            'created_at': '2026-11-09T15:00:00Z',
          }
        ],
      });

      expect(data.bankConfigured, isTrue);
      expect(data.bankAccount, isNotNull);
      expect(data.bankAccount!.bankCode, 'MBBank');
      expect(data.bankAccount!.accountNumber, '0389123456');
      expect(data.tiers.length, 1);

      final tier = data.tiers.first;
      expect(tier.name, 'Fan Cứng VIP');
      expect(tier.priceFiatVnd, 50000);
      expect(tier.isOwned, isTrue);
      expect(tier.hasPermission(FandomPermissionBit.bypassSlowmode), isTrue);
    });

    test('PaymentOrderModel & PaymentTransactionModel evaluate 3-Way Matching states', () {
      final orderUnderpaid = PaymentOrderModel.fromJson({
        'id': 'ord-1',
        'order_code': 'DH12345678',
        'user_id': 'u-1',
        'fandom_id': 'f-100',
        'role_id': 'role-vip-1',
        'role_name': 'Fan Cứng VIP',
        'amount_vnd': 100000,
        'paid_amount_vnd': 40000,
        'remaining_amount_vnd': 60000,
        'duration_days': 30,
        'bank_code': 'MBBank',
        'account_number': '0389123456',
        'account_name': 'NGUYEN VAN A',
        'qr_url': 'https://qr.sepay.vn/img?acc=0389123456&bank=MBBank&amount=100000&des=DH12345678',
        'status': 'UNDERPAID',
        'expires_at': '2026-11-09T16:00:00Z',
        'created_at': '2026-11-09T15:45:00Z',
        'transactions': [
          {
            'id': 'tx-1',
            'sepay_transaction_id': 900101,
            'order_id': 'ord-1',
            'order_code': 'DH12345678',
            'gateway': 'MBBank',
            'transaction_date': '2026-11-09 22:46:00',
            'account_number': '0389123456',
            'transfer_type': 'in',
            'transfer_amount': 40000,
            'code': 'DH12345678',
            'content': 'CHUYEN TIEN DH12345678',
            'reconciliation_status': 'UNDERPAID',
            'audit_note': 'Chuyển thiếu 60,000đ',
            'created_at': '2026-11-09T15:46:00Z',
          }
        ],
      });

      expect(orderUnderpaid.orderCode, 'DH12345678');
      expect(orderUnderpaid.isUnderpaid, isTrue);
      expect(orderUnderpaid.isCompleted, isFalse);
      expect(orderUnderpaid.remainingAmountVnd, 60000);
      expect(orderUnderpaid.transactions.first.isDiscrepant, isTrue);

      final ledger = FandomLedgerModel.fromJson({
        'fandom_id': 'f-100',
        'total_revenue_vnd': 150000,
        'paid_orders_count': 2,
        'discrepant_transactions_count': 1,
        'orders': [],
        'transactions': [
          {
            'id': 'tx-matched',
            'sepay_transaction_id': 900102,
            'gateway': 'MBBank',
            'transaction_date': '2026-11-09 22:50:00',
            'account_number': '0389123456',
            'transfer_amount': 50000,
            'content': 'DH88889999',
            'reconciliation_status': 'MATCHED',
          }
        ],
      });

      expect(ledger.totalRevenueVnd, 150000);
      expect(ledger.paidOrdersCount, 2);
      expect(ledger.transactions.first.isDiscrepant, isFalse);
    });
  });
}
