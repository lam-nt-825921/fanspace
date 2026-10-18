import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/fandom_provider.dart';
import 'screens/home/public_directory_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FanSpaceApp());
}

class FanSpaceApp extends StatelessWidget {
  const FanSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => FandomProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'FanSpace - Mạng Xã Hội Fandom',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const PublicDirectoryScreen(),
          );
        },
      ),
    );
  }
}
