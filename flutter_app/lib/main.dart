import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: WordBookApp()));
}

class WordBookApp extends ConsumerWidget {
  const WordBookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'WordBook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _buildHome(auth),
    );
  }

  Widget _buildHome(AuthState auth) {
    switch (auth.status) {
      case AuthStatus.unknown:
        // ★ 直接显示登录页，避免闪白屏/loading
        // 如果 token 有效会自动跳转到 HomeScreen
        return const LoginScreen();
      case AuthStatus.authenticated:
        return const HomeScreen();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
    }
  }
}
