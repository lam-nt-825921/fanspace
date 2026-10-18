import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/session_model.dart';

class ActiveSessionsDialog extends StatefulWidget {
  const ActiveSessionsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ActiveSessionsDialog(),
    );
  }

  @override
  State<ActiveSessionsDialog> createState() => _ActiveSessionsDialogState();
}

class _ActiveSessionsDialogState extends State<ActiveSessionsDialog> {
  List<SessionModel> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final list = await auth.listSessions();
    if (mounted) {
      setState(() {
        _sessions = list;
        _isLoading = false;
      });
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toUpperCase()) {
      case 'MOBILE':
        return Icons.phone_iphone_rounded;
      case 'DESKTOP':
        return Icons.laptop_chromebook_rounded;
      default:
        return Icons.language_rounded;
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.revokeSession(sessionId);
    if (ok) {
      await _loadSessions();
    }
  }

  Future<void> _revokeAllOther() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.revokeAllOtherSessions();
    if (ok) {
      await _loadSessions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: surfaceColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices_rounded, color: AppTheme.primary, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        'Thiết bị đang đăng nhập',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Mỗi nền tảng (Web, Mobile, Desktop) chỉ duy trì tối đa 1 phiên hoạt động duy nhất.',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _sessions.isEmpty
                        ? Center(child: Text('Không có phiên nào.', style: TextStyle(color: subColor)))
                        : ListView.separated(
                            itemCount: _sessions.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _sessions[index];
                              final timeStr = item.lastActiveAt != null
                                  ? DateFormat('HH:mm - dd/MM/yyyy').format(item.lastActiveAt!)
                                  : 'Không xác định';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: (item.isCurrent ? AppTheme.primary : Colors.grey)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _getPlatformIcon(item.platform),
                                    color: item.isCurrent ? AppTheme.primary : subColor,
                                    size: 24,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      item.deviceName ?? item.platform,
                                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 14),
                                    ),
                                    if (item.isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.success.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Hiện tại',
                                          style: TextStyle(color: AppTheme.success, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  'IP: ${item.ipAddress ?? "Ẩn danh"} • $timeStr',
                                  style: TextStyle(color: subColor, fontSize: 11),
                                ),
                                trailing: item.isCurrent
                                    ? null
                                    : IconButton(
                                        tooltip: 'Đăng xuất thiết bị này',
                                        icon: const Icon(Icons.logout, color: AppTheme.error, size: 20),
                                        onPressed: () => _revokeSession(item.id),
                                      ),
                              );
                            },
                          ),
              ),

              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _sessions.length > 1 ? _revokeAllOther : null,
                icon: const Icon(Icons.phonelink_erase_rounded, size: 18),
                label: const Text('Đăng xuất tất cả thiết bị khác'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
