import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../diary/providers/diary_provider.dart';
import '../../diary/models/diary_dto.dart';
import '../../../app/theme.dart';
import '../../../shared/utils/constants.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diaryAsync = ref.watch(dailyDiaryProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: diaryAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (dailyData) {
          final todayCalories = dailyData.totalCaloriesConsumed.toInt();
          final dailyGoal = dailyData.targetCalories.toInt();
          final remaining = dailyGoal - todayCalories;
          final percentage = dailyGoal == 0 ? 0.0 : (todayCalories / dailyGoal).clamp(0.0, 1.0);
          final calorieColor = percentage < 0.75
              ? AppTheme.calorieGood
              : percentage < 1.0
                  ? AppTheme.calorieMid
                  : AppTheme.calorieOver;
                  
          final allEntries = [
            ...dailyData.breakfast,
            ...dailyData.lunch,
            ...dailyData.dinner,
            ...dailyData.snacks,
          ];

          return CustomScrollView(
            slivers: [
              // ─── App Bar ──────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 0,
                pinned: true,
                backgroundColor: AppTheme.background.withAlpha(240),
                title: Row(
                  children: [
                    Text(
                      '🍃 CalTrack',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('EEE, d MMM').format(dailyData.date),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.onBackground.withAlpha(10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.person, color: AppTheme.primary),
                        onPressed: () => context.pushNamed('profile'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.bar_chart, color: AppTheme.primary),
                      onPressed: () => context.pushNamed('stats'),
                    ),
                  ],
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ─── Calorie Ring Card ──────────────────────────────
                    _CalorieRingCard(
                      todayCalories: todayCalories,
                      dailyGoal: dailyGoal,
                      remaining: remaining,
                      percentage: percentage,
                      calorieColor: calorieColor,
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 20),

                    // ─── Meal Breakdown ─────────────────────────────────
                    _MealBreakdownCard(dailyData: dailyData)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 24),

                    // ─── Today's log ────────────────────────────────────
                    Text(
                      "Hôm nay",
                      style: GoogleFonts.outfit(
                        color: AppTheme.onBackground,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                    const SizedBox(height: 12),
                    if (allEntries.isEmpty)
                      _EmptyState().animate().fadeIn(duration: 400.ms, delay: 300.ms)
                    else
                      ...allEntries.asMap().entries.map((e) {
                        final index = e.key;
                        final entry = e.value;
                        return _FoodEntryTile(entry: entry)
                            .animate()
                            .fadeIn(duration: 400.ms, delay: (300 + index * 50).ms)
                            .slideX(begin: 0.1, end: 0);
                      }),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _ScanFAB().animate().scale(delay: 500.ms, duration: 400.ms),
    );
  }
}

class _CalorieRingCard extends StatelessWidget {
  final int todayCalories;
  final int dailyGoal;
  final int remaining;
  final double percentage;
  final Color calorieColor;

  const _CalorieRingCard({
    required this.todayCalories,
    required this.dailyGoal,
    required this.remaining,
    required this.percentage,
    required this.calorieColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.onBackground.withAlpha(12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          // Ring
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: percentage,
                    strokeWidth: 12,
                    backgroundColor: AppTheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(calorieColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$todayCalories',
                      style: GoogleFonts.outfit(
                        color: AppTheme.onBackground,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'kcal',
                      style: GoogleFonts.outfit(
                        color: AppTheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatRow(
                  label: 'Mục tiêu',
                  value: '$dailyGoal kcal',
                  color: AppTheme.onSurface,
                ),
                const SizedBox(height: 12),
                _StatRow(
                  label: remaining >= 0 ? 'Còn lại' : 'Vượt quá',
                  value: '${remaining.abs()} kcal',
                  color: calorieColor,
                  bold: true,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 8,
                    backgroundColor: AppTheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(calorieColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(percentage * 100).toStringAsFixed(0)}% mục tiêu ngày',
                  style: GoogleFonts.outfit(
                    color: AppTheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(color: AppTheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: color,
            fontSize: 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MealBreakdownCard extends StatelessWidget {
  final DailyDiaryDto dailyData;

  const _MealBreakdownCard({required this.dailyData});

  @override
  Widget build(BuildContext context) {
    final bfCal = dailyData.breakfast.fold<double>(0, (sum, e) => sum + e.calories);
    final lCal = dailyData.lunch.fold<double>(0, (sum, e) => sum + e.calories);
    final dCal = dailyData.dinner.fold<double>(0, (sum, e) => sum + e.calories);
    final sCal = dailyData.snacks.fold<double>(0, (sum, e) => sum + e.calories);

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
          Text(
            'Phân bổ bữa ăn',
            style: GoogleFonts.outfit(
              color: AppTheme.onBackground,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _MealSlot(emoji: '🍳', label: 'Sáng', calories: bfCal.toInt())),
              Expanded(child: _MealSlot(emoji: '🍱', label: 'Trưa', calories: lCal.toInt())),
              Expanded(child: _MealSlot(emoji: '🍲', label: 'Tối', calories: dCal.toInt())),
              Expanded(child: _MealSlot(emoji: '🍎', label: 'Ăn Vặt', calories: sCal.toInt())),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealSlot extends StatelessWidget {
  final String emoji;
  final String label;
  final int calories;

  const _MealSlot({
    required this.emoji,
    required this.label,
    required this.calories,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: AppTheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$calories',
          style: GoogleFonts.outfit(
            color: calories > 0 ? AppTheme.primaryDark : AppTheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'kcal',
          style: GoogleFonts.outfit(
            color: AppTheme.onSurface,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _FoodEntryTile extends StatelessWidget {
  final MealItemDto entry;

  const _FoodEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.onBackground.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                _mealEmoji(entry.mealType),
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.foodName,
                  style: GoogleFonts.outfit(
                    color: AppTheme.onBackground,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.mealType,
                  style: GoogleFonts.outfit(
                    color: AppTheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${entry.calories.toInt()} kcal',
            style: GoogleFonts.outfit(
              color: AppTheme.primaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _mealEmoji(String mealType) {
    if (mealType == 'Breakfast') return '🍳';
    if (mealType == 'Lunch') return '🍱';
    if (mealType == 'Dinner') return '🍲';
    return '🍎';
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Text('🥗', style: TextStyle(fontSize: 48)),
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có gì hôm nay',
            style: GoogleFonts.outfit(
              color: AppTheme.onBackground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bấm nút camera để quét món ăn đầu tiên của bạn!',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: AppTheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => context.pushNamed('scanner'),
      backgroundColor: AppTheme.primary,
      icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
      label: Text(
        'Quét Món Ăn',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}
