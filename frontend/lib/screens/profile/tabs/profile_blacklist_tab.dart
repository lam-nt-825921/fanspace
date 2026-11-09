/// Blacklist management tab inside UserSettingsDialog.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ProfileBlacklistTab extends StatefulWidget {
  const ProfileBlacklistTab({super.key});

  @override
  State<ProfileBlacklistTab> createState() => _ProfileBlacklistTabState();
}

class _ProfileBlacklistTabState extends State<ProfileBlacklistTab> {
  final List<Map<String, String>> _mockBlacklist = [
    {
      'id': '1',
      'name': 'Spammer Bot 01',
      'username': 'bot_spammer_01',
      'reason': 'Spam tin nhắn quảng cáo không phù hợp',
      'date': '18/10/2026',
    },
    {
      'id': '2',
      'name': 'Toxic User X',
      'username': 'toxic_user_x',
      'reason': 'Vi phạm quy tắc ứng xử cộng đồng',
      'date': '19/10/2026',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Danh sách chặn (Blacklist)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Các tài khoản bị bạn chặn sẽ không thể gửi tin nhắn hoặc tương tác.',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Tính năng tìm kiếm tài khoản để thêm vào blacklist.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add_disabled, size: 16),
                label: const Text('Chặn người dùng'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _mockBlacklist.isEmpty
                ? Center(
                    child: Text(
                      'Danh sách chặn hiện đang trống.',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: _mockBlacklist.length,
                    itemBuilder: (ctx, idx) {
                      final item = _mockBlacklist[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: palette.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.border),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.error,
                            child: Icon(
                              Icons.block,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            item['name']!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: palette.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            '@${item['username']} • Lý do: ${item['reason']}',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              setState(() => _mockBlacklist.removeAt(idx));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Đã bỏ chặn ${item['name']}.'),
                                ),
                              );
                            },
                            child: const Text(
                              'Bỏ chặn',
                              style: TextStyle(color: AppTheme.error),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
