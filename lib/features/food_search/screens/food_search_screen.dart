import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme.dart';
import '../models/food_nutrition_item.dart';
import '../services/food_search_service.dart';

class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key});

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FoodSearchService _service = FoodSearchService.instance;
  Timer? _debounce;
  late Future<void> _loadFuture;
  List<FoodNutritionItem> _suggestions = <FoodNutritionItem>[];
  FoodNutritionItem? _selectedFood;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadFoods();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFoods() async {
    try {
      await _service.loadFoods();
      await _performSearch("");
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(value);
    });

    if (value.trim().isEmpty) {
      setState(() {
        _selectedFood = null;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final results = await _service.searchFoods(query);
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Nutrition Lookup',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.onBackground,
        elevation: 0,
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          if (_errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load the food database.\n$_errorMessage',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppTheme.onSurface),
                ),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search foods and view their nutrition values per 100g',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: AppTheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Try typing banana, chicken, rice...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_suggestions.isNotEmpty)
                    Text(
                      _searchController.text.trim().isEmpty
                          ? 'Popular foods'
                          : 'Suggestions',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _suggestions.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: _suggestions.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final food = _suggestions[index];
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedFood = food;
                                    _searchController.text = food.name;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              food.name,
                                              style: GoogleFonts.outfit(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.onBackground,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              food.sourceType,
                                              style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                color: AppTheme.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        food.caloriesLabel,
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.primaryDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedFood != null) _buildSelectedFoodCard(_selectedFood!),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'No foods matched your search. Try a shorter or different name.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(color: AppTheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildSelectedFoodCard(FoodNutritionItem food) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.onBackground.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            food.name,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Per 100g • ${food.caloriesLabel}',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _NutritionChip(label: 'Protein', value: _formatValue(food.protein)),
              _NutritionChip(label: 'Carbs', value: _formatValue(food.carbs)),
              _NutritionChip(label: 'Fat', value: _formatValue(food.fat)),
              _NutritionChip(label: 'Sugar', value: _formatValue(food.sugar)),
              _NutritionChip(label: 'Fiber', value: _formatValue(food.fiber)),
              _NutritionChip(label: 'Sodium', value: _formatValue(food.sodium, unit: 'mg')),
            ],
          ),
        ],
      ),
    );
  }

  String _formatValue(double? value, {String unit = 'g'}) {
    if (value == null) return 'N/A';
    return '${value.toStringAsFixed(1)} $unit';
  }
}

class _NutritionChip extends StatelessWidget {
  final String label;
  final String value;

  const _NutritionChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
