import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../services/diary_api_service.dart';
import '../models/diary_dto.dart';
import '../providers/diary_provider.dart';

final weeklyStatsProvider = FutureProvider<List<DailyStatDto>>((ref) async {
  final api = ref.watch(diaryApiServiceProvider);
  final end = DateTime.now();
  final start = end.subtract(const Duration(days: 6));
  return api.getStats(start, end);
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(weeklyStatsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Thống kê', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppTheme.onBackground)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.onBackground),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (stats) {
          if (stats.isEmpty) {
            return const Center(child: Text('Chưa có dữ liệu thống kê'));
          }

          double maxCalories = 0;
          for (var stat in stats) {
            if (stat.caloriesConsumed > maxCalories) maxCalories = stat.caloriesConsumed;
          }
          if (maxCalories < 2000) maxCalories = 2000;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lượng calo 7 ngày qua',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.onBackground),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxCalories * 1.2,
                      barTouchData: BarTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              if (value.toInt() >= stats.length) return const SizedBox();
                              final date = stats[value.toInt()].date;
                              final isToday = date.day == DateTime.now().day && date.month == DateTime.now().month;
                              final text = isToday ? 'HN' : DateFormat('E', 'vi').format(date);
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(text, style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.onSurface)),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: stats.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.caloriesConsumed,
                              color: AppTheme.primary,
                              width: 16,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
