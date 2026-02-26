import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);

    bool success;
    if (_isLogin) {
      success = await ref.read(authProvider.notifier).login(email, password);
    } else {
      final nickname = _nicknameController.text.trim();
      success = await ref.read(authProvider.notifier).register(
        email, password, nickname: nickname.isNotEmpty ? nickname : null,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (!success) {
        final error = ref.read(authProvider).error ?? 'Operation failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo area
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.menu_book_rounded,
                    size: 40, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  'WordBook',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Welcome back' : 'Create your account',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 40),

                // Form
                if (!_isLogin) ...[
                  TextField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      labelText: 'Nickname',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : Text(_isLogin ? 'Login' : 'Register'),
                  ),
                ),
                const SizedBox(height: 16),

                // Toggle
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin
                      ? "Don't have an account? Register"
                      : 'Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
