import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import '../database_helper.dart';
import '../utils/unit_converter.dart';
import '../perf.dart';

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

  // Built once per load(), so lookups never walk the whole list.
  final Map<String, Map<String, dynamic>> _byKey = {};
  final Map<String, List<RecipeUse>> _uses = {};
  List<List<Map<String, dynamic>>>? _dupCache;
  List<MissingName>? _missingCache;

  bool _loaded = false;
  bool get loaded => _loaded;

  // ---------------------------------------------------------------- names
  static final _spaces = RegExp(r'\s+');
  static final _brackets = RegExp(r'\(.*?\)');
  static final _notWord = RegExp(r'[^a-z0-9 ]');

  /// The name without brackets and punctuation: "Almond (fine)." -> "almond".
  static String core(String k) =>
      k.replaceAll(_brackets, '').replaceAll(_notWord, '').replaceAll(_spaces, ' ').trim();
  static String key(String? name) =>
      (name ?? '').toLowerCase().replaceAll(_spaces, ' ').trim();

  Map<String, dynamic>? find(String? name) {
    final k = key(name);
    return k.isEmpty ? null : _byKey[k];
  }

  void _indexItems() {
    _byKey.clear();
    for (final it in items) {
      _byKey.putIfAbsent(key(it['name']?.toString()), () => it);
    }
    _dupCache = null;
    _missingCache = null;
  }

  /// Letters to change to turn [a] into [b]; stops early once it is over 2.
  static int _editDistance(String a, String b) {
    if ((a.length - b.length).abs() > 2) return 9;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = i;
      final ca = a.codeUnitAt(i - 1);
      for (var j = 1; j <= b.length; j++) {
        var v = prev[j - 1] + (ca == b.codeUnitAt(j - 1) ? 0 : 1);
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > 2) return 9;
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
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
    final k = key(name);
    if (k.isEmpty) return null;
    for (final e in _byKey.entries) {
      if (e.key.isEmpty || e.key[0] != k[0]) continue;
      if (looksSame(k, e.key) || looksSame(e.key, k)) return e.value;
    }
    return null;
  }

  /// Pairs that look like duplicates (shorter/typo first, longer second).
  /// Worked out once per change to the list; names are only compared with
  /// names that start with the same letter.
  List<List<Map<String, dynamic>>> duplicatePairs() {
    if (_dupCache != null) return _dupCache!;
    final groups = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final e in _byKey.entries) {
      if (e.key.isNotEmpty) groups.putIfAbsent(e.key[0], () => []).add(e);
    }
    final out = <List<Map<String, dynamic>>>[];
    final paired = <String>{};
    for (final g in groups.values) {
      g.sort((x, y) => x.key.length.compareTo(y.key.length));
      for (var i = 0; i < g.length; i++) {
        if (paired.contains(g[i].key)) continue;
        for (var j = i + 1; j < g.length; j++) {
          if (paired.contains(g[j].key)) continue;
          final ci = core(g[i].key), cj = core(g[j].key);
          if ((ci.isNotEmpty && ci == cj) || looksSame(g[i].key, g[j].key)) {
            out.add([g[i].value, g[j].value]);
            paired..add(g[i].key)..add(g[j].key);
            break;
          }
        }
      }
    }
    return _dupCache = out;
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
  List<RecipeUse> usedIn(String name) => _uses[key(name)] ?? const [];

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
  Future<void> load() => perfAsync('pricebook load', _load);

  Future<void> _load() async {
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
    _uses.clear();
    _recipes.forEach((id, r) {
      if (r.deleted) return;
      final seen = <String>{};
      for (final l in r.lines) {
        final k = key(l.name);
        if (seen.add(k)) _uses.putIfAbsent(k, () => []).add(RecipeUse(id, r.name, l));
      }
    });
    _indexItems();
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
    _byKey[key(local['name']?.toString())] = local;
    _dupCache = null;
    _missingCache = null;
    // sent to the server by the next sync (one run, started by the caller)
    return local;
  }

  /// Records price history, keeps per-recipe prices on rename.
  Future<void> afterIngredientSaved(
      {String? oldName, required String newName, double? oldPrice, double? newPrice, String unit = 'kg'}) async {
    final db = DatabaseHelper();
    if (oldName != null && key(oldName) != key(newName)) {
      await db.renamePriceKey(key(oldName), key(newName));
      await db.renameLinesInRecipes({key(oldName): newName});
      await db.addPendingSync({
        'action': 'MERGE_INGREDIENT',
        'target_id': 0,
        'data': jsonEncode({'from_name': oldName, 'into_name': newName}),
        'created_at': DateTime.now().toIso8601String(),
      });
      ApiService().syncPendingActions().catchError((_) {});
    }
    if (newPrice != null && oldPrice != null && (newPrice - oldPrice).abs() > 1e-9) {
      await db.addPriceHistory(key(newName), oldPrice, newPrice, unit);
    }
    await load();
  }

  /// Merge [from] into [into]: recipes switch over, [into] keeps [from]'s
  /// price if it had none, then [from] is removed. Done on the phone in one
  /// step; the server gets a single "merge" request in the background.
  Future<int> merge(Map<String, dynamic> from, Map<String, dynamic> into) =>
      mergeMany([(from, into)]);

  /// Several merges in one go (one database transaction, one reload).
  /// Returns how many recipe lines moved.
  Future<int> mergeMany(List<(Map<String, dynamic>, Map<String, dynamic>)> pairs) async {
    if (pairs.isEmpty) return 0;
    final db = DatabaseHelper();
    final renames = <String, String>{};
    var moved = 0;
    final now = DateTime.now().toIso8601String();
    for (final (from, into) in pairs) {
      final fromName = from['name'].toString(), intoName = into['name'].toString();
      if (key(fromName) == key(intoName)) continue;
      moved += usedIn(fromName).length;
      renames[key(fromName)] = intoName;
      await db.renamePriceKey(key(fromName), key(intoName));
      if (_num(into['price']) == null && _num(from['price']) != null) {
        await db.updateLocalIngredient(into['id'] as int, {
          'price': _num(from['price']),
          'unit': from['unit'],
        });
        into['price'] = from['price']; // a later pair into the same item sees it
      }
      await db.deleteLocalIngredient(from['id'] as int);
      await db.addPendingSync({
        'action': 'MERGE_INGREDIENT',
        'target_id': from['id'] as int,
        'data': jsonEncode({'from_name': fromName, 'into_name': intoName}),
        'created_at': now,
      });
    }
    await db.renameLinesInRecipes(renames);
    await load();
    ApiService().syncPendingActions().catchError((_) {});
    return moved;
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
        .toList();
    if (todo.isEmpty) return null;
    final report = MigrationReport()..firstRun = done.isEmpty;
    // Names that are not in Ingredients are NOT added here any more: the
    // Ingredients tab lists them for review ("names in your recipes").
    // Only a recipe that carried a different price than the list keeps it
    // as "price for this recipe only", so no cost changes.
    final newOverrides = <(int, String, double)>[];
    for (final e in todo) {
      for (final l in e.value.lines) {
        final it = find(l.name);
        final lp = l.legacyPrice;
        if (it == null || lp == null || lp <= 0) continue;
        if ((overrides[e.key] ?? const {}).containsKey(key(l.name))) continue;
        final listPerKg = _perKg(it);
        if (listPerKg == null || (listPerKg - lp).abs() / lp <= 0.005) continue;
        final base = baseOf(it['unit']?.toString() ?? 'kg') ?? 1000;
        newOverrides.add((e.key, key(l.name),
            isCount(it['unit']?.toString()) ? lp * base : lp * base / 1000));
        report.differentPrices.add(key(l.name));
      }
      done.add(e.key);
    }
    await db.setOverrides(newOverrides);
    await db.cacheData('pricebook_done_ids', done.toList());
    if (newOverrides.isNotEmpty) overrides = await db.getAllOverrides();
    report.recipes = todo.length;
    return report;
  }

  // ---------------------------------------------------------------- names in recipes
  /// Names used in recipes that are not in Ingredients, grouped so that
  /// "Salt", "salt." and "sault" are one row. Each group suggests a name
  /// (the most used spelling) or an ingredient already in the list.
  List<MissingName> missingFromList() {
    if (_missingCache != null) return _missingCache!;
    final counts = <String, int>{}, spelling = <String, String>{}, unit = <String, String>{};
    final price = <String, double>{}, priceAt = <String, String>{};
    _uses.forEach((k, list) {
      if (k.isEmpty || _byKey.containsKey(k)) return;
      counts[k] = list.length;
      spelling[k] = list.first.line.name.trim().replaceAll(RegExp(r'[.,;]+$'), '');
      unit[k] = list.first.line.unit;
      for (final u in list) {
        final lp = u.line.legacyPrice;
        final at = _recipes[u.recipeId]?.createdAt ?? '';
        if (lp != null && lp > 0 && at.compareTo(priceAt[k] ?? '') >= 0) {
          price[k] = lp;
          priceAt[k] = at;
        }
      }
    });
    // group: same name without punctuation/brackets, or "looks the same"
    final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final groups = <MissingName>[];
    final byCore = <String, MissingName>{};
    final byLetter = <String, List<(String, MissingName)>>{};
    for (final k in keys) {
      final c = core(k);
      var g = byCore[c];
      if (g == null && c.length >= 3) {
        for (final (oc, other) in byLetter[c[0]] ?? const <(String, MissingName)>[]) {
          if (looksSame(c, oc) || looksSame(oc, c)) {
            g = other;
            break;
          }
        }
      }
      if (g == null) {
        g = MissingName(spelling[k]!, libUnitFor(unit[k]!));
        groups.add(g);
        if (c.isNotEmpty) byLetter.putIfAbsent(c[0], () => []).add((c, g));
      }
      byCore.putIfAbsent(c, () => g!);
      g.keys.add(k);
      g.spellings.add(spelling[k]!);
      g.recipeCount += counts[k]!;
      if (price[k] != null && g.price == null) g.price = price[k];
    }
    final listByCore = <String, Map<String, dynamic>>{};
    _byKey.forEach((k, it) => listByCore.putIfAbsent(core(k), () => it));
    for (final g in groups) {
      for (final k in g.keys) {
        final m = listByCore[core(k)] ?? similar(k);
        if (m != null) {
          g.matches = m;
          break;
        }
      }
    }
    return _missingCache = groups;
  }

  /// Adds the picked names in one step. A group that matches an existing
  /// ingredient is merged into it instead of being added again.
  Future<int> addMissing(List<MissingName> picks) async {
    if (picks.isEmpty) return 0;
    final db = DatabaseHelper();
    final renames = <String, String>{};
    final toCreate = <Map<String, dynamic>>[];
    final merges = <Map<String, String>>[];
    var base = DateTime.now().millisecondsSinceEpoch;
    for (final g in picks) {
      final target = g.useExisting && g.matches != null ? g.matches!['name'].toString() : g.name.trim();
      if (!(g.useExisting && g.matches != null)) {
        toCreate.add({
          'id': base++,
          'name': target,
          'category': guessCategory(target),
          'unit': g.unit,
          // old recipe prices were per kg / per piece, the same number as the list unit
          'price': g.price,
          'auto_added': 1,
        });
      }
      for (final k in g.keys) {
        if (k == key(target)) continue;
        renames[k] = target;
        merges.add({'from_name': k, 'into_name': target});
      }
    }
    await db.saveIngredientsAndRename(toCreate, renames);
    final now = DateTime.now().toIso8601String();
    if (toCreate.isNotEmpty) {
      await db.addPendingSync({
        'action': 'CREATE_INGREDIENTS',
        'target_id': 0,
        'data': jsonEncode({'items': toCreate}),
        'created_at': now,
      });
    }
    for (final m in merges) {
      await db.addPendingSync({
        'action': 'MERGE_INGREDIENT',
        'target_id': 0,
        'data': jsonEncode(m),
        'created_at': now,
      });
    }
    await load();
    ApiService().syncPendingActions().catchError((_) {});
    return picks.length;
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

/// A name used in recipes that is not in the Ingredients list yet.
class MissingName {
  String name; // suggested name to add
  final String unit; // kg, L or pcs
  final Set<String> keys = {}; // every spelling, as keys
  final List<String> spellings = [];
  int recipeCount = 0;
  double? price; // newest price a recipe carried
  Map<String, dynamic>? matches; // an ingredient already in the list that looks the same
  bool useExisting = true; // merge into [matches] instead of adding
  MissingName(this.name, this.unit);
}
