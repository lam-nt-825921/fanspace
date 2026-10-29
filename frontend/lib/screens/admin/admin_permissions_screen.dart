import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});

  @override
  State<AdminPermissionsScreen> createState() => _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> {
  // Interactive Bitmask Calculator state
  int _calculatedBitmask = 19; // Default: Chat Moderator (1 + 2 + 16)
  int _testPermissionBit = 1; // Default check: SEND_MESSAGES

  final List<Map<String, dynamic>> _permissions = [
    {
      'bit': 0,
      'value': 1,
      'name': 'SEND_MESSAGES',
      'label': 'Gửi tin nhắn văn bản',
      'desc': 'Cho phép soạn và gửi tin nhắn trong các kênh văn bản được phân quyền.',
      'category': 'Giao tiếp',
    },
    {
      'bit': 1,
      'value': 2,
      'name': 'MANAGE_MESSAGES',
      'label': 'Quản lý tin nhắn',
      'desc': 'Xóa tin nhắn của người khác, ghim tin nhắn quan trọng (Pin), gỡ phản ứng.',
      'category': 'Kiểm duyệt',
    },
    {
      'bit': 2,
      'value': 4,
      'name': 'JOIN_VOICE',
      'label': 'Tham gia phòng Voice',
      'desc': 'Kết nối vào phòng Voice WebRTC để lắng nghe các diễn giả.',
      'category': 'Âm thanh',
    },
    {
      'bit': 3,
      'value': 8,
      'name': 'SPEAK_VOICE',
      'label': 'Phát biểu trong phòng Voice',
      'desc': 'Bật micro phát biểu trực tiếp trong phòng Open Mic hoặc được duyệt lên Stage.',
      'category': 'Âm thanh',
    },
    {
      'bit': 4,
      'value': 16,
      'name': 'MUTE_MEMBERS',
      'label': 'Khóa mõm / Cấm phát ngôn (Mute)',
      'desc': 'Tạm khóa quyền chat hoặc tắt micro của thành viên vi phạm trong 1h, 24h, 7d.',
      'category': 'Kiểm duyệt',
    },
    {
      'bit': 5,
      'value': 32,
      'name': 'KICK_MEMBERS',
      'label': 'Trục xuất thành viên (Kick)',
      'desc': 'Đuổi thành viên ra khỏi Fandom (thành viên vẫn được phép xin gia nhập lại).',
      'category': 'Kiểm duyệt',
    },
    {
      'bit': 6,
      'value': 64,
      'name': 'BAN_MEMBERS',
      'label': 'Cấm vĩnh viễn (Ban)',
      'desc': 'Chặn vĩnh viễn ID người dùng khỏi Fandom, không thể tìm thấy hoặc vào lại.',
      'category': 'Kiểm duyệt',
    },
    {
      'bit': 7,
      'value': 128,
      'name': 'ADMINISTRATOR',
      'label': 'Toàn quyền Quản trị (Admin)',
      'desc': 'Bỏ qua toàn bộ kiểm tra bit quyền khác, nắm giữ quyền hạn tối cao trong Fandom.',
      'category': 'Hệ thống',
    },
    {
      'bit': 8,
      'value': 256,
      'name': 'MANAGE_ROLES',
      'label': 'Quản trị Vai trò (Roles)',
      'desc': 'Tạo vai trò mới, chọn màu tên, kéo thả thứ bậc ưu tiên và gán quyền hạn.',
      'category': 'Quản trị',
    },
    {
      'bit': 9,
      'value': 512,
      'name': 'MANAGE_CHANNELS',
      'label': 'Quản trị Kênh (Channels)',
      'desc': 'Tạo mới, sửa tên, phân quyền truy cập và xóa các kênh Text hoặc Voice.',
      'category': 'Quản trị',
    },
    {
      'bit': 10,
      'value': 1024,
      'name': 'MANAGE_MEMBERSHIP',
      'label': 'Quản lý Gói Hội viên (Membership)',
      'desc': 'Thiết lập 1 đến 4 mốc Tier Hội viên, định giá coin/VND và thiết lập quyền lợi.',
      'category': 'Tài chính',
    },
  ];

  final List<Map<String, dynamic>> _roles = [
    {
      'name': 'Chủ Fandom (Owner)',
      'mask': 2047,
      'badgeColor': const Color(0xFFEF4444),
      'desc': 'Toàn quyền 100% mọi phân hệ, duy nhất có quyền gán Preset Mod và chuyển nhượng Fandom.',
    },
    {
      'name': 'Preset Co-Host / Admin',
      'mask': 1023,
      'badgeColor': const Color(0xFFF59E0B),
      'desc': 'Phó quản trị viên Fandom do Owner chỉ định, có quyền kiểm duyệt và cấu hình kênh.',
    },
    {
      'name': 'Preset Chat Moderator',
      'mask': 19, // 1 + 2 + 16
      'badgeColor': const Color(0xFF10B981),
      'desc': 'Quản lý trật tự khung chat: ghim tin, xóa tin nhắn xấu và mute người vi phạm.',
    },
    {
      'name': 'Preset Voice Moderator',
      'mask': 28, // 4 + 8 + 16
      'badgeColor': const Color(0xFF06B6D4),
      'desc': 'Quản lý phòng đàm thoại Voice: duyệt giơ tay lên Stage, hạ người nói, mute micro.',
    },
    {
      'name': 'Thành viên (Member)',
      'mask': 13, // 1 + 4 + 8
      'badgeColor': const Color(0xFF6B7280),
      'desc': 'Thành viên chính thức: tham gia chat văn bản, vào voice room và phát biểu tự do.',
    },
    {
      'name': 'Khách vãng lai (Guest)',
      'mask': 0,
      'badgeColor': const Color(0xFF9CA3AF),
      'desc': 'Chỉ có quyền đọc/xem thông tin công khai (Read-Only), không thể chat hay voice.',
    },
  ];

  bool _hasBit(int mask, int bitValue) {
    if ((mask & 128) != 0) return true; // Administrator bit bypasses all checks
    return (mask & bitValue) != 0;
  }

  void _toggleBit(int bitValue) {
    setState(() {
      if ((_calculatedBitmask & bitValue) != 0) {
        _calculatedBitmask &= ~bitValue;
      } else {
        _calculatedBitmask |= bitValue;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Title(
      title: 'Ma trận Phân quyền & RBAC Bitmask | FanSpace Admin',
      color: AppTheme.primary,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.security, size: 20, color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              const Text('Hệ Thống Phân Quyền RBAC Bitmask & Governance'),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined, size: 18),
              label: const Text('Về Trang Chủ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Intro Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.memory, color: Colors.blueAccent, size: 36),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Kiến trúc Bitmask Permissions O(1) Tốc độ Cao',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Hệ thống lưu trữ toàn bộ quyền hạn dưới dạng một số nguyên 64-bit duy nhất trong Redis và PostgreSQL. Mọi thao tác kiểm tra quyền diễn ra bằng phép toán logic bitwise trên CPU với độ phức tạp O(1), triệt tiêu hoàn toàn nghẽn DB.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // SECTION 1: Interactive Bitmask Simulator
              Text('1. Trình Mô Phỏng & Tính Toán Bitmask Tương Tác', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 6),
              Text('Tích chọn các quyền hạn bên dưới để xem giá trị bitmask được sinh ra tự động và kiểm thử logic kiểm tra bitwise O(1).', style: TextStyle(fontSize: 13, color: subColor)),
              const SizedBox(height: 16),

              Card(
                color: surfaceColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Calculation Monitor
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black38 : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('GIÁ TRỊ THẬP PHÂN (DECIMAL MASK)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_calculatedBitmask',
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.3)),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('BIỂU DIỄN NHỊ PHÂN (BINARY BITS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '0b${_calculatedBitmask.toRadixString(2).padLeft(11, '0')}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Checkboxes Grid
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: _permissions.map((p) {
                          final isChecked = (_calculatedBitmask & (p['value'] as int)) != 0;
                          return FilterChip(
                            selected: isChecked,
                            label: Text('${p['name']} (${p['value']})'),
                            selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                            checkmarkColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isChecked ? AppTheme.primary : textColor,
                              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                            onSelected: (_) => _toggleBit(p['value'] as int),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Test verification widget
                      Row(
                        children: [
                          const Icon(Icons.bolt, color: Colors.amber, size: 22),
                          const SizedBox(width: 8),
                          Text('Kiểm tra quyền tức thì O(1):', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(width: 14),
                          DropdownButton<int>(
                            value: _testPermissionBit,
                            dropdownColor: surfaceColor,
                            items: _permissions.map<DropdownMenuItem<int>>((p) {
                              return DropdownMenuItem<int>(
                                value: p['value'] as int,
                                child: Text('${p['name']} (Bit ${p['bit']})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _testPermissionBit = val);
                            },
                          ),
                          const Spacer(),
                          Builder(
                            builder: (context) {
                              final allowed = _hasBit(_calculatedBitmask, _testPermissionBit);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: allowed ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: allowed ? AppTheme.success : AppTheme.error),
                                ),
                                child: Row(
                                  children: [
                                    Icon(allowed ? Icons.check_circle : Icons.cancel, color: allowed ? AppTheme.success : AppTheme.error, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      allowed ? 'CHO PHÉP (Quyền hợp lệ)' : 'TỪ CHỐI (Không có quyền)',
                                      style: TextStyle(
                                        color: allowed ? AppTheme.success : AppTheme.error,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // SECTION 2: Role Comparison Matrix
              Text('2. Ma Trận Phân Quyền Giữa Các Vai Trò Chuẩn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 6),
              Text('Bảng so sánh chi tiết các quyền hạn được cấp sẵn cho từng cấp bậc vai trò trong hệ sinh thái Fandom.', style: TextStyle(fontSize: 13, color: subColor)),
              const SizedBox(height: 16),

              Card(
                color: surfaceColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 24,
                    columns: [
                      const DataColumn(label: Text('Tên Quyền Hạn', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataColumn(label: Text('Phân loại', style: TextStyle(fontWeight: FontWeight.bold))),
                      ..._roles.map((r) => DataColumn(
                            label: Text(
                              r['name'] as String,
                              style: TextStyle(fontWeight: FontWeight.bold, color: r['badgeColor'] as Color),
                            ),
                          )),
                    ],
                    rows: _permissions.map((p) {
                      final pVal = p['value'] as int;
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(p['label'] as String, style: TextStyle(color: subColor, fontSize: 11)),
                              ],
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(p['category'] as String, style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                          ..._roles.map((r) {
                            final has = _hasBit(r['mask'] as int, pVal);
                            return DataCell(
                              Center(
                                child: Icon(
                                  has ? Icons.check_circle_rounded : Icons.remove_circle_outline,
                                  color: has ? AppTheme.success : Colors.grey.withValues(alpha: 0.4),
                                  size: 18,
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // SECTION 3: Standard Bitmask Specification Table
              Text('3. Danh Mục Chi Tiết 11 Bit Quyền Hệ Thống', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 16),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _permissions.length,
                itemBuilder: (ctx, idx) {
                  final item = _permissions[idx];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Bit', style: TextStyle(fontSize: 10, color: subColor)),
                                Text('${item['bit']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(width: 8),
                                    Text('(${item['label']})', style: TextStyle(fontSize: 13, color: subColor)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(item['desc'] as String, style: TextStyle(fontSize: 12, color: subColor)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Dec: ${item['value']}',
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
