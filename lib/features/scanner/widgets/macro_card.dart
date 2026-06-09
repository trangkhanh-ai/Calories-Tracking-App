import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme.dart';

class MacroCard extends StatelessWidget {
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const MacroCard({
    super.key,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          _MacroItem(
            emoji: '🔥',
            value: calories.round().toString(),
            unit: 'kcal',
            label: 'Calories',
            valueColor: AppTheme.secondary,
            flex: 3,
          ),
          _divider(),
          _MacroItem(
            emoji: '🥩',
            value: proteinG.toStringAsFixed(1),
            unit: 'g',
            label: 'Đạm',
            valueColor: const Color(0xFF4ECDC4),
          ),
          _divider(),
          _MacroItem(
            emoji: '🌾',
            value: carbsG.toStringAsFixed(1),
            unit: 'g',
            label: 'Carbs',
            valueColor: const Color(0xFFFFE66D),
          ),
          _divider(),
          _MacroItem(
            emoji: '💧',
            value: fatG.toStringAsFixed(1),
            unit: 'g',
            label: 'Béo',
            valueColor: const Color(0xFFFF6B9D),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 40,
        color: AppTheme.surface,
      );
}

class _MacroItem extends StatelessWidget {
  final String emoji;
  final String value;
  final String unit;
  final String label;
  final Color valueColor;
  final int flex;

  const _MacroItem({
    required this.emoji,
    required this.value,
    required this.unit,
    required this.label,
    required this.valueColor,
    this.flex = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: GoogleFonts.outfit(
                    color: valueColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: GoogleFonts.outfit(
                    color: AppTheme.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: AppTheme.onSurface,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
