import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme.dart';
import '../models/meal_suggestion.dart';

class CoachSuggestionCard extends StatelessWidget {
  const CoachSuggestionCard({
    super.key,
    required this.state,
    required this.onOpenSearch,
  });

  final AsyncValue<List<MealSuggestion>> state;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return state.when(
      loading: _buildLoading,
      error: (_, _) => const SizedBox.shrink(),
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return _buildContent(suggestions);
      },
    );
  }

  Widget _buildLoading() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _decoration(),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Đang tính gợi ý...'),
        ],
      ),
    );
  }

  Widget _buildContent(List<MealSuggestion> suggestions) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withAlpha(35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hôm nay nên ăn gì?',
                  style: GoogleFonts.outfit(
                    color: AppTheme.onBackground,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                suggestions.first.mealType,
                style: GoogleFonts.outfit(
                  color: AppTheme.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Gợi ý theo lượng calo còn lại trong ngày',
            style: GoogleFonts.outfit(
              color: AppTheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ...suggestions.map(_SuggestionTile.new),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenSearch,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Mở tìm kiếm'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryDark,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppTheme.secondary.withAlpha(75)),
      boxShadow: [
        BoxShadow(
          color: AppTheme.secondary.withAlpha(20),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile(this.suggestion);

  final MealSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.restaurant_rounded,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.food.name,
                  style: GoogleFonts.outfit(
                    color: AppTheme.onBackground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  suggestion.quantityLabel,
                  style: GoogleFonts.outfit(
                    color: AppTheme.onSurface,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            suggestion.caloriesLabel,
            style: GoogleFonts.outfit(
              color: AppTheme.primaryDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
