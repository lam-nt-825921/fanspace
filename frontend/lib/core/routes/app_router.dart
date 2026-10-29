import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/oauth_callback_screen.dart';
import '../../screens/home/public_directory_screen.dart';
import '../../screens/home/create_fandom_screen.dart';
import '../../screens/home/fandom_detail_screen.dart';
import '../../screens/admin/admin_login_screen.dart';
import '../../screens/admin/admin_permissions_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const PublicDirectoryScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      name: 'register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/auth/callback',
      name: 'oauth-callback',
      builder: (context, state) {
        final ticket = state.uri.queryParameters['ticket'];
        final error = state.uri.queryParameters['error'];
        return OAuthCallbackScreen(ticket: ticket, error: error);
      },
    ),
    GoRoute(
      path: '/fandoms/create',
      name: 'create-fandom',
      builder: (context, state) => const CreateFandomScreen(),
    ),
    GoRoute(
      path: '/fandoms/:slug',
      name: 'fandom-detail',
      builder: (context, state) {
        final slug = state.pathParameters['slug'] ?? '';
        return FandomDetailScreen(slug: slug);
      },
    ),
    GoRoute(
      path: '/admin/login',
      name: 'admin-login',
      builder: (context, state) => const AdminLoginScreen(),
    ),
    GoRoute(
      path: '/admin/permissions',
      name: 'admin-permissions',
      builder: (context, state) => const AdminPermissionsScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('404 - Không tìm thấy trang', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('Về trang chủ'),
          ),
        ],
      ),
    ),
  ),
);
