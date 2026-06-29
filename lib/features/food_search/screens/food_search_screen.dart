import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../models/food_nutrition_item.dart';
import '../services/food_search_service.dart';
import '../../diary/models/diary_dto.dart';
import '../../diary/providers/diary_provider.dart';
import '../../diary/models/food_entry.dart';

class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key});

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FoodSearchService _service = FoodSearchService.instance;
  Timer? _debounce;
  late Future<void> _loadFuture;
  List<FoodNutritionItem> _suggestions = <FoodNutritionItem>[];
  FoodNutritionItem? _selectedFood;
  bool _isLoading = true;
  bool _isSearching = false;
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
      _isSearching = true;
      _errorMessage = null;
    });
    
    try {
      final results = await _service.searchFoods(query);
      setState(() {
        _suggestions = results;
        _isSearching = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isSearching = false;
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
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Connection error: $_errorMessage',
                        style: GoogleFonts.outfit(color: AppTheme.error, fontWeight: FontWeight.w500),
                      ),
                    ),
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    ),
                  if (_suggestions.isNotEmpty && !_isSearching)
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
                    child: _isSearching
                        ? const SizedBox()
                        : (_errorMessage != null && _suggestions.isEmpty)
                            ? const SizedBox()
                            : _suggestions.isEmpty
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddMealBottomSheet(food),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Add to Diary',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMealBottomSheet(FoodNutritionItem food) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddMealBottomSheet(
        food: food,
        onSave: (quantity, mealType, date) async {
          Navigator.pop(context);
          try {
            final entry = FoodEntry(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: food.name,
              calories: ((food.calories ?? 0.0) * (quantity / 100)).round(),
              proteinG: (food.protein ?? 0.0) * (quantity / 100),
              carbsG: (food.carbs ?? 0.0) * (quantity / 100),
              fatG: (food.fat ?? 0.0) * (quantity / 100),
              date: date,
              mealType: mealType,
            );
            await ref.read(localStorageProvider).addEntry(entry);
            ref.invalidate(dailyDiaryProvider);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${food.name} added to $mealType!'),
                  backgroundColor: AppTheme.primaryDark,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to add to diary.'),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          }
        },
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

class _AddMealBottomSheet extends StatefulWidget {
  final FoodNutritionItem food;
  final Function(double quantity, String mealType, DateTime date) onSave;

  const _AddMealBottomSheet({required this.food, required this.onSave});

  @override
  State<_AddMealBottomSheet> createState() => _AddMealBottomSheetState();
}

class _AddMealBottomSheetState extends State<_AddMealBottomSheet> {
  final TextEditingController _qtyController = TextEditingController(text: "100");
  String _selectedMealType = "Snack";
  final DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add ${widget.food.name}',
            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.onBackground),
          ),
          const SizedBox(height: 20),
          Text('Quantity (grams)', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          const SizedBox(height: 8),
          TextField(
            controller: _qtyController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          Text('Meal Type', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Breakfast', 'Lunch', 'Dinner', 'Snack'].map((type) {
              final isSelected = _selectedMealType == type;
              return ChoiceChip(
                label: Text(type),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedMealType = type);
                },
                selectedColor: AppTheme.primary.withAlpha(50),
                labelStyle: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.primaryDark : AppTheme.onSurface,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(_qtyController.text) ?? 100;
                widget.onSave(qty, _selectedMealType, _selectedDate);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                'Save to Diary',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
