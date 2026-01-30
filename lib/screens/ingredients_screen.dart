import 'package:flutter/material.dart';
import '../api_service.dart';
import 'ingredient_form_screen.dart';
// Note: We'll need an Ingredient model later, for now we will assume dynamic or create a model if simple.
// Since we don't have an Ingredient model file yet, we will fetch raw JSON or create a basic class inside this file or assume ApiService returns List<dynamic>

class Ingredient {
  final int id;
  final String name;
  final String? brand;
  final String category;
  final double? price;
  final String? unit;
  final double? calories;

  Ingredient({
    required this.id,
    required this.name,
    this.brand,
    required this.category,
    this.price,
    this.unit,
    this.calories,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: json['id'],
      name: json['name'],
      brand: json['brand'],
      category: json['category'] ?? 'Uncategorized',
      price: json['price'] != null ? double.tryParse(json['price'].toString()) : null,
      unit: json['unit'],
      calories: json['calories'] != null ? double.tryParse(json['calories'].toString()) : null,
    );
  }
}

class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  List<Ingredient> _ingredients = [];
  List<Ingredient> _filteredIngredients = [];
  
  // Filter state
  String _searchQuery = '';
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Dry Goods',
    'Dairy',
    'Produce',
    'Meat',
    'Seafood',
    'Frozen',
    'Canned',
    'Beverages',
    'Cleaning',
    'In-House'
  ];

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    setState(() => _isLoading = true);
    try {
      // NOTE: We assume ApiService has getIngredients(). If not we need to add it.
      // For now we will mock or try to call it. 
      // Since I can't check ApiService easily without reading it again (I didn't check it for getIngredients specifically, but Dashboard had a comment about it),
      // I will implement getIngredients in ApiService in the next step if missing.
      final data = await _apiService.getIngredients();
      
      final List<Ingredient> loadedCallback = (data).map((json) => Ingredient.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          _ingredients = loadedCallback;
          _filterIngredients();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // _ingredients = []; // Keep empty on error
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading ingredients: $e')));
      }
    }
  }

  void _filterIngredients() {
    setState(() {
      _filteredIngredients = _ingredients.where((ingredient) {
        final matchesSearch = ingredient.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesCategory = _selectedCategory == 'All' || 
            ingredient.category.toLowerCase() == _selectedCategory.toLowerCase() ||
            ingredient.category.toLowerCase().contains(_selectedCategory.toLowerCase()); // Flexible match
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingredients'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadIngredients,
          )
        ],
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // Search & Filter Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search ingredients...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) {
                    _searchQuery = val;
                    _filterIngredients();
                  },
                ),
                const SizedBox(height: 12),
                // Category Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = cat;
                                _filterIngredients();
                              });
                            }
                          },
                          selectedColor: const Color(0xFFE74C3C),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          backgroundColor: Colors.grey[100],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          
          // List
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _filteredIngredients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.kitchen, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('No ingredients found', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredIngredients.length,
                        itemBuilder: (context, index) {
                          final ingredient = _filteredIngredients[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.fastfood, color: Colors.orange), // Generic food icon
                              ),
                              title: Text(
                                ingredient.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    ingredient.category,
                                    style: TextStyle(color: Colors.blue[700], fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (ingredient.price != null && ingredient.unit != null)
                                        Text('\$${ingredient.price} / ${ingredient.unit}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      if (ingredient.calories != null) ...[
                                        const SizedBox(width: 12),
                                        Text('${ingredient.calories} kcal', style: const TextStyle(color: Colors.grey)),
                                      ]
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => IngredientFormScreen(ingredient: ingredient)),
                                    ).then((result) {
                                      if (result == true) _loadIngredients();
                                    });
                                  } else if (value == 'delete') {
                                    // Confirm delete
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete Ingredient?'),
                                        content: Text('Are you sure you want to delete ${ingredient.name}?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    
                                    if (confirm == true) {
                                      final error = await _apiService.deleteIngredient(ingredient.id);
                                      if (error == null) {
                                         _loadIngredients();
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 20, color: Colors.blue), SizedBox(width: 8), Text('Edit')])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('Delete')])),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const IngredientFormScreen()),
          ).then((result) {
            if (result == true) {
              _loadIngredients();
            }
          });
        },
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add_circle, color: Colors.white),
        label: const Text('Add Ingredient', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
