import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
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
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => FandomProvider()),
      ],
      child: MaterialApp(
        title: 'FanSpace',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const PublicDirectoryScreen(),
      ),
    );
  }
}
