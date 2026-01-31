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
  final int initialTab;
  const RecipeListScreen({super.key, this.initialTab = 0});

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
  int _selectedTab = 0; // 0 = My Recipes, 1 = Shared with Me

  final List<String> _categories = ['All'];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
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
    } catch (e) {}
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
    } catch (e) {}
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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

        bool matchesTab = true;
        if (_currentUserId != null) {
          if (_selectedTab == 0) {
            matchesTab = recipe.userId == _currentUserId;
          } else {
            matchesTab = recipe.userId != _currentUserId;
          }
        }
        return matchesQuery && matchesCategory && matchesTab;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: _buildHeaderControls(),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: _buildStatsAndFilters(),
            ),
          ),
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFE74C3C)),
                  ),
                )
              : _filteredRecipes.isEmpty
                  ? SliverFillRemaining(child: _buildNoResults())
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 600 ? 3 : 2,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildRecipeCard(_filteredRecipes[index]),
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
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      stretch: true,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        centerTitle: false,
        titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 16),
        title: const Text(
          'Recipia',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.person_outline, color: Color(0xFF475569)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        children: [
          _buildSearchBar(),
          const SizedBox(height: 20),
          _buildCategoryList(),
          const SizedBox(height: 20),
          _buildTabSwitcher(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => _filterRecipes(),
        decoration: InputDecoration(
          hintText: 'Find a great recipe...',
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
          prefixIcon: const Icon(Icons.search_rounded,
              color: Color(0xFF94A3B8), size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.cancel_rounded,
                      color: Color(0xFF64748B), size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _filterRecipes();
                  })
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        physics: const BouncingScrollPhysics(),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategory = cat);
              _filterRecipes();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: const Color(0xFF1E293B).withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return IntrinsicHeight(
      child: Row(
        children: [
          _buildModernTab('Personal', 0, Icons.restaurant_menu_rounded),
          const SizedBox(width: 12),
          _buildModernTab('Community', 1, Icons.explore_rounded),
        ],
      ),
    );
  }

  Widget _buildModernTab(String title, int index, IconData icon) {
    final bool isActive = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
            _filterRecipes();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFEEF2FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF6366F1).withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? const Color(0xFF4F46E5)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF64748B),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsAndFilters() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${_filteredRecipes.length} recipes found',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Icon(Icons.tune_rounded, size: 20, color: Color(0xFF64748B)),
      ],
    );
  }

  Widget _buildRecipeCard(Recipe recipe) {
    final bool isOwner = _currentUserId == recipe.userId;

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
          MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe)),
        )
            .then((result) {
          if (result == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Recipe deleted'),
                    backgroundColor: Colors.green),
              );
            }
          }
          _loadRecipes();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  recipe.itemPhoto != null
                      ? _buildRecipeImage(recipe.itemPhoto!)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF818CF8), Color(0xFF6366F1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.flatware_rounded,
                              color: Colors.white54, size: 40),
                        ),
                  _buildCardBadges(recipe, isOwner),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.transparent
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          recipe.sectionName.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (!isOwner && recipe.ownerName != null)
                        Expanded(
                          child: Text(
                            '• ${recipe.ownerName}',
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBadges(Recipe recipe, bool isOwner) {
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (recipe.isPending == 1)
            _buildBadge(Icons.sync_rounded, 'PENDING', const Color(0xFFF59E0B)),
          if (!isOwner)
            _buildBadge(
                Icons.people_rounded, 'COMMUNITY', const Color(0xFF10B981)),
          if (isOwner && (recipe.sharedWithCount ?? 0) > 0)
            _buildBadge(Icons.share_rounded, '${recipe.sharedWithCount}',
                const Color(0xFF6366F1)),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RecipeFormScreen()),
          );
          _loadRecipes();
        },
        backgroundColor: const Color(0xFFE74C3C),
        elevation: 4,
        highlightElevation: 8,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'NEW RECIPE',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.flatware_rounded,
                size: 80, color: const Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Recipes Yet',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          Text(
            'Time to share your culinary secrets!\nCreate your first masterpiece today.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15, color: Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              _searchController.clear();
              setState(() => _selectedCategory = 'All');
              _filterRecipes();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Clear All Filters',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )
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
        placeholder: (context, url) => Container(
          color: const Color(0xFFF1F5F9),
          child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFE74C3C))),
        ),
        errorWidget: (_, __, ___) => Container(
          color: const Color(0xFFF1F5F9),
          child: const Icon(Icons.flatware_rounded, color: Color(0xFFCBD5E1)),
        ),
      );
    } else {
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFF1F5F9),
          child: const Icon(Icons.flatware_rounded, color: Color(0xFFCBD5E1)),
        ),
      );
    }
  }
}
