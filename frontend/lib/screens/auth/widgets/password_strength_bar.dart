import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PasswordStrengthBar extends StatelessWidget {
  final String password;

  const PasswordStrengthBar({
    super.key,
    required this.password,
  });

  int _calculateStrength() {
    if (password.isEmpty) return 0;

    int score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[@$!%*?&^#()_+=\-[\]{}|;:,.<>?/~`]').hasMatch(password)) score++;

    return score;
  }

  Color _getColor(int score) {
    switch (score) {
      case 1:
        return AppTheme.error;
      case 2:
        return const Color(0xFFFF9800); // Orange
      case 3:
        return const Color(0xFFFFEB3B); // Yellow
      case 4:
        return AppTheme.success;
      default:
        return Colors.grey.withValues(alpha: 0.3);
    }
  }

  String _getLabel(int score) {
    switch (score) {
      case 1:
        return 'Mật khẩu yếu (cần tối thiểu 8 ký tự)';
      case 2:
        return 'Mật khẩu trung bình (thêm số hoặc chữ hoa)';
      case 3:
        return 'Mật khẩu khá an toàn';
      case 4:
        return 'Mật khẩu rất mạnh và tối ưu';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final score = _calculateStrength();
    final color = _getColor(score);
    final label = _getLabel(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: List.generate(4, (index) {
            final isFilled = index < score;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: isFilled ? color : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$score/4',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
