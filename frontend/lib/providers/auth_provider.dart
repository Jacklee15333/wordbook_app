import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? token;
  final String? userId;
  final String? email;
  final String? nickname;
  final bool isAdmin;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.userId,
    this.email,
    this.nickname,
    this.isAdmin = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    String? userId,
    String? email,
    String? nickname,
    bool? isAdmin,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      nickname: nickname ?? this.nickname,
      isAdmin: isAdmin ?? this.isAdmin,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState()) {
    _checkSavedToken();
  }

  Future<void> _checkSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token != null) {
      try {
        final user = await _api.getMe();
        state = AuthState(
          status: AuthStatus.authenticated,
          token: token,
          userId: user['id'],
          email: user['email'],
          nickname: user['nickname'],
          isAdmin: user['is_admin'] ?? false,
        );
      } catch (_) {
        await prefs.remove('access_token');
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final data = await _api.login(email, password);
      final token = data['access_token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        userId: data['user_id'],
        email: data['email'],
        nickname: data['nickname'],
      );
      // Fetch admin status
      try {
        final user = await _api.getMe();
        state = state.copyWith(isAdmin: user['is_admin'] ?? false);
      } catch (_) {}
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      );
      return false;
    }
  }

  Future<bool> register(String email, String password, {String? nickname}) async {
    try {
      final data = await _api.register(email, password, nickname: nickname);
      final token = data['access_token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        userId: data['user_id'],
        email: data['email'],
        nickname: data['nickname'],
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  String _extractError(dynamic e) {
    if (e is DioException && e.response != null) {
      final data = e.response!.data;
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
    }
    return 'Network error, please try again';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiServiceProvider));
});