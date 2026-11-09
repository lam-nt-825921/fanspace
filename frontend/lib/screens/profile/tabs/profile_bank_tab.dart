/// Bank account configuration tab inside UserSettingsDialog.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ProfileBankTab extends StatefulWidget {
  const ProfileBankTab({super.key});

  @override
  State<ProfileBankTab> createState() => _ProfileBankTabState();
}

class _ProfileBankTabState extends State<ProfileBankTab> {
  final _bankNameController = TextEditingController(
    text: 'MB Bank',
  );
  final _accountNumberController = TextEditingController(text: '0987654321');
  final _accountNameController = TextEditingController(text: 'NGUYEN VAN A');

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tài khoản Ngân hàng Thụ hưởng',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Napas 247 VietQR',
                  style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Dùng để nhận doanh thu khi người hâm mộ đăng ký gói hội viên tại các Fandom bạn quản lý.',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E3C72).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _bankNameController.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  _accountNumberController.text.replaceAllMapped(
                    RegExp(r'.{4}'),
                    (match) => '${match.group(0)} ',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CHỦ TÀI KHOẢN',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Text(
                          _accountNameController.text.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'VIETQR READY',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Ngân hàng',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _bankNameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.account_balance, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          Text(
            'Số tài khoản ngân hàng',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _accountNumberController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.credit_card, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          Text(
            'Tên chủ tài khoản viết hoa không dấu',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _accountNameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person, size: 20),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Đã lưu cấu hình tài khoản ngân hàng VietQR!',
                    ),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Cập nhật tài khoản'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
