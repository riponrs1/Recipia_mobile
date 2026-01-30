import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../models/recipe.dart';
import 'recipe_form_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_list_screen.dart';
import 'ingredients_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  int _recipeCount = 0;
  int _ingredientCount = 0;
  int _sharedCount = 0;
  List<Recipe> _recentRecipes = [];
  String _userName = 'Chef';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final user = await _apiService.getUser();
      final stats = await _apiService.getHomeStats();

      if (mounted) {
        setState(() {
          _userName = user['name'];
          _recipeCount = stats['total_recipes'];
          _ingredientCount = stats['total_ingredients'];
          _sharedCount = stats['total_shared'] ?? 0;

          List<dynamic> recentJson = stats['recent_recipes'];
          _recentRecipes =
              recentJson.map((json) => Recipe.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome,',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600),
                        ),
                        Text(
                          _userName,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.menu_book,
                      label: 'Total Recipes',
                      count: _recipeCount.toString(),
                      color: const Color(0xFF0D6EFD),
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      icon: Icons.people,
                      label: 'Shared with Me',
                      count: _sharedCount.toString(),
                      color: const Color(0xFF6F42C1),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.kitchen,
                      label: 'Ingredients',
                      count: _ingredientCount.toString(),
                      color: const Color(0xFF198754),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Recipes',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) => const RecipeListScreen()),
                            )
                            .then((_) => _loadDashboardData());
                      },
                      child: const Text('View All'),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                if (_recentRecipes.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.grey.shade200,
                          style: BorderStyle.solid),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.menu_book,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No recipes yet',
                            style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                else
                  ..._recentRecipes.map((recipe) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildRecentRecipeCard(context, recipe),
                      )),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(builder: (_) => const RecipeFormScreen()),
              )
              .then((_) => _loadDashboardData());
        },
        backgroundColor: const Color(0xFFE74C3C),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatCard(
      {required IconData icon,
      required String label,
      required String count,
      required Color color}) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5)),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (label == 'Total Recipes') {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                        builder: (_) => const RecipeListScreen(initialTab: 0)),
                  )
                  .then((_) => _loadDashboardData());
            } else if (label == 'Shared with Me') {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                        builder: (_) => const RecipeListScreen(initialTab: 1)),
                  )
                  .then((_) => _loadDashboardData());
            } else if (label == 'Ingredients') {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                        builder: (_) => const IngredientsScreen()),
                  )
                  .then((_) => _loadDashboardData());
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 16),
                Text(count,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text(label,
                    style: TextStyle(
                        fontSize: 14, color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRecipeCard(BuildContext context, Recipe recipe) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade100,
            child: recipe.itemPhoto != null
                ? _buildRecipeImage(recipe.itemPhoto!)
                : const Icon(Icons.restaurant, color: Colors.orange),
          ),
        ),
        title: Text(recipe.name,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
        subtitle: Text(recipe.sectionName,
            style: const TextStyle(fontSize: 12, color: Colors.blue)),
        trailing:
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                    builder: (_) => RecipeDetailScreen(recipe: recipe)),
              )
              .then((_) => _loadDashboardData());
        },
      ),
    );
  }

  Widget _buildRecipeImage(String path) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.grey.shade100,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.orange.shade50,
          child: const Icon(Icons.restaurant, color: Colors.orange),
        ),
      );
    } else {
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.orange.shade50,
          child: const Icon(Icons.restaurant, color: Colors.orange),
        ),
      );
    }
  }
}
