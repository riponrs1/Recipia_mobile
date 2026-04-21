import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../models/recipe.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';
import 'profile_screen.dart';

class RecipeListScreen extends StatefulWidget {
  final String? initialCategory;
  const RecipeListScreen({super.key, this.initialCategory});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Recipe> _allRecipes = [];
  List<Recipe> _filteredRecipes = [];
  bool _isLoading = true;
  int? _currentUserId;

  String _selectedCategory = 'All';
  final List<String> _categories = ['All'];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    }
    _fetchCurrentUser();
    _loadRecipes();
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final localSections = await DatabaseHelper().getLocalSections();
      if (mounted) {
        setState(() {
          _categories.clear();
          _categories.add('All');
          for (var s in localSections) {
            _categories.add(s['name']);
          }
          _extractSectionsFromRecipes();
        });
      }

      final sectionsJson = await _apiService.getSections();
      if (sectionsJson.isNotEmpty) {
        for (var s in sectionsJson) {
          await DatabaseHelper().saveLocalSection({
            'name': s['name'],
            'is_system': s['user_id'] == null ? 1 : 0,
            'icon': s['icon'] ?? 'category',
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
          });
        }
        final refreshedLocal = await DatabaseHelper().getLocalSections();
        if (mounted) {
          setState(() {
            _categories.clear();
            _categories.add('All');
            for (var s in refreshedLocal) {
              _categories.add(s['name']);
            }
            _extractSectionsFromRecipes();
          });
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _extractSectionsFromRecipes() {
    if (_allRecipes.isEmpty) return;
    final existingNames = _allRecipes.map((r) => r.sectionName).toSet();
    for (var name in existingNames) {
      if (!_categories.contains(name)) {
        _categories.add(name);
      }
    }
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final user = await _apiService.getUser();
      if (mounted) {
        setState(() {
          _currentUserId = user['id'];
          if (_allRecipes.isNotEmpty) _filterRecipes();
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _loadRecipes() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getRecipes();
      final recipes = data.map((json) => Recipe.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          _allRecipes = recipes;
          _extractSectionsFromRecipes();
          _filterRecipes();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _allRecipes = [];
          _filteredRecipes = [];
        });
      }
    }
  }

  void _filterRecipes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredRecipes = _allRecipes.where((recipe) {
        final matchesQuery = recipe.name.toLowerCase().contains(query);
        final matchesCategory = _selectedCategory == 'All' ||
            recipe.sectionName.toLowerCase() == _selectedCategory.toLowerCase();

        // Only show personal recipes (Community removed)
        bool matchesUser = true;
        if (_currentUserId != null) {
          matchesUser = recipe.userId == _currentUserId;
        }
        
        return matchesQuery && matchesCategory && matchesUser;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CATEGORIES', 
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFAB1A0))),
                  const SizedBox(height: 12),
                  _buildCategoryList(),
                ],
              ),
            ),
          ),
          _isLoading
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF5D4037))))
              : _filteredRecipes.isEmpty
                  ? SliverFillRemaining(child: _buildNoResults())
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.0,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildAtelierCard(_filteredRecipes[index]),
                          childCount: _filteredRecipes.length,
                        ),
                      ),
                    ),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 180.0,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF5D4037),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 24, bottom: 68),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Museum', style: TextStyle(color: Color(0xFFFAB1A0), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text('COLLECTION', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF5D4037)),
            Positioned(
              right: -30,
              bottom: -30,
              child: Icon(Icons.auto_stories_rounded, size: 200, color: Colors.white.withOpacity(0.04)),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
          onPressed: _loadRecipes,
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
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
        controller: _searchController,
        onChanged: (_) => _filterRecipes(),
        decoration: InputDecoration(
          hintText: 'Filter your anthology...',
          hintStyle: TextStyle(color: Colors.brown.shade100, fontSize: 14, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFAB1A0), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = cat);
                _filterRecipes();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF5D4037) : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: isSelected ? Colors.transparent : Colors.black.withOpacity(0.05)),
                ),
                alignment: Alignment.center,
                child: Text(
                  cat.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF636E72),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAtelierCard(Recipe recipe) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe))).then((_) => _loadRecipes()),
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
                  : Container(color: const Color(0xFF5D4037).withOpacity(0.1)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.sectionName.toUpperCase(), 
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFFAB1A0), letterSpacing: 1)),
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

  Widget _buildRecipeImage(String path) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (context, url) => Container(color: Colors.grey.shade100),
        errorWidget: (_, __, ___) => Container(color: Colors.grey.shade100),
      );
    } else {
      return Image.file(
        File(imageUrl), 
        fit: BoxFit.cover, 
        width: double.infinity,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade100)
      );
    }
  }

  Widget _buildFAB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 100),
      child: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipeFormScreen())).then((_) => _loadRecipes()),
        backgroundColor: const Color(0xFF5D4037),
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, size: 80, color: Colors.brown.shade50),
          const SizedBox(height: 16),
          const Text('YOUR COLLECTION IS EMPTY', 
            style: TextStyle(color: Color(0xFFFAB1A0), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ],
      ),
    );
  }
}
