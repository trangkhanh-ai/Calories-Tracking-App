import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../diary/providers/diary_provider.dart';
import '../services/profile_api_service.dart';

/// Màn hình thiết lập mục tiêu calo — chạy sau khi đăng ký (hoặc từ Profile).
/// Người dùng nhập chỉ số cơ thể + mức vận động; backend tính TDEE
/// (sedentary = hệ số 1.2) và trả về calo khuyến nghị.
class GoalSetupScreen extends ConsumerStatefulWidget {
  const GoalSetupScreen({super.key});

  @override
  ConsumerState<GoalSetupScreen> createState() => _GoalSetupScreenState();
}

class _GoalSetupScreenState extends ConsumerState<GoalSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  String _gender = 'male';
  String _activityLevel = 'sedentary';
  String _goal = 'maintain';
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  static const _activityOptions = [
    (value: 'sedentary', label: 'Không tập thể dục', subtitle: 'Ít vận động, làm việc văn phòng', icon: Icons.weekend),
    (value: 'light', label: 'Tập nhẹ', subtitle: 'Tập 1-3 buổi/tuần', icon: Icons.directions_walk),
    (value: 'moderate', label: 'Tập vừa', subtitle: 'Tập 3-5 buổi/tuần', icon: Icons.directions_run),
    (value: 'active', label: 'Tập nhiều', subtitle: 'Tập 6-7 buổi/tuần', icon: Icons.fitness_center),
  ];

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _calculateAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final profile = await profileApiService.getProfile();
      final displayName =
          (profile?['displayName'] as String?) ?? (profile?['username'] as String?) ?? 'User';

      // 1. Lưu chỉ số cơ thể + mức vận động lên backend
      await profileApiService.updateProfile(
        displayName: displayName,
        height: double.parse(_heightController.text),
        weight: double.parse(_weightController.text),
        age: int.parse(_ageController.text),
        gender: _gender,
        activityLevel: _activityLevel,
      );

      // 2. Backend tính BMI/BMR/TDEE/calo khuyến nghị
      final goalData = await profileApiService.getCalorieGoal(goal: _goal);
      if (goalData == null) {
        throw Exception('Không tính được mục tiêu calo. Kiểm tra kết nối backend.');
      }

      final recommended = (goalData['recommendedCalories'] as num).round();

      // 3. Chốt mục tiêu: lưu backend + local để vòng tròn Home cập nhật
      await profileApiService.updateProfile(
        displayName: displayName,
        height: double.parse(_heightController.text),
        weight: double.parse(_weightController.text),
        age: int.parse(_ageController.text),
        gender: _gender,
        targetCalories: recommended,
      );
      await ref.read(localStorageProvider).setDailyGoal(recommended);
      ref.read(dailyGoalProvider.notifier).updateGoal(recommended);
      ref.invalidate(dailyDiaryProvider);

      if (mounted) setState(() => _result = goalData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Thiết lập mục tiêu calo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cho chúng tôi biết về bạn để tính lượng calo phù hợp mỗi ngày',
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),

                // ─── Chỉ số cơ thể ───────────────────────────────
                Row(
                  children: [
                    Expanded(child: _buildNumberField(_ageController, 'Tuổi', suffix: '')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _gender,
                        decoration: _inputDecoration('Giới tính'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Nam')),
                          DropdownMenuItem(value: 'female', child: Text('Nữ')),
                        ],
                        onChanged: (v) => setState(() => _gender = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildNumberField(_heightController, 'Chiều cao', suffix: 'cm')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumberField(_weightController, 'Cân nặng', suffix: 'kg')),
                  ],
                ),
                const SizedBox(height: 24),

                // ─── Mức vận động ────────────────────────────────
                const Text(
                  'Bạn tập thể dục thế nào?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _activityLevel,
                  onChanged: (v) => setState(() => _activityLevel = v!),
                  child: Column(
                    children: _activityOptions
                        .map(
                          (option) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _activityLevel == option.value
                                    ? Theme.of(context).colorScheme.primary
                                    : const Color(0xFFE2E8F0),
                                width: _activityLevel == option.value ? 2 : 1,
                              ),
                            ),
                            child: RadioListTile<String>(
                              value: option.value,
                              title: Text(option.label,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(option.subtitle, style: const TextStyle(fontSize: 12)),
                              secondary: Icon(option.icon),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // ─── Mục tiêu cân nặng ───────────────────────────
                DropdownButtonFormField<String>(
                  initialValue: _goal,
                  decoration: _inputDecoration('Mục tiêu của bạn'),
                  items: const [
                    DropdownMenuItem(value: 'lose', child: Text('Giảm cân (-500 kcal/ngày)')),
                    DropdownMenuItem(value: 'maintain', child: Text('Giữ cân')),
                    DropdownMenuItem(value: 'gain', child: Text('Tăng cân (+500 kcal/ngày)')),
                  ],
                  onChanged: (v) => setState(() => _goal = v!),
                ),
                const SizedBox(height: 24),

                // ─── Kết quả ─────────────────────────────────────
                if (_result != null) _buildResultCard(),

                FilledButton(
                  onPressed: _isLoading ? null : _calculateAndSave,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Tính toán & Áp dụng'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: Text(_result != null ? 'Bắt đầu theo dõi 🎉' : 'Bỏ qua, thiết lập sau'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _result!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF34D399)),
      ),
      child: Column(
        children: [
          _resultRow('BMI', '${result['bmi']}'),
          _resultRow('BMR (trao đổi chất cơ bản)', '${(result['bmr'] as num).round()} kcal'),
          _resultRow('TDEE (tiêu hao mỗi ngày)', '${(result['tdee'] as num).round()} kcal'),
          const Divider(),
          _resultRow(
            'Mục tiêu calo mỗi ngày',
            '${result['recommendedCalories']} kcal',
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF475569))),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 18 : 14,
              color: highlight ? const Color(0xFF059669) : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _buildNumberField(TextEditingController controller, String label, {String? suffix}) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDecoration(label, suffix: suffix),
      validator: (v) {
        final parsed = double.tryParse(v ?? '');
        if (parsed == null || parsed <= 0) return 'Không hợp lệ';
        return null;
      },
    );
  }
}
