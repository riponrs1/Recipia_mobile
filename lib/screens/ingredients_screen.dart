import 'package:flutter/material.dart';
import '../api_service.dart';
import '../models/ingredient.dart';
import 'ingredient_form_screen.dart';
import 'profile_screen.dart';

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
      final data = await _apiService.getIngredients();
      final loaded = (data).map((json) => Ingredient.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          _ingredients = loaded;
          _filterIngredients();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _filterIngredients() {
    setState(() {
      _filteredIngredients = _ingredients.where((ingredient) {
        final matchesSearch =
            ingredient.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesCategory = _selectedCategory == 'All' ||
            ingredient.category.toLowerCase() == _selectedCategory.toLowerCase();
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7), // Creamy background
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildFilterSection()),
          _isLoading 
            ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            : _filteredIngredients.isEmpty 
               ? _buildEmptyState()
               : _buildIngredientsList(),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100), // Lifted to clear navigation bar
        child: FloatingActionButton.extended(
          onPressed: _navigateToAdd,
          backgroundColor: const Color(0xFF1B4D3E),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('New Ingredient', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 180.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1B4D3E),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 24, bottom: 60),
        title: const Text(
          'Pantry',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 28,
            letterSpacing: -0.5,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF1B4D3E)),
            Positioned(
              right: -50,
              top: -50,
              child: Icon(Icons.kitchen_rounded, size: 250, color: Colors.white.withOpacity(0.05)),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: _loadIngredients,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ),
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
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        onChanged: (val) {
          _searchQuery = val;
          _filterIngredients();
        },
        decoration: InputDecoration(
          hintText: 'Search items...',
          hintStyle: TextStyle(color: Colors.brown.shade200, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.brown.shade300),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
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
              selectedColor: const Color(0xFFE1B12C).withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFFD63031) : const Color(0xFF636E72),
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                fontSize: 13,
              ),
              backgroundColor: Colors.white,
              elevation: 0,
              pressElevation: 0,
              side: BorderSide(
                color: isSelected ? const Color(0xFFD63031).withOpacity(0.3) : Colors.black12,
                width: 1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIngredientsList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = _filteredIngredients[index];
            return _buildIngredientCard(item);
          },
          childCount: _filteredIngredients.length,
        ),
      ),
    );
  }

  Widget _buildIngredientCard(Ingredient item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _navigateToEdit(item),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildCategoryIcon(item.category),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF2D3436))),
                      const SizedBox(height: 4),
                      Text(item.category, style: TextStyle(color: Colors.brown.shade300, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.price != null && item.unit != null)
                      Text('\$${item.price!.toStringAsFixed(2)}/${item.unit}', 
                           style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E), fontSize: 14)),
                    if (item.calories != null)
                      Text('${item.calories!.toInt()} kcal', 
                           style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryIcon(String category) {
    IconData icon;
    Color color;
    switch (category.toLowerCase()) {
      case 'dairy': icon = Icons.egg_outlined; color = Colors.orange; break;
      case 'produce': icon = Icons.eco_outlined; color = Colors.green; break;
      case 'meat': icon = Icons.kebab_dining_outlined; color = Colors.red; break;
      default: icon = Icons.inventory_2_outlined; color = Colors.brown;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_rounded, size: 80, color: Colors.brown.shade50),
            const SizedBox(height: 16),
            Text('Pantry is empty', style: TextStyle(color: Colors.brown.shade200, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _navigateToAdd() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IngredientFormScreen())).then((val) {
      if (val == true) _loadIngredients();
    });
  }

  void _navigateToEdit(Ingredient item) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => IngredientFormScreen(ingredient: item))).then((val) {
      if (val == true) _loadIngredients();
    });
  }
}
