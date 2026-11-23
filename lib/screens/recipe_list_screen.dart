import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../widgets/app_toast.dart';
import '../app_settings.dart';
import '../services/price_book.dart';
import '../tab_events.dart';
import '../database_helper.dart';
import '../models/recipe.dart';
import 'recipe_detail_screen.dart';
import 'recipe_form_screen.dart';
import 'recipe_share_screen.dart';

// ---- Redesign palette (matches app theme) ----
const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

class RecipeListScreen extends StatefulWidget {
  final String? initialCategory;
  const RecipeListScreen({super.key, this.initialCategory});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  final _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ScrollController _chipScroll = ScrollController();

  List<Recipe> _allRecipes = [];
  List<Recipe> _filteredRecipes = [];
  final Map<int, double> _gramCache = {};
  final Map<int, int> _countCache = {};
  bool _isLoading = true;
  bool _gridView = false;
  int? _currentUserId;
  String _userName = '';

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
    AppSettings.changes.addListener(_onSettings);
    TabReselect.instance.addListener(_onTabReselect);
  }

  /// Recipes tab tapped again: show all recipes from the top.
  void _onTabReselect() {
    if (TabReselect.instance.tab != 0 || !mounted) return;
    _searchController.clear();
    setState(() => _selectedCategory = 'All');
    _filterRecipes();
    for (final c in [_scroll, _chipScroll]) {
      if (c.hasClients) {
        c.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    }
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.changes.removeListener(_onSettings);
    TabReselect.instance.removeListener(_onTabReselect);
    _scroll.dispose();
    _chipScroll.dispose();
    _searchController.dispose();
    super.dispose();
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
    // who you are, from the phone first (no waiting for the server)
    final cached = await DatabaseHelper().getCachedData('user_profile');
    if (cached is Map && cached['id'] != null && mounted) {
      final user = Map<String, dynamic>.from(cached);
      setState(() {
          _currentUserId = user['id'];
          final n = (user['name'] ?? '').toString();
          _userName = n == 'Offline Chef' ? '' : n.split(' ').first;
          if (_allRecipes.isNotEmpty) _filterRecipes();
      });
    }
    try {
      final user = await _apiService.getUser();
      if (mounted) {
        setState(() {
          _currentUserId = user['id'];
          final n = (user['name'] ?? '').toString();
          _userName = n == 'Offline Chef' ? '' : n.split(' ').first;
          if (_allRecipes.isNotEmpty) _filterRecipes();
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _applyRecipes(List<Recipe> recipes) {
    _allRecipes = recipes;
    _gramCache.clear();
    _countCache.clear();
    for (final r in recipes) {
      _gramCache[r.id] = _computeGrams(r);
      _countCache[r.id] = _computeCount(r);
    }
    _extractSectionsFromRecipes();
    _filterRecipes();
  }

  // cache-first: show local instantly, then refresh from the network in the background
  Future<void> _loadRecipes({bool background = false}) async {
    if (!background) {
      try {
        final cached = await DatabaseHelper().getCachedRecipes();
        if (cached.isNotEmpty && mounted) {
          setState(() {
            _applyRecipes(
                cached.map((j) => Recipe.fromJson(j)).toList());
            _isLoading = false;
          });
        }
      } catch (_) {}
    }
    try {
      // refreshes the local cache (which preserves full ingredients even
      // though the list endpoint omits them), then display from cache.
      await _apiService.getRecipes();
      final cached = await DatabaseHelper().getCachedRecipes();
      final recipes = cached.map((json) => Recipe.fromJson(json)).toList();
      if (mounted) {
        setState(() {
          _applyRecipes(recipes);
          _isLoading = false;
        });
      }
      _fillMissingDetails(recipes);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _filling = false;

  /// Recipes saved without their ingredients (older server lists left them
  /// out) are fetched quietly, a few at a time, so the list shows real
  /// counts and weights and every recipe opens instantly — even offline later.
  Future<void> _fillMissingDetails(List<Recipe> recipes) async {
    if (_filling) return;
    final missing = recipes
        .where((r) => r.id > 0 && _computeCount(r) == 0)
        .map((r) => r.id)
        .toList();
    if (missing.isEmpty) return;
    _filling = true;
    try {
      const batch = 4;
      for (var i = 0; i < missing.length; i += batch) {
        if (!mounted) return;
        final ids = missing.skip(i).take(batch);
        final got = await Future.wait(ids.map((id) async {
          try {
            final data = await _apiService.getRecipe(id);
            if (PriceBook.parseLines(
                    data['ingredients'] is String
                        ? data['ingredients']
                        : jsonEncode(data['ingredients'] ?? []))
                .isEmpty) return false;
            await DatabaseHelper().saveLocalRecipe(data);
            return true;
          } catch (_) {
            return false;
          }
        }));
        if (!got.contains(true)) {
          if (got.every((g) => !g) && i == 0) return; // offline: try next time
          continue;
        }
        final cached = await DatabaseHelper().getCachedRecipes();
        if (!mounted) return;
        setState(() => _applyRecipes(cached.map((j) => Recipe.fromJson(j)).toList()));
      }
      await PriceBook.instance.migrateIfNeeded();
    } finally {
      _filling = false;
    }
  }

  void _filterRecipes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredRecipes = _allRecipes.where((recipe) {
        final matchesQuery = recipe.name.toLowerCase().contains(query);
        final matchesCategory = _selectedCategory == 'All' ||
            recipe.sectionName.toLowerCase() == _selectedCategory.toLowerCase();
        bool matchesUser = true;
        if (_currentUserId != null && _currentUserId != 0) {
          matchesUser = recipe.userId == _currentUserId;
        }
        return matchesQuery && matchesCategory && matchesUser;
      }).toList();
    });
  }

  // ---- helpers (computed once, then read from cache) ----
  double _grams(Recipe r) => _gramCache[r.id] ?? 0;
  int _ingCount(Recipe r) => _countCache[r.id] ?? 0;

  double _computeGrams(Recipe r) {
    try {
      final list = jsonDecode(r.ingredients);
      double t = 0;
      if (list is List) {
        for (final i in list) {
          final q = double.tryParse('${i['qty']}') ?? 0;
          final u = '${i['unit']}'.toLowerCase().trim();
          if (u == 'g' || u == 'gm' || u == 'ml') {
            t += q;
          } else if (u == 'kg' || u == 'l') {
            t += q * 1000;
          }
        }
      }
      return t;
    } catch (_) {
      return 0;
    }
  }

  int _computeCount(Recipe r) {
    try {
      final list = jsonDecode(r.ingredients);
      return list is List ? list.length : 0;
    } catch (_) {
      return 0;
    }
  }

  String _fmtG(double g) {
    final s = (g % 1 == 0) ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
    // thousands separator
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return parts.length > 1 ? '$intPart.${parts[1]} g' : '$intPart g';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildSearch(),
            _buildCategoryList(),
            const SizedBox(height: 4),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _filteredRecipes.isEmpty
                      ? _buildNoResults()
                      : RefreshIndicator(
                          color: _accent,
                          onRefresh: _loadRecipes,
                          child: _gridView ? _buildGrid() : _buildList(),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
    final count = _filteredRecipes.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Recipes',
                    style: TextStyle(fontFamily: 'SpaceGrotesk',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: _fg)),
                const SizedBox(height: 2),
                Text(
                    '$count recipe${count == 1 ? '' : 's'}${_userName.isNotEmpty ? ' · $_userName' : ''}',
                    style: const TextStyle(fontSize: 13, color: _muted)),
              ],
            ),
          ),
          _viewToggle(),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    Widget btn(bool grid, IconData icon) {
      final on = _gridView == grid;
      return GestureDetector(
        onTap: () => setState(() => _gridView = grid),
        child: Container(
          width: 36,
          height: 34,
          decoration: BoxDecoration(
            color: on ? _surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: on
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Icon(icon, size: 18, color: on ? _accent : _muted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(children: [
        btn(false, Icons.view_agenda_outlined),
        btn(true, Icons.grid_view_rounded),
      ]),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (_) => _filterRecipes(),
          style: const TextStyle(fontSize: 15, color: _fg),
          decoration: const InputDecoration(
            hintText: 'Search recipes or ingredients',
            hintStyle: TextStyle(color: _muted, fontSize: 15),
            prefixIcon: Icon(Icons.search_rounded, color: _muted, size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        controller: _chipScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = cat);
                _filterRecipes();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isSelected ? _accent : const Color(0xFFF4EAE4),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: isSelected ? Colors.transparent : _line),
                ),
                alignment: Alignment.center,
                child: Text(
                  cat,
                  style: TextStyle(
                    color: isSelected ? Colors.white : _fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- list view, grouped by section ----
  Widget _buildList() {
    // group preserving order
    final Map<String, List<Recipe>> groups = {};
    for (final r in _filteredRecipes) {
      groups.putIfAbsent(r.sectionName, () => []).add(r);
    }
    final widgets = <Widget>[];
    groups.forEach((sec, items) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
        child: Text(sec.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _muted)),
      ));
      for (final r in items) {
        widgets.add(_listCard(r));
      }
    });
    if (_allRecipes.any(_canEdit)) widgets.add(_swipeTip());
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 140),
      children: widgets,
    );
  }

  Widget _swipeTip() {
    return const Padding(
      // right inset keeps the tip clear of the scan / + buttons
      padding: EdgeInsets.fromLTRB(24, 8, 96, 0),
      child: Row(
        children: [
          Icon(Icons.west_rounded, size: 15, color: _muted),
          SizedBox(width: 6),
          Flexible(
            child: Text('Swipe left to delete · hold for more options',
                style: TextStyle(fontSize: 12, color: _muted)),
          ),
        ],
      ),
    );
  }

  // ---- open / delete / undo ----
  bool _canEdit(Recipe r) =>
      _currentUserId == 0 || (_currentUserId != null && r.userId == _currentUserId);

  Future<void> _openDetail(Recipe r) async {
    final result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: r)));
    if (!mounted) return;
    if (result is RecipeDeleted) {
      _removeLocally(result.id);
      _showUndo(result.id, result.name);
    } else if (result == true) {
      _loadRecipes(background: true);
    }
  }

  Future<void> _openEdit(Recipe r) async {
    final changed = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RecipeFormScreen(recipe: r)));
    if (changed == true && mounted) _loadRecipes(background: true);
  }

  Future<void> _openShare(Recipe r) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RecipeShareScreen(recipe: r)));
  }

  void _removeLocally(int id) {
    setState(() {
      _allRecipes.removeWhere((x) => x.id == id);
      _filteredRecipes.removeWhere((x) => x.id == id);
    });
  }

  /// Moves a recipe to Trash (local soft delete) and offers Undo.
  /// Every delete asks first; the recipe then goes to Trash (with Undo).
  Future<bool> _confirmDelete(Recipe r) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _bg,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete “${r.name}”?',
                  style: const TextStyle(fontFamily: 'SpaceGrotesk',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _fg)),
              const SizedBox(height: 8),
              const Text(
                  'It moves to Trash. You can restore it from Profile → Trash for 30 days.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: _fg)),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0392B),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Move to Trash',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _fg,
                    backgroundColor: _surface,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _trash(Recipe r, {bool asked = false}) async {
    if (!asked && !await _confirmDelete(r)) return;
    if (!mounted) return;
    _removeLocally(r.id);
    final error = await _apiService.deleteRecipe(r.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      _loadRecipes(background: true);
      return;
    }
    _showUndo(r.id, r.name);
  }

  void _showUndo(int id, String name) {
    AppToast.info(
      context,
      '“$name” moved to Trash',
      actionLabel: 'Undo',
      onAction: () async {
        await _apiService.restoreRecipe(id);
        if (mounted) _loadRecipes(background: true);
      },
    );
  }

  void _showActions(Recipe r) {
    final canEdit = _canEdit(r);
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap,
            {bool danger = false}) {
          final color = danger ? const Color(0xFFC0392B) : _fg;
          return InkWell(
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _surface2, borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 19, color: danger ? color : _accent),
                ),
                const SizedBox(width: 14),
                Text(label, style: TextStyle(fontSize: 15, color: color)),
              ]),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                          color: _line, borderRadius: BorderRadius.circular(9))),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    item(Icons.visibility_outlined, 'Open', () => _openDetail(r)),
                    if (canEdit) ...[
                      const Divider(height: 1, color: _line),
                      item(Icons.edit_outlined, 'Edit', () => _openEdit(r)),
                    ],
                    const Divider(height: 1, color: _line),
                    item(Icons.share_outlined, 'Share', () => _openShare(r)),
                    if (canEdit) ...[
                      const Divider(height: 1, color: _line),
                      item(Icons.delete_outline_rounded, 'Delete',
                          () => _trash(r),
                          danger: true),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listCard(Recipe r) {
    final card = GestureDetector(
      onTap: () => _openDetail(r),
      onLongPress: () => _showActions(r),
      child: _listCardBody(r),
    );
    if (!_canEdit(r)) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: card);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Dismissible(
          key: ValueKey('recipe-${r.id}'),
          direction: DismissDirection.endToStart,
          dismissThresholds: const {DismissDirection.endToStart: 0.35},
          background: Container(
            color: const Color(0xFFC0392B),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Delete',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          confirmDismiss: (_) => _confirmDelete(r),
          onDismissed: (_) => _trash(r, asked: true),
          child: card,
        ),
      ),
    );
  }

  Widget _listCardBody(Recipe r) {
    final n = _ingCount(r);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            _thumb(r, 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _fg)),
                  const SizedBox(height: 2),
                  // the section is already the heading above the cards
                  Text('$n ingredient${n == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (AppSettings.showWeights)
              Text(_fmtG(_grams(r)),
                  style: const TextStyle(fontFamily: 'SpaceGrotesk',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _muted)),
          ],
        ),
      );
  }

  // ---- grid view ----
  Widget _buildGrid() {
    return GridView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _filteredRecipes.length,
      itemBuilder: (context, i) => _gridCard(_filteredRecipes[i]),
    );
  }

  Widget _gridCard(Recipe r) {
    return GestureDetector(
      onTap: () => _openDetail(r),
      onLongPress: () => _showActions(r),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: _photoOrTile(r),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    button: true,
                    label: 'More for ${r.name}',
                    child: GestureDetector(
                      onTap: () => _showActions(r),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.more_vert_rounded,
                            size: 18, color: _fg),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _fg)),
                  const SizedBox(height: 5),
                  Text(
                      [
                        if (AppSettings.showWeights) _fmtG(_grams(r)),
                        '${_ingCount(r)} items'
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // thumbnail (photo or soft tile with initial)
  Widget _thumb(Recipe r, double size) {
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
          style: const TextStyle(fontFamily: 'SpaceGrotesk',
              fontSize: 19, fontWeight: FontWeight.w700, color: _accent)),
    );
    if (r.itemPhoto == null || r.itemPhoto!.isEmpty) return tile;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
          width: size,
          height: size,
          child: _buildRecipeImage(r.itemPhoto!, tile)),
    );
  }

  Widget _photoOrTile(Recipe r) {
    final tile = Container(
      color: _accentSoft,
      alignment: Alignment.center,
      child: Text(r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
          style: const TextStyle(fontFamily: 'SpaceGrotesk',
              fontSize: 30, fontWeight: FontWeight.w700, color: _accent)),
    );
    if (r.itemPhoto == null || r.itemPhoto!.isEmpty) return tile;
    return SizedBox.expand(child: _buildRecipeImage(r.itemPhoto!, tile));
  }

  /// Shows the recipe photo; [fallback] (the letter tile) is shown while it
  /// loads and when the photo is missing or cannot load.
  Widget _buildRecipeImage(String path, Widget fallback) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (context, url) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    } else {
      return Image.file(File(imageUrl),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => fallback);
    }
  }

  Widget _buildFAB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'fab_new',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RecipeFormScreen()))
                .then((changed) {
              if (changed == true) _loadRecipes(background: true);
            }),
            backgroundColor: _accent,
            elevation: 10,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(19)),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, size: 72, color: _accentSoft),
          const SizedBox(height: 16),
          const Text('No recipes yet',
              style: TextStyle(
                  color: _muted, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
