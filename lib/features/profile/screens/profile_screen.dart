import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/theme.dart';
import '../../diary/providers/diary_provider.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../utils/calculator_utils.dart';
import '../services/profile_api_service.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  int _age = 25;
  double _weight = 65.0;
  double _heightCm = 170.0;
  Gender _gender = Gender.male;
  ActivityLevel _activityLevel = ActivityLevel.moderatelyActive;
  WeightGoal _weightGoal = WeightGoal.maintain;

  double? _bmi;
  double? _tdee;
  int? _recommendedCalories;
  bool _isLoading = false;

  String _username = 'Người Dùng';
  String? _avatarUrl;
  String? _selectedDefaultAvatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedActivity = prefs.getString('activityLevel');
      final savedGoal = prefs.getString('weightGoal');
      
      final profile = await ref.read(profileProvider.future);
      if (profile != null && mounted) {
        setState(() {
          _username = profile['username'] ?? _username;
          _avatarUrl = profile['avatarUrl'];
          _age = profile['age'] ?? _age;
          _weight = (profile['weight'] as num?)?.toDouble() ?? _weight;
          _heightCm = (profile['height'] as num?)?.toDouble() ?? _heightCm;
          _gender = (profile['gender'] == 'Female') ? Gender.female : Gender.male;
          
          if (savedActivity != null) {
            _activityLevel = ActivityLevel.values.firstWhere((e) => e.toString() == savedActivity, orElse: () => _activityLevel);
          }
          if (savedGoal != null) {
            _weightGoal = WeightGoal.values.firstWhere((e) => e.toString() == savedGoal, orElse: () => _weightGoal);
          }
        });
      }
    } catch (e) {
      print('Load Profile Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDefaultAvatar() async {
    final avatars = await profileApiService.getDefaultAvatars();
    if (avatars.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tải được danh sách ảnh mặc định')));
      }
      return;
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text('Chọn ảnh đại diện', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: avatars.length,
                      itemBuilder: (context, index) {
                        final avatarUrl = avatars[index];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _avatarUrl = avatarUrl;
                              _selectedDefaultAvatarUrl = avatarUrl;
                            });
                            Navigator.pop(ctx);
                          },
                          child: CircleAvatar(
                            backgroundImage: NetworkImage(avatarUrl),
                            backgroundColor: AppTheme.surfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      );
    }
  }

  void _calculate() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final bmr = CalculatorUtils.calculateBMR(
        gender: _gender,
        weight: _weight,
        heightCm: _heightCm,
        age: _age,
      );
      setState(() {
        _bmi = CalculatorUtils.calculateBMI(weight: _weight, heightCm: _heightCm);
        _tdee = CalculatorUtils.calculateTDEE(bmr: bmr, activityLevel: _activityLevel);
        _recommendedCalories = CalculatorUtils.calculateRecommendedCalories(
          tdee: _tdee!,
          goal: _weightGoal,
        );
      });
    }
  }

  Future<void> _applyGoal() async {
    if (_recommendedCalories != null) {
      setState(() => _isLoading = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('activityLevel', _activityLevel.toString());
        await prefs.setString('weightGoal', _weightGoal.toString());

        final result = await profileApiService.updateProfile(
          displayName: _username,
          height: _heightCm,
          weight: _weight,
          age: _age,
          gender: _gender == Gender.male ? 'Male' : 'Female',
          targetCalories: _recommendedCalories!,
          defaultAvatarUrl: _selectedDefaultAvatarUrl,
        );

        if (result != null && mounted) {
          setState(() {
             _avatarUrl = result['avatarUrl'];
             _selectedDefaultAvatarUrl = null;
          });
          ref.read(dailyGoalProvider.notifier).updateGoal(_recommendedCalories!);
          ref.read(profileProvider.notifier).refresh();
          await ref.refresh(dailyDiaryProvider.future);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã đồng bộ lên Server & cập nhật mục tiêu: $_recommendedCalories kcal!',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
          }
        } else if (mounted) {
          throw Exception('Không nhận được phản hồi từ Server');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi đồng bộ Server: $e', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _confirmLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Đăng xuất', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: Colors.redAccent)),
          content: Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản này không?', style: GoogleFonts.outfit(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Hủy', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Đăng xuất', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withAlpha(240),
        title: Text(
          'Hồ Sơ & Tính Toán',
          style: GoogleFonts.outfit(
            color: AppTheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.primary),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Đăng xuất',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickDefaultAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: AppTheme.surfaceVariant,
                        backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                        child: _avatarUrl == null
                            ? const Icon(Icons.person, size: 50, color: Colors.grey)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 24),
              _buildSectionTitle('Thông tin cá nhân')
                  .animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

              TextFormField(
                key: ValueKey(_username),
                initialValue: _username,
                readOnly: true,
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.grey),
                decoration: InputDecoration(
                  labelText: 'Tên đăng nhập',
                  filled: true,
                  fillColor: AppTheme.surfaceVariant.withAlpha(100),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<Gender>(
                      label: 'Giới tính',
                      value: _gender,
                      items: const [
                        DropdownMenuItem(value: Gender.male, child: Text('Nam')),
                        DropdownMenuItem(value: Gender.female, child: Text('Nữ')),
                      ],
                      onChanged: (v) => setState(() => _gender = v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildNumberInput(
                      label: 'Tuổi',
                      initialValue: _age.toString(),
                      onSaved: (v) => _age = int.tryParse(v!) ?? _age,
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      label: 'Chiều cao (cm)',
                      initialValue: _heightCm.toString(),
                      onSaved: (v) => _heightCm = double.tryParse(v!) ?? _heightCm,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildNumberInput(
                      label: 'Cân nặng (kg)',
                      initialValue: _weight.toString(),
                      onSaved: (v) => _weight = double.tryParse(v!) ?? _weight,
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 32),
              _buildSectionTitle('Lối sống & Mục tiêu')
                  .animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
              
              _buildDropdown<ActivityLevel>(
                label: 'Mức độ vận động',
                value: _activityLevel,
                items: const [
                  DropdownMenuItem(value: ActivityLevel.sedentary, child: Text('Ít vận động (Việc văn phòng)')),
                  DropdownMenuItem(value: ActivityLevel.lightlyActive, child: Text('Vận động nhẹ (Tập 1-3 ngày/tuần)')),
                  DropdownMenuItem(value: ActivityLevel.moderatelyActive, child: Text('Vận động vừa (Tập 3-5 ngày/tuần)')),
                  DropdownMenuItem(value: ActivityLevel.veryActive, child: Text('Vận động nhiều (Tập 6-7 ngày/tuần)')),
                  DropdownMenuItem(value: ActivityLevel.extraActive, child: Text('Rất năng động (Lao động chân tay/VĐV)')),
                ],
                onChanged: (v) => setState(() => _activityLevel = v!),
              ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 16),
              _buildDropdown<WeightGoal>(
                label: 'Mục tiêu',
                value: _weightGoal,
                items: const [
                  DropdownMenuItem(value: WeightGoal.lose, child: Text('Giảm cân')),
                  DropdownMenuItem(value: WeightGoal.maintain, child: Text('Giữ cân')),
                  DropdownMenuItem(value: WeightGoal.gain, child: Text('Tăng cân')),
                ],
                onChanged: (v) => setState(() => _weightGoal = v!),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
              
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                  shadowColor: AppTheme.primary.withAlpha(100),
                ),
                onPressed: _calculate,
                child: Text(
                  'Tính Toán',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ).animate().scale(delay: 400.ms, duration: 300.ms),
              
              if (_bmi != null && _tdee != null && _recommendedCalories != null) ...[
                const SizedBox(height: 40),
                _buildResultsCard().animate().fadeIn().slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          color: AppTheme.onBackground,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildNumberInput({required String label, required String initialValue, required void Function(String?) onSaved}) {
    return TextFormField(
      key: ValueKey(initialValue),
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppTheme.onBackground),
      decoration: InputDecoration(
        labelText: label,
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Bắt buộc' : null,
      onSaved: onSaved,
    );
  }

  Widget _buildDropdown<T>({required String label, required T value, required List<DropdownMenuItem<T>> items, required void Function(T?) onChanged}) {
    return DropdownButtonFormField<T>(
      value: value,
      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppTheme.onBackground, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildResultsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.onBackground.withAlpha(10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Kết Quả Của Bạn', 
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.onBackground)
          ),
          const SizedBox(height: 24),
          _buildResultRow('Chỉ số BMI', _bmi!.toStringAsFixed(1), _getBMIStatus(_bmi!)),
          const SizedBox(height: 16),
          _buildResultRow('TDEE (Năng lượng tiêu hao)', '${_tdee!.round()} kcal', 'mỗi ngày'),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Text(
                  'Mục tiêu Calo đề xuất',
                  style: GoogleFonts.outfit(color: AppTheme.onSurface, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_recommendedCalories!} kcal',
                  style: GoogleFonts.outfit(
                    color: AppTheme.primaryDark,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 4,
                shadowColor: AppTheme.secondary.withAlpha(100),
              ),
              onPressed: _isLoading ? null : _applyGoal,
              icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle, color: Colors.white),
              label: Text(
                _isLoading ? 'Đang đồng bộ...' : 'Áp dụng Mục tiêu này',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, String subValue) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: GoogleFonts.outfit(color: AppTheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: GoogleFonts.outfit(color: AppTheme.onBackground, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(subValue, style: GoogleFonts.outfit(color: AppTheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  String _getBMIStatus(double bmi) {
    if (bmi < 18.5) return 'Thiếu cân';
    if (bmi < 24.9) return 'Bình thường';
    if (bmi < 29.9) return 'Thừa cân';
    return 'Béo phì';
  }
}
