import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_api_service.dart';

final authServiceProvider = Provider((ref) => AuthApiService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});

class AuthState {
  final bool isLoading;
  final String? token;
  final String? error;

  AuthState({this.isLoading = false, this.token, this.error});

  bool get isAuthenticated => token != null;

  AuthState copyWith({bool? isLoading, String? token, String? error, bool clearError = false}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApiService _authService;

  AuthNotifier(this._authService) : super(AuthState()) {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null) {
      state = state.copyWith(token: token);
    }
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
      state = state.copyWith(isLoading: false, error: e.toString());
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
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    state = AuthState();
  }

  // ─── Remember Me ──────────────────────────────────────────────────────────

  /// Lưu tên đăng nhập + mật khẩu vào bộ nhớ cục bộ
  Future<void> saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_username', username);
    await prefs.setString('saved_password', password);
  }

  /// Đọc tên đăng nhập + mật khẩu đã lưu (trả về null nếu chưa lưu)
  Future<Map<String, String>?> loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('saved_username');
    final password = prefs.getString('saved_password');
    if (username != null && password != null) {
      return {'username': username, 'password': password};
    }
    return null;
  }

  /// Xóa dữ liệu đăng nhập đã lưu
  Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
  }
}
