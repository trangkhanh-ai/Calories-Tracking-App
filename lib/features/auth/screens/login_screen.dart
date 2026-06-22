import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  bool _rememberMe = false;
  Map<String, String>? _savedCredentials;
  bool _showSuggestion = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();

    // Lắng nghe khi ô username được focus → hiện popup gợi ý
    _usernameFocusNode.addListener(() {
      if (_usernameFocusNode.hasFocus && _savedCredentials != null) {
        setState(() => _showSuggestion = true);
      }
    });
  }

  @override
  void dispose() {
    _usernameFocusNode.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final saved = await ref.read(authProvider.notifier).loadSavedCredentials();
    if (saved != null && mounted) {
      setState(() {
        _savedCredentials = saved;
        _rememberMe = true;
      });
    }
  }

  /// Khi người dùng chọn tài khoản từ popup gợi ý
  void _applySavedCredentials() {
    if (_savedCredentials == null) return;
    setState(() {
      _usernameController.text = _savedCredentials!['username']!;
      _passwordController.text = _savedCredentials!['password']!;
      _showSuggestion = false;
      _rememberMe = true;
    });
    _usernameFocusNode.unfocus();
  }

  void _login() async {
    final username = _usernameController.text;
    final password = _passwordController.text;

    final success = await ref.read(authProvider.notifier).login(
          username,
          password,
        );
    if (success) {
      // Lưu hoặc xóa thông tin đăng nhập tùy theo checkbox
      if (_rememberMe) {
        await ref.read(authProvider.notifier).saveCredentials(username, password);
      } else {
        await ref.read(authProvider.notifier).clearSavedCredentials();
      }
      if (mounted) context.go('/');
    } else {
      final error = ref.read(authProvider).error;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Login failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: GestureDetector(
        // Bấm ra ngoài → ẩn popup gợi ý
        onTap: () => setState(() => _showSuggestion = false),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Đăng Nhập',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ─── Ô Username + Popup gợi ý ─────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _usernameController,
                        focusNode: _usernameFocusNode,
                        onTap: () {
                          if (_savedCredentials != null) {
                            setState(() => _showSuggestion = true);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Tên đăng nhập',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: const Color(0xFFF8F9FA),
                        ),
                      ),

                      // ★ Popup gợi ý tài khoản đã lưu ★
                      if (_showSuggestion && _savedCredentials != null)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _applySavedCredentials,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2ECC71).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.person_rounded, color: Color(0xFF2ECC71), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _savedCredentials!['username']!,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2C3E50),
                                            ),
                                          ),
                                          const Text(
                                            'Tài khoản đã lưu • Bấm để điền nhanh',
                                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FA),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ─── Checkbox Nhớ tài khoản ─────────────────────────
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (value) => setState(() => _rememberMe = value ?? false),
                          activeColor: const Color(0xFF2ECC71),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        child: const Text(
                          'Nhớ tài khoản',
                          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF2ECC71),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                        : const Text('ĐĂNG NHẬP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Chưa có tài khoản? Đăng ký ngay'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
