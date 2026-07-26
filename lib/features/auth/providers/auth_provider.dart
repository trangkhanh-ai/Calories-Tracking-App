import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/network_failure.dart';
import '../services/auth_api_service.dart';
import '../utils/jwt_validator.dart';

final authServiceProvider = Provider((ref) => AuthApiService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  // Riverpod disposes the notifier itself when this provider is disposed, and
  // AuthNotifier.dispose deregisters its unauthorized listener there. Adding an
  // explicit ref.onDispose(notifier.dispose) here would dispose it twice.
  return AuthNotifier(ref.watch(authServiceProvider));
});

class AuthState {
  final bool isLoading;
  final String? token;
  final String? error;

  const AuthState({this.isLoading = false, this.token, this.error});

  bool get isAuthenticated => token != null;

  /// Note the explicit [clearToken] flag: a nullable `token` parameter alone
  /// cannot distinguish "leave the token alone" from "clear it", which is why
  /// logout previously failed to null it out.
  AuthState copyWith({
    bool? isLoading,
    String? token,
    String? error,
    bool clearError = false,
    bool clearToken = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      token: clearToken ? null : (token ?? this.token),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApiService _authService;
  final JwtValidator jwtValidator;
  late final VoidCallback _removeUnauthorizedListener;

  AuthNotifier(
    this._authService, {
    this.jwtValidator = const JwtValidator(),
    UnauthorizedCoordinator? coordinator,
  }) : super(const AuthState()) {
    final target = coordinator ?? ApiClient.unauthorizedCoordinator;
    _removeUnauthorizedListener = target.addListener(_handleUnauthorized);
    restoreSession();
  }

  /// Invoked by the coordinator, which guarantees a single run even when
  /// several 401s arrive together.
  Future<void> _handleUnauthorized() async {
    if (!mounted) return;
    await logout();
  }

  @override
  void dispose() {
    _removeUnauthorizedListener();
    super.dispose();
  }

  /// Restores a stored session at startup, discarding an expired or malformed
  /// token instead of letting it drive a 401 redirect loop.
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null) {
      return;
    }

    if (!jwtValidator.isValid(token)) {
      await prefs.remove('jwt_token');
      if (mounted) {
        state = state.copyWith(clearToken: true);
      }
      return;
    }

    if (mounted) {
      state = state.copyWith(token: token);
    }
  }

  String _formatAuthError(Object error) {
    if (error is DioException) {
      final failure = NetworkFailure.fromDioException(error);

      // Login/register need domain-specific wording for the credential cases;
      // everything else uses the shared failure model.
      return switch (failure) {
        UnauthorizedFailure() => 'Tên đăng nhập hoặc mật khẩu không chính xác.',
        ConflictFailure() => 'Tên đăng nhập hoặc email đã được đăng ký.',
        _ => failure.message,
      };
    }

    // Never surface a raw toString() to the user.
    return 'Đã xảy ra lỗi không xác định. Vui lòng thử lại.';
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.login(username, password);
      final token = data['token'] as String;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', token);
      
      state = state.copyWith(isLoading: false, token: token);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _formatAuthError(e));
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.register(
        username: username,
        email: email,
        password: password,
        displayName: displayName,
      );
      final token = data['token'] as String;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', token);

      state = state.copyWith(isLoading: false, token: token);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _formatAuthError(e));
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');

    // A fresh AuthState guarantees token == null and isAuthenticated == false.
    if (mounted) {
      state = const AuthState();
    }
  }

  // ─── Remember Me ──────────────────────────────────────────────────────────
  // Chỉ lưu username. KHÔNG lưu mật khẩu dưới bất kỳ hình thức nào —
  // SharedPreferences là plaintext, phiên đăng nhập đã được giữ bằng JWT.

  /// Lưu tên đăng nhập vào bộ nhớ cục bộ
  Future<void> saveRememberedUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_username', username);
  }

  /// Đọc tên đăng nhập đã lưu (trả về null nếu chưa lưu)
  Future<String?> loadRememberedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    // Dọn mật khẩu plaintext mà các bản cũ từng lưu
    await prefs.remove('saved_password');
    return prefs.getString('saved_username');
  }

  /// Xóa tên đăng nhập đã lưu
  Future<void> clearRememberedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
  }
}
