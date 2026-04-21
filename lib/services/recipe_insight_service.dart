import 'dart:convert';
import '../database_helper.dart';
import '../models/recipe.dart';
import '../utils/unit_converter.dart';

class RecipeInsightService {
  final _db = DatabaseHelper();

  /// Calculates the total financial and nutritional value of the entire recipe collection.
  Future<Map<String, double>> calculateAnthologyStats() async {
    final localRecipesData = await _db.getCachedRecipes();
    final pantryItems = await _db.getCachedIngredients();
    
    double totalCost = 0.0;
    double totalCalories = 0.0;

    for (var rData in localRecipesData) {
      final recipe = Recipe.fromJson(rData);
      final stats = _calculateRecipeStats(recipe, pantryItems);
      totalCost += stats['cost'] ?? 0.0;
      totalCalories += stats['calories'] ?? 0.0;
    }

    return {
      'totalCost': totalCost,
      'totalCalories': totalCalories,
    };
  }

  /// Calculates cost and calories for a specific recipe using current pantry prices.
  Map<String, double> _calculateRecipeStats(Recipe recipe, List<dynamic> pantry) {
    if (recipe.ingredients.isEmpty) return {'cost': 0.0, 'calories': 0.0};

    double cost = 0.0;
    double calories = 0.0;

    try {
      final List<dynamic> ingredients = jsonDecode(recipe.ingredients);
      for (var item in ingredients) {
        final double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
        final String unit = item['unit']?.toString() ?? '';
        final String name = item['name']?.toString().toLowerCase().trim() ?? '';

        // Find the most recent price/calories from pantry for this item
        final pantryItem = pantry.firstWhere(
          (p) => p['name'].toString().toLowerCase().trim() == name,
          orElse: () => null,
        );

        if (pantryItem != null) {
          final double pricePerKg = (pantryItem['price'] ?? 0.0).toDouble();
          final double calPerKg = (pantryItem['calories'] ?? 0.0).toDouble();
          final double grams = UnitConverter.toGrams(qty, unit);

          if (grams > 0) {
            cost += (grams / 1000) * pricePerKg;
            calories += (grams / 1000) * calPerKg;
          } else {
            // For pieces/items, use flat rate
            cost += qty * pricePerKg;
            calories += qty * calPerKg;
          }
        }
      }
    } catch (e) {
      // Skip failed parse
    }

    return {'cost': cost, 'calories': calories};
  }

  /// Finds recipes within a specific budget and calorie range.
  Future<List<Map<String, dynamic>>> discoverRecipes({
    double? maxBudget,
    double? maxCalories,
    String? sortBy, // 'cost', 'calories'
  }) async {
    final localRecipesData = await _db.getCachedRecipes();
    final pantryItems = await _db.getCachedIngredients();
    
    List<Map<String, dynamic>> results = [];

    for (var rData in localRecipesData) {
      final recipe = Recipe.fromJson(rData);
      final stats = _calculateRecipeStats(recipe, pantryItems);
      
      final recipeCost = stats['cost'] ?? 0.0;
      final recipeCals = stats['calories'] ?? 0.0;

      bool matchesBudget = maxBudget == null || recipeCost <= maxBudget;
      bool matchesCalories = maxCalories == null || recipeCals <= maxCalories;

      if (matchesBudget && matchesCalories) {
        results.add({
          'recipe': recipe,
          'cost': recipeCost,
          'calories': recipeCals,
        });
      }
    }

    if (sortBy == 'cost') {
      results.sort((a, b) => (a['cost'] as double).compareTo(b['cost'] as double));
    } else if (sortBy == 'calories') {
      results.sort((a, b) => (a['calories'] as double).compareTo(b['calories'] as double));
    }

    return results;
  }
}
