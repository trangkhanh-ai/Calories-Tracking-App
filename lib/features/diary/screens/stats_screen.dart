import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../providers/diary_provider.dart';

// This screen previously declared its own `weeklyStatsProvider` that read only
// from local storage. It shadowed the shared provider in diary_provider.dart,
// so the stats chart never reflected the server at all. It now consumes the
// shared, server-first provider.

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
        // Never render a raw exception to the user.
        error: (_, _) => _StatsMessage(
          message: 'Không tải được thống kê. Vui lòng thử lại.',
          onRetry: () => ref.invalidate(weeklyStatsProvider),
        ),
        data: (statsState) {
          final stats = statsState.displayData;

          if (stats == null || stats.isEmpty) {
            return _StatsMessage(
              message: statsState.message ?? 'Chưa có dữ liệu thống kê',
              onRetry: statsState.canRetry
                  ? () => ref.invalidate(weeklyStatsProvider)
                  : null,
            );
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

/// Centred message with an optional retry, used for both the empty and the
/// degraded states so neither ever shows a raw exception.
class _StatsMessage extends StatelessWidget {
  const _StatsMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppTheme.onBackground, fontSize: 16),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text('Thử lại', style: GoogleFonts.outfit()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
