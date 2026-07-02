import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/food_analysis_result.dart';
import '../widgets/macro_card.dart';
import '../../diary/models/food_entry.dart';
import '../../diary/providers/diary_provider.dart';
import '../../../app/theme.dart';
import '../../../shared/utils/constants.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  final FoodAnalysisResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  late List<bool> _selectedItems;
  double _servingScale = 1.0;
  String _selectedMeal = 'Bữa Trưa';
  late List<TextEditingController> _nameControllers;
  late List<bool> _editingName;

  @override
  void initState() {
    super.initState();
    _selectedItems = List.filled(widget.result.items.length, true);
    _nameControllers = widget.result.items
        .map((item) => TextEditingController(text: item.name))
        .toList();
    _editingName = List.filled(widget.result.items.length, false);
  }

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<NutritionInfo> get _selectedNutrition {
    final result = <NutritionInfo>[];
    for (int i = 0; i < widget.result.items.length; i++) {
      if (_selectedItems[i]) {
        result.add(widget.result.items[i].copyWithScale(_servingScale));
      }
    }
    return result;
  }

  double get _totalCalories =>
      _selectedNutrition.fold(0, (s, n) => s + n.calories);
  double get _totalProtein =>
      _selectedNutrition.fold(0, (s, n) => s + n.proteinG);
  double get _totalCarbs =>
      _selectedNutrition.fold(0, (s, n) => s + n.carbsG);
  double get _totalFat =>
      _selectedNutrition.fold(0, (s, n) => s + n.fatG);

  Future<void> _saveEntry() async {
    if (_selectedNutrition.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hãy chọn ít nhất 1 món để lưu', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final names = <String>[];
    for (int i = 0; i < widget.result.items.length; i++) {
      if (_selectedItems[i]) names.add(_nameControllers[i].text);
    }
    final combinedName = names.join(' + ');
    
    final mealMap = {
      'Bữa Sáng': 'Breakfast',
      'Bữa Trưa': 'Lunch',
      'Bữa Tối': 'Dinner',
      'Ăn Vặt': 'Snack'
    };

    final entry = FoodEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: combinedName,
      calories: _totalCalories.round(),
      proteinG: _totalProtein,
      carbsG: _totalCarbs,
      fatG: _totalFat,
      date: DateTime.now(),
      mealType: mealMap[_selectedMeal] ?? 'Snack',
      imagePath: widget.result.imagePath,
    );

    try {
      await ref.read(localStorageProvider).addEntry(entry);
      ref.invalidate(dailyDiaryProvider);
      // ref.invalidate(weeklyStatsProvider); // TODO: implement local stats
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e', style: GoogleFonts.outfit()), backgroundColor: AppTheme.error),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã lưu "$combinedName" vào $_selectedMeal', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMultipleItems = widget.result.items.length > 1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Kết Quả Nhận Diện'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Food image
            _buildFoodImage().animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
            const SizedBox(height: 24),

            // Multiple foods selector
            if (hasMultipleItems) ...[
              _buildMultipleFoodsSelector().animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 20),
            ],

            // Food name (single item)
            if (!hasMultipleItems && widget.result.items.isNotEmpty) ...[
              _buildFoodNameRow(0).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 6),
              Text(
                widget.result.items[0].servingSize,
                style: GoogleFonts.outfit(
                  color: AppTheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 24),
            ],

            // Serving scale slider
            _buildServingSlider().animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 24),

            // Macro card
            MacroCard(
              calories: _totalCalories,
              proteinG: _totalProtein,
              carbsG: _totalCarbs,
              fatG: _totalFat,
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 24),

            // Meal type selector
            _buildMealTypeSelector().animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                  shadowColor: AppTheme.primary.withAlpha(100),
                ),
                onPressed: _saveEntry,
                icon: const Icon(Icons.save_alt_rounded, color: Colors.white),
                label: Text(
                  'Lưu vào nhật ký',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ).animate().fadeIn(delay: 500.ms).scale(),
            const SizedBox(height: 16),

            // Secondary actions
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.camera_alt_outlined, color: AppTheme.onSurface),
                label: Text('Quét lại', style: GoogleFonts.outfit(color: AppTheme.onBackground, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.surfaceVariant, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.surface,
                ),
              ),
            ).animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodImage() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.onBackground.withAlpha(15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: kIsWeb
              ? Image.network(
                  widget.result.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildImageError(),
                )
              : Image.file(
                  File(widget.result.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildImageError(),
                ),
        ),
      ),
    );
  }

  Widget _buildImageError() {
    return Container(
      color: AppTheme.surfaceVariant,
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, color: AppTheme.onSurface, size: 48),
      ),
    );
  }

  Widget _buildFoodNameRow(int index) {
    return Row(
      children: [
        Expanded(
          child: _editingName[index]
              ? TextField(
                  controller: _nameControllers[index],
                  autofocus: true,
                  style: GoogleFonts.outfit(
                    color: AppTheme.onBackground,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    border: UnderlineInputBorder(),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.primary),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.primary, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => setState(() => _editingName[index] = false),
                )
              : Text(
                  _nameControllers[index].text,
                  style: GoogleFonts.outfit(
                    color: AppTheme.onBackground,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        IconButton(
          onPressed: () => setState(() => _editingName[index] = !_editingName[index]),
          icon: Icon(
            _editingName[index] ? Icons.check_rounded : Icons.edit_outlined,
            color: AppTheme.primary,
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildMultipleFoodsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🍽️ Các món được nhận diện',
          style: GoogleFonts.outfit(
            color: AppTheme.onBackground,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(widget.result.items.length, (i) {
          final item = widget.result.items[i];
          final isSelected = _selectedItems[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primary.withAlpha(20) : AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppTheme.primary.withAlpha(80) : Colors.transparent,
                width: 2,
              ),
              boxShadow: [
                if (!isSelected)
                  BoxShadow(
                    color: AppTheme.onBackground.withAlpha(5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: CheckboxListTile(
              value: isSelected,
              onChanged: (v) => setState(() => _selectedItems[i] = v ?? false),
              activeColor: AppTheme.primary,
              title: _buildFoodNameRow(i),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  '${item.servingSize} • ${(item.calories * _servingScale).round()} kcal',
                  style: GoogleFonts.outfit(color: AppTheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildServingSlider() {
    final scaleLabel = AppConstants.servingScaleLabels[
        AppConstants.servingScales.indexOf(_servingScale)];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.onBackground.withAlpha(8),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📏 Khẩu phần',
                style: GoogleFonts.outfit(
                  color: AppTheme.onBackground,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  scaleLabel,
                  style: GoogleFonts.outfit(
                    color: AppTheme.primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: AppConstants.servingScales.indexOf(_servingScale).toDouble(),
            min: 0,
            max: (AppConstants.servingScales.length - 1).toDouble(),
            divisions: AppConstants.servingScales.length - 1,
            activeColor: AppTheme.primary,
            inactiveColor: AppTheme.surfaceVariant,
            onChanged: (v) => setState(() {
              _servingScale = AppConstants.servingScales[v.round()];
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: AppConstants.servingScaleLabels
                  .map((l) => Text(l, style: GoogleFonts.outfit(color: AppTheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lưu vào bữa:',
          style: GoogleFonts.outfit(
            color: AppTheme.onBackground,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            AppConstants.mealTypes.length,
            (i) {
              final meal = AppConstants.mealTypes[i];
              final emoji = AppConstants.mealTypeEmojis[i];
              final isSelected = _selectedMeal == meal;
              return GestureDetector(
                onTap: () => setState(() => _selectedMeal = meal),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      if (!isSelected)
                        BoxShadow(
                          color: AppTheme.onBackground.withAlpha(8),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      if (isSelected)
                        BoxShadow(
                          color: AppTheme.primary.withAlpha(80),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Text(
                    '$emoji $meal',
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.white : AppTheme.onBackground,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
