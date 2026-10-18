import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _storageKey = 'theme_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadThemeFromStorage();
  }

  Future<void> _loadThemeFromStorage() async {
    try {
      final savedMode = await _storage.read(key: _storageKey);
      if (savedMode == 'light') {
        _themeMode = ThemeMode.light;
      } else if (savedMode == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.dark;
      }
      notifyListeners();
    } catch (_) {
      // Default to dark on error
      _themeMode = ThemeMode.dark;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      String value = 'dark';
      if (mode == ThemeMode.light) {
        value = 'light';
      } else if (mode == ThemeMode.system) {
        value = 'system';
      }
      await _storage.write(key: _storageKey, value: value);
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}
