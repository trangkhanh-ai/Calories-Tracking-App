import 'package:dio/dio.dart';
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

  String _formatAuthError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401) return 'Tên đăng nhập hoặc mật khẩu không chính xác.';
      if (code == 409) return 'Tên đăng nhập hoặc email đã được đăng ký.';
      if (code == 400) {
        final detail = e.response?.data is Map ? (e.response?.data['detail'] ?? e.response?.data['message']) : null;
        return detail != null ? 'Lỗi dữ liệu: $detail' : 'Thông tin không hợp lệ. Mật khẩu phải từ 8 ký tự trở lên.';
      }
      if (code == 429) return 'Thao tác quá nhanh, vui lòng thử lại sau 1 phút.';
      if (code != null && code >= 500) return 'Hệ thống bận (Mã $code). Vui lòng thử lại sau.';
      return 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.';
    }
    return e.toString();
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
    state = AuthState();
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
