import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../models/recipe.dart';
import '../database_helper.dart';
import 'recipe_form_screen.dart';
import 'recipe_detail_screen.dart';
import 'recipe_list_screen.dart';
import 'ingredients_screen.dart';
import 'profile_screen.dart';

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
  int _cookedCount = 0;
  List<Recipe> _recentRecipes = [];
  List<Map<String, dynamic>> _sections = [];
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
      final cookedTotal = await DatabaseHelper().getTotalCookedCount();
      final sections = await DatabaseHelper().getLocalSections();

      if (mounted) {
        setState(() {
          _userName = user['name'];
          _recipeCount = stats['total_recipes'];
          _ingredientCount = stats['total_ingredients'];
          _cookedCount = cookedTotal;
          _sections = sections.take(10).toList(); // Show first 10 sections

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
      return const Scaffold(
        backgroundColor: Color(0xFFFDFBF7),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF1B4D3E))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: const Color(0xFF1B4D3E),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildMinimalistAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _buildMetricBar(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('CATEGORIES', isSub: true),
                    const SizedBox(height: 16),
                    _buildCategoryExplorer(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('RECIPE COLLECTION', 
                      onSeeAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeListScreen()))),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _recentRecipes.isEmpty
                ? SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _buildEmptyState()))
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 160),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildRecipeCard(_recentRecipes[index]),
                        childCount: _recentRecipes.length,
                      ),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100),
        child: FloatingActionButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeFormScreen())).then((_) => _loadDashboardData()),
          backgroundColor: const Color(0xFF1B4D3E),
          elevation: 12,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  Widget _buildMinimalistAppBar() {
    return SliverAppBar(
      expandedHeight: 180.0,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1B4D3E),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 24, bottom: 72),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RECIPIA KITCHEN', 
              style: TextStyle(color: const Color(0xFFE1B12C).withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            Text(_userName, 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5)),
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF1B4D3E)),
            Positioned(
              right: -20,
              top: -20,
              child: Icon(Icons.restaurant_rounded, size: 180, color: Colors.white.withOpacity(0.04)),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFDFBF7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: _buildSearchBar(),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: TextField(
        readOnly: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeListScreen())),
        decoration: InputDecoration(
          hintText: 'Search your recipes...',
          hintStyle: TextStyle(color: Colors.brown.shade100, fontSize: 14, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFE1B12C), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildMetricBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeListScreen())),
            behavior: HitTestBehavior.opaque,
            child: _buildMetricItem(_recipeCount.toString(), 'RECIPES'),
          ),
          _buildVerticalSeparator(),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IngredientsScreen())),
            behavior: HitTestBehavior.opaque,
            child: _buildMetricItem(_ingredientCount.toString(), 'PANTRY'),
          ),
          _buildVerticalSeparator(),
          _buildMetricItem(_cookedCount.toString(), 'COOKED'),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFE1B12C), letterSpacing: 1)),
      ],
    );
  }

  Widget _buildVerticalSeparator() => Container(width: 1, height: 24, color: Colors.black.withOpacity(0.05));

  Widget _buildSectionHeader(String title, {bool isSub = false, VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, 
          style: TextStyle(
            fontSize: isSub ? 10 : 16, 
            fontWeight: FontWeight.w900, 
            letterSpacing: isSub ? 1.5 : -0.5,
            color: isSub ? const Color(0xFFE1B12C) : const Color(0xFF2D3436))),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: const Text('SEE ALL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E), letterSpacing: 1)),
          ),
      ],
    );
  }

  Widget _buildCategoryExplorer() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _sections.length,
        itemBuilder: (context, index) {
          final section = _sections[index];
          final name = section['name'] as String;
          final icon = _getSectionIcon(name);
          
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeListScreen(initialCategory: name))),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withOpacity(0.04)),
              ),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(name.toUpperCase(), 
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E), letterSpacing: 1)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getSectionIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('hot')) return '🔥';
    if (lower.contains('cold')) return '🥗';
    if (lower.contains('bakery')) return '🥐';
    if (lower.contains('pastry')) return '🍰';
    if (lower.contains('sweet')) return '🍭';
    if (lower.contains('sauce')) return '🧪';
    if (lower.contains('pizza')) return '🍕';
    if (lower.contains('breakfast')) return '🍳';
    if (lower.contains('appetizer')) return '🍢';
    if (lower.contains('main')) return '🍽️';
    if (lower.contains('dessert')) return '🍮';
    if (lower.contains('beverage')) return '🥤';
    if (lower.contains('seafood')) return '🐟';
    if (lower.contains('soup')) return '🥣';
    if (lower.contains('side')) return '🍟';
    if (lower.contains('vegetarian')) return '🥦';
    if (lower.contains('vegan')) return '🌿';
    return '🍽️';
  }

  Widget _buildRecipeCard(Recipe recipe) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: recipe.itemPhoto != null
                  ? _buildRecipeImage(recipe.itemPhoto!)
                  : Container(color: const Color(0xFF1B4D3E).withOpacity(0.1)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.sectionName.toUpperCase(), 
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFE1B12C), letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Text(recipe.name, 
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF2D3436))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      child: Column(
        children: [
          Icon(Icons.auto_stories_rounded, size: 48, color: Colors.brown.shade50),
          const SizedBox(height: 20),
          const Text('NO RECIPES YET', 
            style: TextStyle(color: Color(0xFFE1B12C), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildRecipeImage(String path) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey.shade100),
        errorWidget: (_, __, ___) => Container(color: Colors.grey.shade100, child: const Icon(Icons.broken_image)),
      );
    } else {
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade100, child: const Icon(Icons.broken_image)),
      );
    }
  }
}
