import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../api_service.dart';
import '../models/ingredient.dart';
import '../services/price_book.dart';
import '../tab_events.dart';
import 'ingredient_form_screen.dart';

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFFBF6E8);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);
const _accentSoft = Color(0xFFE6EFE9);
const _warn = Color(0xFFA8650A);
const _warnSoft = Color(0xFFFBEFD9);
const _needsPrice = 'Needs price';

/// Lets other screens open Ingredients on a filter (e.g. after the update summary).
final ValueNotifier<String?> ingredientFilterRequest = ValueNotifier(null);

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
    'Dairy',
    'Produce',
    'Meat',
    'Seafood',
    'Spices',
    'Oils',
    'Sauces',
    'Dry Goods',
    'Beverages',
  ];

  final _book = PriceBook.instance;
  final _searchCtl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _book.addListener(_onBook);
    ingredientFilterRequest.addListener(_onFilterRequest);
    TabReselect.instance.addListener(_onTabReselect);
    _loadIngredients();
  }

  @override
  void dispose() {
    _book.removeListener(_onBook);
    ingredientFilterRequest.removeListener(_onFilterRequest);
    TabReselect.instance.removeListener(_onTabReselect);
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onBook() {
    if (!mounted) return;
    _ingredients = _book.items.map((j) => Ingredient.fromJson(j)).toList();
    _filterIngredients();
  }

  /// Ingredients tab tapped again: show all ingredients from the top.
  void _onTabReselect() {
    if (TabReselect.instance.tab != 1 || !mounted) return;
    _searchCtl.clear();
    _searchQuery = '';
    setState(() => _selectedCategory = 'All');
    _filterIngredients();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _onFilterRequest() {
    final f = ingredientFilterRequest.value;
    if (f == null || !mounted) return;
    setState(() => _selectedCategory = f);
    _filterIngredients();
    ingredientFilterRequest.value = null;
  }

  Future<void> _loadIngredients() async {
    if (_ingredients.isEmpty) setState(() => _isLoading = true);
    try {
      await _apiService.getIngredients(); // refreshes the local copy when online
      await _book.load();
      final loaded = _book.items.map((json) => Ingredient.fromJson(json)).toList();
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
      }
    }
  }

  void _filterIngredients() {
    setState(() {
      _filteredIngredients = _ingredients.where((ingredient) {
        final matchesSearch =
            ingredient.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesCategory = _selectedCategory == 'All' ||
            (_selectedCategory == _needsPrice
                ? ingredient.price == null
                : ingredient.category.toLowerCase() ==
                    _selectedCategory.toLowerCase());
        return matchesSearch && matchesCategory;
      }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            _search(),
            if (!_isLoading && _ingredients.isNotEmpty) _summary(),
            if (!_isLoading) ..._banners(),
            _chips(),
            const SizedBox(height: 6),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _filteredIngredients.isEmpty
                      ? _empty()
                      : RefreshIndicator(
                          color: _accent,
                          onRefresh: _loadIngredients,
                          child: ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics()),
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 120),
                            itemCount: _filteredIngredients.length,
                            itemBuilder: (context, i) =>
                                _card(_filteredIngredients[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FloatingActionButton(
          onPressed: _navigateToAdd,
          backgroundColor: _accent,
          elevation: 10,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ingredients',
                    style: TextStyle(fontFamily: 'SpaceGrotesk',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: _fg)),
                const SizedBox(height: 2),
                Text('${_ingredients.length} in your pantry',
                    style: const TextStyle(fontSize: 13, color: _muted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _navigateToAdd,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line)),
              child: const Icon(Icons.add_rounded, color: _fg, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: TextField(
          controller: _searchCtl,
          onChanged: (val) {
            _searchQuery = val;
            _filterIngredients();
          },
          style: const TextStyle(fontSize: 15, color: _fg),
          decoration: const InputDecoration(
            hintText: 'Search ingredients',
            hintStyle: TextStyle(color: _muted, fontSize: 15),
            prefixIcon: Icon(Icons.search_rounded, color: _muted, size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    final np = _ingredients.where((i) => i.price == null).length;
    final cats = [
      'All',
      if (np > 0 || _selectedCategory == _needsPrice) _needsPrice,
      ..._categories.skip(1),
    ];
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: cats.length,
        itemBuilder: (context, index) {
          final cat = cats[index];
          final isSelected = _selectedCategory == cat;
          final warn = cat == _needsPrice;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = cat);
                _filterIngredients();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (warn ? _warn : _accent)
                      : (warn ? _warnSoft : const Color(0xFFF1EAD9)),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: isSelected || warn ? Colors.transparent : _line),
                ),
                child: Text(warn ? '$cat · $np' : cat,
                    style: TextStyle(
                        color: isSelected ? Colors.white : (warn ? _warn : _fg),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- prototype: count · categories · pantry value ----
  Widget _summary() {
    final cats = _ingredients.map((i) => i.category).toSet().length;
    final value =
        _ingredients.fold<double>(0, (t, i) => t + (i.price ?? 0));
    String money(double v) => v >= 1000
        ? '${AppSettings.currency}${(v / 1000).toStringAsFixed(1)}k'
        : '${AppSettings.currency}${v.toStringAsFixed(0)}';
    Widget stat(String n, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(children: [
              Text(n,
                  style: const TextStyle(fontFamily: 'SpaceGrotesk',
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: _fg)),
              const SizedBox(height: 2),
              Text(l, style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(children: [
        stat('${_ingredients.length}', 'ingredients'),
        const SizedBox(width: 10),
        stat('$cats', cats == 1 ? 'category' : 'categories'),
        const SizedBox(width: 10),
        stat(money(value), 'pantry value'),
      ]),
    );
  }

  // ---- "need a price" and "looks like a duplicate" ----
  List<Widget> _banners() {
    final out = <Widget>[];
    final np = _ingredients.where((i) => i.price == null).length;
    if (np > 0 && _selectedCategory != _needsPrice) {
      out.add(_banner(
        warn: true,
        text: TextSpan(children: [
          TextSpan(
              text: '$np need${np == 1 ? 's' : ''} a price. ',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: 'Recipes using them show an incomplete cost.'),
        ]),
        action: 'Show',
        onTap: () {
          setState(() => _selectedCategory = _needsPrice);
          _filterIngredients();
        },
      ));
    }
    final dups = _book.duplicatePairs();
    if (dups.isNotEmpty) {
      final a = dups.first[0], b = dups.first[1];
      out.add(_banner(
        warn: false,
        text: TextSpan(children: [
          const TextSpan(text: '“'),
          TextSpan(text: '${a['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: '” looks like “'),
          TextSpan(text: '${b['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '”.${dups.length > 1 ? '  +${dups.length - 1} more' : ''}'),
        ]),
        action: 'Merge',
        onTap: () => _merge(a, b),
      ));
    }
    return out;
  }

  Future<void> _merge(Map<String, dynamic> from, Map<String, dynamic> into) async {
    final n = await _book.merge(from, into);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Merged into “${into['name']}” · $n recipe${n == 1 ? '' : 's'} updated'),
    ));
  }

  Widget _banner(
      {required bool warn,
      required InlineSpan text,
      required String action,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: warn ? _warnSoft : _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: warn ? _warnSoft : _line),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: _warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(text,
                style: const TextStyle(fontSize: 13, height: 1.35, color: _fg)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(action,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  static const _catHue = {
    'dairy': 200, 'produce': 96, 'vegetables': 96, 'fruits': 330,
    'meat': 4, 'seafood': 190, 'sauces': 28, 'spices': 12, 'oils': 48,
    'grains': 38, 'bakery': 30, 'beverages': 210,
  };

  Color _catColor(String cat) {
    final h = _catHue[cat.toLowerCase()] ?? (cat.hashCode % 360).abs();
    return HSLColor.fromAHSL(1, h.toDouble(), 0.46, 0.48).toColor();
  }

  Widget _card(Ingredient item) {
    final used = _book.usedIn(item.name).length;
    return GestureDetector(
      onTap: () => _navigateToEdit(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: _catColor(item.category),
                  borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text(
                  item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontFamily: 'SpaceGrotesk',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: _fg)),
                  const SizedBox(height: 3),
                  Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: [
                          item.category,
                          if ((item.brand ?? '').trim().isNotEmpty) item.brand!.trim()
                        ].join(' · ')),
                        if (used > 0)
                          TextSpan(
                              text: ' · in $used recipe${used == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  color: _accent, fontWeight: FontWeight.w600)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (item.price == null)
                  const Text('No price yet',
                      style: TextStyle(
                          color: _warn, fontWeight: FontWeight.w600, fontSize: 12.5)),
                if (item.price != null)
                  Text(
                      '${AppSettings.currency}${item.price!.toStringAsFixed(0)}${item.unit != null ? '/${item.unit}' : ''}',
                      style: const TextStyle(fontFamily: 'SpaceGrotesk',
                          fontWeight: FontWeight.w600,
                          color: _fg,
                          fontSize: 15)),
                if (item.calories != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        ['pcs', 'pc', 'piece', 'dozen']
                                .contains((item.unit ?? '').toLowerCase())
                            ? '${item.calories!.toInt()} cal each'
                            : '${item.calories!.toInt()} cal/100g',
                        style: const TextStyle(color: _muted, fontSize: 11.5)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_rounded, size: 72, color: _accentSoft),
          const SizedBox(height: 16),
          const Text('No ingredients yet',
              style: TextStyle(
                  color: _muted, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _navigateToAdd() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const IngredientFormScreen()))
        .then((val) {
      if (val == true) _loadIngredients();
    });
  }

  void _navigateToEdit(Ingredient item) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => IngredientFormScreen(ingredient: item)))
        .then((val) {
      if (val == true) _loadIngredients();
    });
  }
}
