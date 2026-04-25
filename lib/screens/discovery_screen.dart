import 'package:flutter/material.dart';
import '../services/recipe_insight_service.dart';
import 'recipe_detail_screen.dart';
import 'recipe_analysis_screen.dart';
import '../models/recipe.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _insightService = RecipeInsightService();
  bool _isLoading = true;
  
  Map<String, double> _recipeStats = {'totalCost': 0.0, 'totalCalories': 0.0};
  List<Map<String, dynamic>> _discoveredRecipes = [];
  
  double _maxBudget = 50.0;
  double _maxCalories = 2000.0;
  String _sortBy = 'cost';
  String _nameQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final stats = await _insightService.calculateCollectionStats();
    final discovery = await _insightService.discoverRecipes(
      maxBudget: _maxBudget,
      maxCalories: _maxCalories,
      sortBy: _sortBy,
    );

    if (mounted) {
      setState(() {
        _recipeStats = stats;
        _discoveredRecipes = discovery;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredResults() {
    if (_nameQuery.isEmpty) return _discoveredRecipes;
    return _discoveredRecipes.where((item) {
      final Recipe r = item['recipe'];
      return r.name.toLowerCase().contains(_nameQuery.toLowerCase());
    }).toList();
  }

  Future<void> _refreshDiscovery() async {
    final discovery = await _insightService.discoverRecipes(
      maxBudget: _maxBudget,
      maxCalories: _maxCalories,
      sortBy: _sortBy,
    );
    if (mounted) {
      setState(() {
        _discoveredRecipes = discovery;
      });
    }
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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAnalyticsSection(),
                  const SizedBox(height: 32),
                  _buildDiscoveryTools(),
                  const SizedBox(height: 32),
                  const Text('DISCOVERY RESULTS', 
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFE1B12C))),
                  const SizedBox(height: 16),
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _nameQuery = val),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'Search within results...',
                        hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFFE1B12C)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _isLoading 
            ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF1B4D3E))))
            : _discoveredRecipes.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState())
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final results = _getFilteredResults();
                        return _buildDiscoveryCard(results[index]);
                      },
                      childCount: _getFilteredResults().length,
                     ),
                   ),
                 ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 140.0,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1B4D3E),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 24, bottom: 20),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Culinary', style: TextStyle(color: Color(0xFFE1B12C), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text('DISCOVERY', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsSection() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'TOTAL VALUE', 
            '\$${_recipeStats['totalCost']?.toStringAsFixed(2)}', 
            Icons.account_balance_wallet_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'TOTAL CALORIES', 
            '${_recipeStats['totalCalories']?.toStringAsFixed(0)} kcal', 
            Icons.bolt_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE1B12C), size: 20),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFB2BEC3), letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))),
        ],
      ),
    );
  }

  Widget _buildDiscoveryTools() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4D3E),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SMART FILTERS', 
            style: TextStyle(color: Color(0xFFE1B12C), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 24),
          _buildSliderLabel('Max Budget', '\$${_maxBudget.toInt()}'),
          Slider(
            value: _maxBudget,
            min: 5,
            max: 200,
            divisions: 39,
            activeColor: const Color(0xFFE1B12C),
            inactiveColor: Colors.white.withOpacity(0.1),
            onChanged: (val) {
              setState(() => _maxBudget = val);
              _refreshDiscovery();
            },
          ),
          const SizedBox(height: 16),
          _buildSliderLabel('Max Calories', '${_maxCalories.toInt()} kcal'),
          Slider(
            value: _maxCalories,
            min: 100,
            max: 5000,
            divisions: 49,
            activeColor: const Color(0xFFE1B12C),
            inactiveColor: Colors.white.withOpacity(0.1),
            onChanged: (val) {
              setState(() => _maxCalories = val);
              _refreshDiscovery();
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildSortChip('Lowest Price', 'cost'),
              const SizedBox(width: 12),
              _buildSortChip('Lowest Cal', 'calories'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderLabel(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildSortChip(String label, String type) {
    bool isSelected = _sortBy == type;
    return GestureDetector(
      onTap: () {
        setState(() => _sortBy = type);
        _refreshDiscovery();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE1B12C) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, 
          style: TextStyle(
            color: isSelected ? const Color(0xFF1B4D3E) : Colors.white60, 
            fontSize: 10, 
            fontWeight: FontWeight.w900
          )
        ),
      ),
    );
  }

  Widget _buildDiscoveryCard(Map<String, dynamic> item) {
    final Recipe recipe = item['recipe'];
    final double cost = item['cost'];
    final double calories = item['calories'];

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFDFBF7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.restaurant_rounded, color: Color(0xFF1B4D3E), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF2D3436))),
                  const SizedBox(height: 4),
                  Text(recipe.sectionName.toUpperCase(), 
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFE1B12C), letterSpacing: 1)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('\$${cost.toStringAsFixed(2)}', 
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1B4D3E))),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RecipeAnalysisScreen(recipe: recipe, batchMultiplier: 1.0)
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1B12C).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.insights_rounded, size: 14, color: Color(0xFFE1B12C)),
                      ),
                    ),
                  ],
                ),
                Text('${calories.toStringAsFixed(0)} kcal', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: Color(0xFFB2BEC3))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.brown.shade100),
          const SizedBox(height: 16),
          const Text('NO MATCHES FOUND', 
            style: TextStyle(color: Color(0xFFE1B12C), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 8),
          const Text('Try adjusting your filters', style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}
