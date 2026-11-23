import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../models/ingredient.dart';
import '../services/price_book.dart';
import '../perf.dart';
import 'ingredient_review_screen.dart';
import '../tab_events.dart';
import 'ingredient_form_screen.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _chip = Color(0xFFF4EAE4);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);
const _warn = Color(0xFFA8650A);
const _warnSoft = Color(0xFFFBEFD9);
const _needsPrice = 'Needs price';

/// Lets other screens open Ingredients on a filter (e.g. "Needs price").
final ValueNotifier<String?> ingredientFilterRequest = ValueNotifier(null);

enum _Sort { az, used, priceHigh, priceLow, changed }

const _sortNames = {
  _Sort.az: ('A–Z', 'By name'),
  _Sort.used: ('Most used', 'In the most recipes first'),
  _Sort.priceHigh: ('Price ↓', 'Highest price first'),
  _Sort.priceLow: ('Price ↑', 'Lowest price first'),
  _Sort.changed: ('Changed', 'Price changed most recently first'),
};

/// The price list: one clean list, search + sort, filters with counts, and a
/// quiet "Review" line for names in recipes and look-alikes. Nothing is
/// added or merged unless the cook chooses it.
class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  final _apiService = ApiService();
  final _book = PriceBook.instance;
  final _searchCtl = TextEditingController();
  final _scroll = ScrollController();

  bool _isLoading = true;
  List<Ingredient> _ingredients = [];
  List<Ingredient> _shown = [];
  String _query = '';
  String _category = 'All';
  _Sort _sort = _Sort.az;
  Map<String, String> _lastChange = const {}; // ingredient key -> changed_at

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
    _apply();
  }

  /// Ingredients tab tapped again: all ingredients, from the top.
  void _onTabReselect() {
    if (TabReselect.instance.tab != 1 || !mounted) return;
    _searchCtl.clear();
    _query = '';
    _category = 'All';
    _apply();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _onFilterRequest() {
    final f = ingredientFilterRequest.value;
    if (f == null || !mounted) return;
    _category = f;
    _apply();
    ingredientFilterRequest.value = null;
  }

  Future<void> _loadIngredients() async {
    // phone copy first, so the list appears at once…
    await _book.load();
    _lastChange = await DatabaseHelper().latestPriceChanges();
    if (mounted) {
      _ingredients = _book.items.map((j) => Ingredient.fromJson(j)).toList();
      if (_ingredients.isNotEmpty) _isLoading = false;
      _apply();
    }
    try {
      // …then the server's list when online
      await _apiService.getIngredients();
      await _book.load();
      if (mounted) {
        _ingredients = _book.items.map((j) => Ingredient.fromJson(j)).toList();
        _isLoading = false;
        _apply();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _used(Ingredient i) => _book.usedIn(i.name).length;

  void _apply() {
    final q = _query.trim().toLowerCase();
    final list = _ingredients.where((i) {
      if (q.isNotEmpty && !i.name.toLowerCase().contains(q)) return false;
      if (_category == 'All') return true;
      if (_category == _needsPrice) return i.price == null;
      return i.category.toLowerCase() == _category.toLowerCase();
    }).toList();
    int byName(Ingredient a, Ingredient b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    switch (_sort) {
      case _Sort.az:
        list.sort(byName);
      case _Sort.used:
        list.sort((a, b) {
          final d = _used(b) - _used(a);
          return d != 0 ? d : byName(a, b);
        });
      case _Sort.priceHigh:
        list.sort((a, b) {
          final d = (b.price ?? -1).compareTo(a.price ?? -1);
          return d != 0 ? d : byName(a, b);
        });
      case _Sort.priceLow:
        list.sort((a, b) {
          final d = (a.price ?? double.infinity).compareTo(b.price ?? double.infinity);
          return d != 0 ? d : byName(a, b);
        });
      case _Sort.changed:
        list.sort((a, b) {
          final d = (_lastChange[PriceBook.key(b.name)] ?? '')
              .compareTo(_lastChange[PriceBook.key(a.name)] ?? '');
          return d != 0 ? d : byName(a, b);
        });
    }
    setState(() => _shown = list);
  }

  String _money(double v) {
    final s = v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '${AppSettings.currency}$s';
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) => perfSync('ingredients screen build', () => _build(context));

  Widget _build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(),
          _search(),
          if (!_isLoading) _reviewLine(),
          _chips(),
          const SizedBox(height: 6),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _shown.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        color: _accent,
                        onRefresh: _loadIngredients,
                        child: ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 120),
                          itemCount: _shown.length + 1,
                          itemBuilder: (_, i) => i == _shown.length
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(
                                      _shown.length == _ingredients.length
                                          ? '${_shown.length} ingredients'
                                          : '${_shown.length} of ${_ingredients.length}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                                )
                              : _row(_shown[i], i == 0, i == _shown.length - 1),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    final priced = _ingredients.where((i) => i.price != null).length;
    final value = _ingredients.fold<double>(0, (t, i) => t + (i.price ?? 0));
    final valueText = value >= 1000
        ? '${AppSettings.currency}${(value / 1000).toStringAsFixed(1)}k'
        : _money(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ingredients',
                style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: _fg)),
            const SizedBox(height: 2),
            Text(
                _isLoading
                    ? ' '
                    : '${_ingredients.length} ingredients · $priced priced · $valueText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _muted)),
          ]),
        ),
        GestureDetector(
          onTap: _navigateToAdd,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
            child: const Icon(Icons.add_rounded, color: _fg, size: 22),
          ),
        ),
      ]),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Container(
        decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) {
                _query = v;
                _apply();
              },
              style: const TextStyle(fontSize: 15, color: _fg),
              decoration: const InputDecoration(
                hintText: 'Search ingredients',
                hintStyle: TextStyle(color: _muted, fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded, color: _muted, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          Container(width: 1, height: 22, color: _line),
          InkWell(
            onTap: _openSort,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.swap_vert_rounded, size: 18, color: _accent),
                const SizedBox(width: 4),
                Text(_sortNames[_sort]!.$1,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// "Review · 32 from recipes · 1 look-alike" — only when there is something.
  Widget _reviewLine() {
    final nr = _book.missingFromList().length;
    final la = _book.duplicatePairs().length;
    if (nr == 0 && la == 0) return const SizedBox.shrink();
    Widget link(String t, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Text(t,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                  decoration: TextDecoration.underline,
                  decorationColor: _line)),
        );
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(22, 0, 20, 8),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        const Text('Review', style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w500)),
        if (nr > 0)
          link('$nr from recipes',
              () => _review(const MissingNamesScreen(), (n) => 'Added $n to Ingredients')),
        if (nr > 0 && la > 0) const Text('·', style: TextStyle(color: _muted)),
        if (la > 0)
          link('$la look-alike${la == 1 ? '' : 's'}',
              () => _review(const DuplicatesScreen(), (n) => 'Merged $n pair${n == 1 ? '' : 's'}')),
      ]),
    );
  }

  Widget _chips() {
    final counts = <String, int>{};
    for (final i in _ingredients) {
      final c = i.category.trim().isEmpty ? 'Uncategorized' : i.category.trim();
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final np = _ingredients.where((i) => i.price == null).length;
    final cats = counts.keys.toList()..sort();
    final items = <(String, int)>[
      ('All', _ingredients.length),
      if (np > 0 || _category == _needsPrice) (_needsPrice, np),
      for (final c in cats) (c, counts[c]!),
    ];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final (cat, n) = items[i];
          final on = _category == cat;
          final warn = cat == _needsPrice;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                _category = cat;
                _apply();
                if (_scroll.hasClients) _scroll.jumpTo(0);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? (warn ? _warn : _accent) : (warn ? _warnSoft : _chip),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: on || warn ? Colors.transparent : _line),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: cat),
                    TextSpan(
                        text: '  $n',
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: (on ? Colors.white : (warn ? _warn : _fg)).withValues(alpha: .6))),
                  ]),
                  style: TextStyle(
                      color: on ? Colors.white : (warn ? _warn : _fg),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _catHue = {
    'dairy': 200, 'produce': 96, 'vegetables': 96, 'fruits': 330,
    'meat': 4, 'seafood': 190, 'sauces': 28, 'spices': 12, 'oils': 48,
    'grains': 38, 'bakery': 30, 'beverages': 210, 'other': 265,
  };

  Color _catColor(String cat) {
    final h = _catHue[cat.toLowerCase()] ?? (cat.hashCode % 360).abs();
    return HSLColor.fromAHSL(1, h.toDouble(), 0.46, 0.50).toColor();
  }

  /// One row of the single list card (first/last rows round the corners).
  Widget _row(Ingredient item, bool first, bool last) {
    final used = _used(item);
    const r = Radius.circular(14);
    return Material(
      color: _surface,
      borderRadius: BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
      child: InkWell(
        onTap: () => _navigateToEdit(item),
        borderRadius: BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(top: first ? r : Radius.zero, bottom: last ? r : Radius.zero),
            border: Border(
              left: const BorderSide(color: _line),
              right: const BorderSide(color: _line),
              top: first ? const BorderSide(color: _line) : BorderSide.none,
              bottom: const BorderSide(color: _line),
            ),
          ),
          child: Row(children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: _catColor(item.category), shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: _fg)),
                const SizedBox(height: 1),
                Text('${item.category} · ${used > 0 ? '$used recipe${used == 1 ? '' : 's'}' : 'not used'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 10),
            item.price == null
                ? const Text('No price',
                    style: TextStyle(color: _warn, fontWeight: FontWeight.w600, fontSize: 12))
                : Text.rich(
                    TextSpan(children: [
                      TextSpan(text: _money(item.price!)),
                      if ((item.unit ?? '').isNotEmpty)
                        TextSpan(
                            text: '/${item.unit}',
                            style: const TextStyle(
                                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: _muted)),
                    ]),
                    style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontWeight: FontWeight.w600,
                        color: _fg,
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
          ]),
        ),
      ),
    );
  }

  Widget _empty() {
    final filtered = _ingredients.isNotEmpty;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.restaurant_rounded, size: 64, color: _accentSoft),
        const SizedBox(height: 14),
        Text(filtered ? 'No ingredients found' : 'No ingredients yet',
            style: const TextStyle(color: _muted, fontSize: 15, fontWeight: FontWeight.w600)),
        if (!filtered) ...[
          const SizedBox(height: 6),
          const Text('Tap + to add your first one.', style: TextStyle(color: _muted, fontSize: 13)),
        ],
      ]),
    );
  }

  // ------------------------------------------------------------------ actions
  Future<void> _openSort() async {
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                  width: 40, height: 5, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(9))),
            ),
            const SizedBox(height: 14),
            const Text('Sort ingredients',
                style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.w700, color: _fg)),
            const SizedBox(height: 12),
            for (final s in _Sort.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, s),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: s == _sort ? _accent : _line),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_sortNames[s]!.$1,
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w600, color: s == _sort ? _accent : _fg)),
                          const SizedBox(height: 2),
                          Text(_sortNames[s]!.$2, style: const TextStyle(fontSize: 12, color: _muted)),
                        ]),
                      ),
                      if (s == _sort) const Icon(Icons.check_rounded, color: _accent),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _sort = picked;
    _apply();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _review(Widget screen, String Function(int) done) async {
    final n = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted || n == null || n == 0) return;
    _loadIngredients();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(done(n))));
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
        .push(MaterialPageRoute(builder: (_) => IngredientFormScreen(ingredient: item)))
        .then((val) {
      if (val == true) _loadIngredients();
    });
  }
}
