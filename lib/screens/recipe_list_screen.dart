import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../models/recipe.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';

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

  final List<String> _categories = [
    'All',
    'Hot Kitchen',
    'Bakery',
    'Pastry',
    'Sweet',
    'Sauce',
    'Cold/Salad',
    'Pizza',
  ];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _fetchCurrentUser();
    _loadRecipes();
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
      // Ignored: User might be offline or not logged in
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Recipes',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => _filterRecipes(),
                  decoration: InputDecoration(
                    hintText: 'Search recipes...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              _filterRecipes();
                            })
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildTab('My Recipes', 0),
                      _buildTab('Shared with Me', 1),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() => _selectedCategory = cat);
                          _filterRecipes();
                        },
                        selectedColor: const Color(0xFFE74C3C),
                        labelStyle: TextStyle(
                          color:
                              isSelected ? Colors.white : Colors.grey.shade700,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide.none),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Showing ${_filteredRecipes.length} recipes',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecipes.isEmpty
                    ? _buildNoResults()
                    : RefreshIndicator(
                        onRefresh: _loadRecipes,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = 2;
                            if (constraints.maxWidth < 300) {
                              crossAxisCount = 1;
                            } else if (constraints.maxWidth > 900) {
                              crossAxisCount = 3;
                            }
                            double ratio = crossAxisCount == 1 ? 1.5 : 0.55;

                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: ratio,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: _filteredRecipes.length,
                              itemBuilder: (context, index) {
                                return _buildRecipeCard(
                                    _filteredRecipes[index]);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RecipeFormScreen()),
          );
          _loadRecipes();
        },
        backgroundColor: const Color(0xFFE74C3C),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTab(String title, int index) {
    final bool isActive = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
            _filterRecipes();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE74C3C) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No recipes found',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() => _selectedCategory = 'All');
              _filterRecipes();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Search'),
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

  Widget _buildRecipeCard(Recipe recipe) {
    final bool isOwner = _currentUserId == recipe.userId;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context)
              .push(
            MaterialPageRoute(
                builder: (_) => RecipeDetailScreen(recipe: recipe)),
          )
              .then((result) {
            if (result == true) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Recipe deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
            _loadRecipes();
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
                flex: 4,
                child: Stack(fit: StackFit.expand, children: [
                  recipe.itemPhoto != null
                      ? _buildRecipeImage(recipe.itemPhoto!)
                      : Container(
                          decoration: const BoxDecoration(
                              gradient: LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )),
                          child: const Icon(Icons.image,
                              color: Colors.white54, size: 40),
                        ),
                  if (recipe.isPending == 1)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Pending Sync',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (!isOwner)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people, size: 10, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Shared',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  if (isOwner && (recipe.sharedWithCount ?? 0) > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.share,
                                size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('Shared (${recipe.sharedWithCount})',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                ])),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF2D3748)),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (recipe.sectionName.isNotEmpty
                                ? recipe.sectionName
                                : 'General') +
                            (_currentUserId != null &&
                                    !isOwner &&
                                    recipe.ownerName != null
                                ? ' • By ${recipe.ownerName}'
                                : ''),
                        style: const TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            RecipeDetailScreen(recipe: recipe)),
                                  )
                                  .then((_) => _loadRecipes());
                            },
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: const Color(0xFFE74C3C),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(0, 32),
                              elevation: 0,
                            ),
                            child: const Text('View',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        if (isOwner) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          RecipeFormScreen(recipe: recipe)),
                                );
                                _loadRecipes();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                foregroundColor: const Color(0xFF718096),
                                side:
                                    const BorderSide(color: Color(0xFFCBD5E0)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                minimumSize: const Size(0, 32),
                              ),
                              child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit, size: 12),
                                    SizedBox(width: 4),
                                    Text('Edit', style: TextStyle(fontSize: 12))
                                  ]),
                            ),
                          ),
                        ]
                      ],
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
