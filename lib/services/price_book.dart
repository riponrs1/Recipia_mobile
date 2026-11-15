import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import '../database_helper.dart';
import '../utils/unit_converter.dart';

/// One price list for the whole app.
///
/// Recipes only say *which* ingredient and *how much*. Cost and calories are
/// always worked out from the Ingredients list (plus an optional price set
/// for one recipe only), so changing a price there updates every recipe.
class PriceBook extends ChangeNotifier {
  PriceBook._();
  static final PriceBook instance = PriceBook._();

  /// Ingredients list rows (id, name, brand, category, price, unit, calories, auto_added).
  List<Map<String, dynamic>> items = [];

  /// recipeId -> ingredientKey -> price (in that ingredient's own unit).
  Map<int, Map<String, double>> overrides = {};

  /// recipeId -> lines, used for "Used in N recipes".
  final Map<int, _RecipeLines> _recipes = {};

  bool _loaded = false;
  bool get loaded => _loaded;

  // ---------------------------------------------------------------- names
  static String key(String? name) =>
      (name ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, dynamic>? find(String? name) {
    final k = key(name);
    if (k.isEmpty) return null;
    for (final it in items) {
      if (key(it['name']?.toString()) == k) return it;
    }
    return null;
  }

  static int _editDistance(String a, String b) {
    if ((a.length - b.length).abs() > 2) return 9;
    final d = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var prev = d[0];
      d[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final t = d[j];
        d[j] = [d[j] + 1, d[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1)]
            .reduce(math.min);
        prev = t;
      }
    }
    return d[b.length];
  }

  /// "Probably the same": a short form of the same words ("mayo" →
  /// "Mayonnaise") or a small typo ("mayonaise"). Different items that only
  /// share a word ("Chicken" / "Chicken mince") never match.
  static bool looksSame(String shortName, String longName) {
    final k = key(shortName), n = key(longName);
    if (k == n || k.length < 3) return false;
    final kw = k.split(' '), nw = n.split(' ');
    if (kw.length == nw.length && k.length < n.length) {
      var allPrefix = true, anyShorter = false;
      for (var i = 0; i < kw.length; i++) {
        if (!nw[i].startsWith(kw[i])) allPrefix = false;
        if (nw[i] != kw[i]) anyShorter = true;
      }
      if (allPrefix && anyShorter) return true;
    }
    return k.length >= 5 && _editDistance(k, n) <= 2;
  }

  /// A likely match for a name that is not in the list yet.
  Map<String, dynamic>? similar(String? name) {
    if (find(name) != null) return null;
    for (final it in items) {
      if (looksSame(name ?? '', it['name']?.toString() ?? '')) return it;
    }
    return null;
  }

  /// Pairs that look like duplicates (shorter/typo first, longer second).
  List<List<Map<String, dynamic>>> duplicatePairs() {
    final out = <List<Map<String, dynamic>>>[];
    for (final a in items) {
      for (final b in items) {
        if (identical(a, b)) continue;
        final an = a['name']?.toString() ?? '', bn = b['name']?.toString() ?? '';
        if (key(bn).length >= key(an).length && looksSame(an, bn)) {
          if (!out.any((p) => identical(p[0], b) && identical(p[1], a))) {
            out.add([a, b]);
          }
          break;
        }
      }
    }
    return out;
  }

  List<Map<String, dynamic>> needsPrice() =>
      items.where((i) => _num(i['price']) == null).toList();

  // ---------------------------------------------------------------- units
  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static const _countUnits = {'pcs', 'pc', 'piece', 'pieces', 'dozen', 'nos'};
  static bool isCount(String? u) => _countUnits.contains(key(u));

  /// Grams in one of this unit (ml treated like g), or pieces for count units.
  static double? baseOf(String? unit) {
    final u = key(unit);
    if (u == 'dozen') return 12;
    if (_countUnits.contains(u)) return 1;
    final n = double.tryParse(u); // old data: unit "1000" = per 1000 g
    if (n != null && n > 0) return n;
    final g = UnitConverter.toGrams(1, u);
    return g > 0 ? g : null;
  }

  /// Price per gram (or per piece), using a recipe-only price when set.
  double? _unitPrice(Map<String, dynamic> it, double? override) {
    final price = override ?? _num(it['price']);
    final base = baseOf(it['unit']?.toString() ?? 'kg');
    if (price == null || base == null || base == 0) return null;
    return price / base;
  }

  /// Cost of one recipe line, or null when it can't be priced.
  double? lineCost(String name, double qty, String unit,
      {Map<String, double>? recipeOverrides, Map<String, double>? tryPrices}) {
    final it = find(name);
    if (it == null) return null;
    final k = key(name);
    final per = _unitPrice(it, tryPrices?[k] ?? recipeOverrides?[k]);
    if (per == null) return null;
    final libCount = isCount(it['unit']?.toString());
    if (isCount(unit) != libCount) return null; // e.g. eggs in grams
    final amount = libCount ? qty * (baseOf(unit) ?? 1) : UnitConverter.toGrams(qty, unit);
    if (amount <= 0 && qty > 0) return null;
    return amount * per;
  }

  /// Calories of one line (ingredient calories are per 100 g, or per piece).
  double? lineCalories(String name, double qty, String unit) {
    final it = find(name);
    final cal = it == null ? null : _num(it['calories']);
    if (cal == null) return null;
    if (isCount(it!['unit']?.toString())) {
      return isCount(unit) ? qty * (baseOf(unit) ?? 1) * cal : null;
    }
    final g = UnitConverter.toGrams(qty, unit);
    return g > 0 ? g / 100 * cal : null;
  }

  // ---------------------------------------------------------------- recipes
  static List<RecipeLine> parseLines(String? ingredientsJson) {
    if (ingredientsJson == null || ingredientsJson.isEmpty || ingredientsJson == 'null') {
      return [];
    }
    try {
      final d = jsonDecode(ingredientsJson);
      if (d is! List) return [];
      return d
          .whereType<Map>()
          .map((m) => RecipeLine(
                m['name']?.toString() ?? '',
                _num(m['qty']) ?? 0,
                m['unit']?.toString() ?? '',
                legacyPrice: _num(m['price']),
              ))
          .where((l) => l.name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Recipes (not in Trash) that use this ingredient.
  List<RecipeUse> usedIn(String name) {
    final k = key(name);
    final out = <RecipeUse>[];
    _recipes.forEach((id, r) {
      if (r.deleted) return;
      for (final l in r.lines) {
        if (key(l.name) == k) {
          out.add(RecipeUse(id, r.name, l));
          break;
        }
      }
    });
    return out;
  }

  CostSummary summarize(int recipeId, List<RecipeLine> lines,
      {double factor = 1, Map<String, double>? tryPrices}) {
    double total = 0, kcal = 0, grams = 0;
    var missing = 0;
    for (final l in lines) {
      final q = l.qty * factor;
      final c = lineCost(l.name, q, l.unit,
          recipeOverrides: overrides[recipeId], tryPrices: tryPrices);
      if (c == null) {
        missing++;
      } else {
        total += c;
      }
      kcal += lineCalories(l.name, q, l.unit) ?? 0;
      grams += math.max(0, UnitConverter.toGrams(q, l.unit));
    }
    return CostSummary(total, missing, kcal, grams);
  }

  // ---------------------------------------------------------------- loading
  Future<void> load() async {
    final db = DatabaseHelper();
    items = (await db.getCachedIngredients())
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    overrides = await db.getAllOverrides();
    _recipes.clear();
    for (final r in await db.getRecipesForPriceBook()) {
      _recipes[r['id'] as int] = _RecipeLines(
        r['name']?.toString() ?? '',
        parseLines(r['ingredients']?.toString()),
        r['deleted_at'] != null,
        r['created_at']?.toString() ?? '',
      );
    }
    _loaded = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- editing
  static const _catGuess = {
    'salt': 'Spices', 'pepper': 'Spices', 'powder': 'Spices', 'spice': 'Spices',
    'oil': 'Oils', 'sauce': 'Sauces', 'mayo': 'Sauces', 'milk': 'Dairy',
    'cream': 'Dairy', 'cheese': 'Dairy', 'butter': 'Dairy', 'yogurt': 'Dairy',
    'yoghurt': 'Dairy', 'garlic': 'Produce', 'onion': 'Produce', 'lemon': 'Produce',
    'chicken': 'Meat', 'beef': 'Meat', 'mutton': 'Meat', 'fish': 'Seafood',
    'prawn': 'Seafood', 'rice': 'Grains', 'flour': 'Grains',
  };
  static String guessCategory(String name) {
    final k = key(name);
    for (final e in _catGuess.entries) {
      if (k.contains(e.key)) return e.value;
    }
    return 'Uncategorized';
  }

  static String libUnitFor(String recipeUnit) {
    final u = key(recipeUnit);
    if (isCount(u)) return 'pcs';
    if (u == 'ml' || u == 'l' || u == 'cup' || u == 'tbsp' || u == 'tsp') return 'L';
    return 'kg';
  }

  /// Adds a name used in a recipe to the Ingredients list ("No price yet").
  Future<Map<String, dynamic>> addFromRecipe(String name, String recipeUnit,
      {double? price}) async {
    final existing = find(name);
    if (existing != null) return existing;
    final data = <String, dynamic>{
      'name': name.trim(),
      'category': guessCategory(name),
      'unit': libUnitFor(recipeUnit),
      if (price != null) 'price': price,
    };
    final id = DateTime.now().microsecondsSinceEpoch ~/ 1000 + items.length;
    final local = {
      'id': id,
      'name': data['name'],
      'brand': null,
      'category': data['category'],
      'price': price,
      'unit': data['unit'],
      'calories': null,
      'auto_added': 1,
    };
    final db = DatabaseHelper();
    await db.saveLocalIngredient(local);
    await db.addPendingSync({
      'action': 'CREATE_INGREDIENT',
      'data': jsonEncode(data),
      'target_id': id,
      'created_at': DateTime.now().toIso8601String(),
    });
    items.add(local);
    // sent to the server by the next sync (one run, started by the caller)
    return local;
  }

  /// Records price history, keeps per-recipe prices on rename.
  Future<void> afterIngredientSaved(
      {String? oldName, required String newName, double? oldPrice, double? newPrice, String unit = 'kg'}) async {
    final db = DatabaseHelper();
    if (oldName != null && key(oldName) != key(newName)) {
      await db.renamePriceKey(key(oldName), key(newName));
      await renameInRecipes(oldName, newName);
    }
    if (newPrice != null && oldPrice != null && (newPrice - oldPrice).abs() > 1e-9) {
      await db.addPriceHistory(key(newName), oldPrice, newPrice, unit);
    }
    await load();
  }

  /// Moves every recipe line from one name to another (rename / merge).
  Future<int> renameInRecipes(String fromName, String toName) async {
    final db = DatabaseHelper();
    final from = key(fromName);
    var changed = 0;
    for (final r in await db.getRecipesForPriceBook()) {
      final raw = r['ingredients']?.toString();
      if (raw == null || raw.isEmpty) continue;
      try {
        final list = jsonDecode(raw);
        if (list is! List) continue;
        var hit = false;
        for (final m in list) {
          if (m is Map && key(m['name']?.toString()) == from) {
            m['name'] = toName;
            hit = true;
          }
        }
        if (!hit) continue;
        changed++;
        final full = await db.getRecipeById(r['id'] as int);
        if (full == null) continue;
        final updated = Map<String, dynamic>.from(full)..['ingredients'] = jsonEncode(list);
        await db.saveLocalRecipe(updated);
        await db.addPendingSync({
          'action': 'UPDATE_RECIPE',
          'target_id': r['id'],
          'data': jsonEncode({
            'name': full['name'],
            'brand_name': full['brand_name'] ?? '',
            'section_name': full['section_name'] ?? '',
            'ingredients': jsonEncode(list),
            'process': full['process'] ?? '',
            'visibility': full['visibility'] ?? 'private',
          }),
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('rename in recipe failed: $e');
      }
    }
    return changed;
  }

  /// Merge [from] into [into]: recipes switch over, then [from] is removed.
  Future<int> merge(Map<String, dynamic> from, Map<String, dynamic> into) async {
    final fromName = from['name'].toString(), intoName = into['name'].toString();
    final n = usedIn(fromName).length;
    final db = DatabaseHelper();
    await db.renamePriceKey(key(fromName), key(intoName));
    await renameInRecipes(fromName, intoName);
    if (_num(into['price']) == null && _num(from['price']) != null) {
      await ApiService().updateIngredient(into['id'] as int, {
        'name': intoName,
        'category': into['category'] ?? 'Uncategorized',
        'brand': into['brand'],
        'price': from['price'],
        'unit': from['unit'],
        'calories': into['calories'] ?? from['calories'],
      });
    }
    await ApiService().deleteIngredient(from['id'] as int);
    await load();
    return n;
  }

  Future<void> setRecipeOverride(int recipeId, String name, double? price) async {
    await DatabaseHelper().setOverride(recipeId, key(name), price);
    overrides = await DatabaseHelper().getAllOverrides();
    notifyListeners();
  }

  // ---------------------------------------------------------------- switch-over
  /// Move to the shared price list. Every recipe line that is not in
  /// Ingredients yet is added, keeping the price the recipe carried. When
  /// recipes carried different prices, the newest goes to Ingredients and the
  /// others keep theirs as "price for this recipe only" — so no cost changes.
  ///
  /// Runs for each recipe once (remembered by id), so recipes whose
  /// ingredients are downloaded later are handled on a later run.
  Future<MigrationReport?> migrateIfNeeded() async {
    final db = DatabaseHelper();
    final done = Set<int>.from(
        ((await db.getCachedData('pricebook_done_ids')) as List?)?.map((e) => e as int) ?? const []);
    await load();
    final todo = _recipes.entries
        .where((e) => !done.contains(e.key) && e.value.lines.isNotEmpty)
        .toList()
      ..sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt)); // newest first wins
    if (todo.isEmpty) return null;
    final firstRun = done.isEmpty;
    final report = MigrationReport();
    final seen = <String>{};
    for (final e in todo) {
      for (final l in e.value.lines) {
        final k = key(l.name);
        if (find(l.name) != null || seen.contains(k)) continue;
        seen.add(k);
        // old recipes stored prices per kg (or per piece) — same as the new list unit
        await addFromRecipe(l.name, l.unit,
            price: (l.legacyPrice ?? 0) > 0 ? l.legacyPrice : null);
        report.added++;
      }
    }
    // per-recipe prices where a recipe carried a different price than the list
    for (final e in todo) {
      for (final l in e.value.lines) {
        final it = find(l.name);
        final lp = l.legacyPrice;
        if (it == null || lp == null || lp <= 0) continue;
        if ((overrides[e.key] ?? const {}).containsKey(key(l.name))) continue;
        final listPerKg = _perKg(it);
        if (listPerKg == null) continue;
        if ((listPerKg - lp).abs() / lp > 0.005) {
          final base = baseOf(it['unit']?.toString() ?? 'kg') ?? 1000;
          final inListUnit = isCount(it['unit']?.toString()) ? lp * base : lp * base / 1000;
          await db.setOverride(e.key, key(l.name), inListUnit);
          report.differentPrices.add(key(l.name));
        }
      }
      done.add(e.key);
    }
    await db.cacheData('pricebook_done_ids', done.toList());
    if (report.added > 0) ApiService().syncPendingActions().catchError((_) {});
    await load();
    report.noPrice = needsPrice().length;
    report.duplicates = duplicatePairs().length;
    report.recipes = todo.length;
    report.firstRun = firstRun;
    return report;
  }

  /// Price per kg (or per piece) the old app expects inside recipe lines.
  double? legacyPerKg(String name) {
    final it = find(name);
    return it == null ? null : _perKg(it);
  }

  /// The list price expressed per kg (or per piece), like the old recipe price.
  double? _perKg(Map<String, dynamic> it) {
    final p = _num(it['price']);
    final base = baseOf(it['unit']?.toString() ?? 'kg');
    if (p == null || base == null || base == 0) return null;
    return isCount(it['unit']?.toString()) ? p / base : p / base * 1000;
  }
}

class RecipeLine {
  final String name;
  final double qty;
  final String unit;
  final double? legacyPrice;
  const RecipeLine(this.name, this.qty, this.unit, {this.legacyPrice});
}

class RecipeUse {
  final int recipeId;
  final String recipeName;
  final RecipeLine line;
  RecipeUse(this.recipeId, this.recipeName, this.line);
}

class _RecipeLines {
  final String name;
  final List<RecipeLine> lines;
  final bool deleted;
  final String createdAt;
  _RecipeLines(this.name, this.lines, this.deleted, this.createdAt);
}

class CostSummary {
  final double total;
  final int missing;
  final double calories;
  final double grams;
  const CostSummary(this.total, this.missing, this.calories, this.grams);
  double? get perKg => grams > 0 ? total / grams * 1000 : null;
  double? get kcalPer100g => grams > 0 ? calories / grams * 100 : null;
}

class MigrationReport {
  int added = 0;
  int recipes = 0;
  bool firstRun = false;
  final Set<String> differentPrices = {};
  int noPrice = 0;
  int duplicates = 0;
}
