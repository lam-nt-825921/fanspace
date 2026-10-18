import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/theme_provider.dart';

class ThemeToggleButton extends StatelessWidget {
  final bool showLabel;

  const ThemeToggleButton({
    super.key,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final iconColor = isLight ? const Color(0xFF6C3CE9) : const Color(0xFFFFB74D);
    final bgColor = isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.1);

    if (showLabel) {
      return TextButton.icon(
        onPressed: () => themeProvider.toggleTheme(),
        icon: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          color: iconColor,
          size: 20,
        ),
        label: Text(
          isDark ? 'Giao diện sáng' : 'Giao diện tối',
          style: TextStyle(
            color: isLight ? Colors.black87 : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Tooltip(
      message: isDark ? 'Chuyển sang giao diện Sáng' : 'Chuyển sang giao diện Tối',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => themeProvider.toggleTheme(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey<bool>(isDark),
                color: iconColor,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
