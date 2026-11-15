import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/price_book.dart';
import 'ingredient_form_screen.dart';

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFFBF6E8);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);
const _accentSoft = Color(0xFFE6EFE9);
const _brown = Color(0xFF8D6E63);
const _warn = Color(0xFFA8650A);
const _warnSoft = Color(0xFFFBEFD9);

/// Cost & calories for one recipe, at the batch size chosen on the recipe page.
/// Prices come from the Ingredients list (or a price set for this recipe only).
class CostScreen extends StatefulWidget {
  final Recipe recipe;
  final double factor;
  const CostScreen({super.key, required this.recipe, this.factor = 1});

  @override
  State<CostScreen> createState() => _CostScreenState();
}

class _CostScreenState extends State<CostScreen> {
  final _book = PriceBook.instance;
  late final List<RecipeLine> _lines;
  bool _trying = false;
  final Map<String, double> _tryPrices = {};
  final Map<int, TextEditingController> _tryCtl = {};

  @override
  void initState() {
    super.initState();
    _lines = PriceBook.parseLines(widget.recipe.ingredients);
    _book.addListener(_redraw);
    if (!_book.loaded) _book.load();
  }

  @override
  void dispose() {
    _book.removeListener(_redraw);
    for (final c in _tryCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  int get _id => widget.recipe.id;
  double get _f => widget.factor;
  String _money(double v) => '${AppSettings.currency}${_group(v.round())}';
  String _group(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  String _qty(double q, String u) {
    if (PriceBook.isCount(u)) return ((q * 2).round() / 2).toString().replaceAll(RegExp(r'\.0$'), '');
    final v = q >= 100 ? q.roundToDouble() : q >= 10 ? (q * 10).round() / 10 : (q * 100).round() / 100;
    final s = v % 1 == 0 ? _group(v.toInt()) : v.toString();
    return s;
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final sum = _book.summarize(_id, _lines, factor: _f, tryPrices: _trying ? _tryPrices : null);
    final was = _book.summarize(_id, _lines, factor: _f);
    final plus = sum.missing > 0 ? '+' : '';
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
            child: Row(children: [
              IconButton(
                  tooltip: 'Back to recipe',
                  icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                  onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Cost & calories',
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk', fontSize: 20, fontWeight: FontWeight.w700, color: _fg)),
                  Text('${widget.recipe.name}${_f != 1 ? ' · ${_fmtF(_f)}× batch' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _muted)),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
              children: [
                _tiles(sum, plus),
                if (sum.missing > 0 && !_trying) _missingBanner(sum.missing),
                const SizedBox(height: 18),
                Row(children: [
                  const Text('Prices',
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk', fontSize: 17, fontWeight: FontWeight.w700, color: _fg)),
                  if (!_trying) ...[
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('tap a line to change its price',
                            style: TextStyle(fontSize: 12, color: _muted))),
                    OutlinedButton(
                      onPressed: _startTry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        backgroundColor: _accentSoft,
                        side: const BorderSide(color: _accent),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Try prices', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                const SizedBox(height: 8),
                if (_trying) _tryBar(),
                for (var k = 0; k < _lines.length; k++) _trying ? _tryRow(k) : _lineRow(k),
                const SizedBox(height: 14),
                _totalRow(sum, was, plus),
                const Padding(
                  padding: EdgeInsets.fromLTRB(2, 14, 2, 0),
                  child: Text(
                      'Prices come from your Ingredients list, so a price change there updates this page. '
                      'People you share the recipe with don’t see this page.',
                      style: TextStyle(fontSize: 12, height: 1.45, color: _muted)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  String _fmtF(double f) => (f * 100).round() % 100 == 0 ? f.round().toString() : f.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');

  Widget _tiles(CostSummary s, String plus) {
    Widget tile(String n, String l) => Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'SpaceGrotesk', fontSize: 20, fontWeight: FontWeight.w600, color: _fg)),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        );
    final perKg = s.perKg, kc100 = s.kcalPer100g;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.3,
      children: [
        tile('${_money(s.total)}$plus', 'batch cost'),
        tile(perKg == null ? '—' : '${_money(perKg)}$plus', 'per kg'),
        tile(s.calories > 0 ? _group(s.calories.round()) : '—', 'calories'),
        tile(kc100 == null || s.calories == 0 ? '—' : kc100.round().toString(), 'kcal / 100 g'),
      ],
    );
  }

  Widget _missingBanner(int n) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(color: _warnSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: _warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$n ingredient${n == 1 ? ' has' : 's have'} no price',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ', so the cost is incomplete.'),
                ]),
                style: const TextStyle(fontSize: 13, height: 1.35, color: _fg)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _addFirstMissing,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Add price'),
          ),
        ]),
      );

  Widget _lineRow(int k) {
    final l = _lines[k];
    final q = l.qty * _f;
    final key = PriceBook.key(l.name);
    final custom = _book.overrides[_id]?[key];
    final it = _book.find(l.name);
    final cost = _book.lineCost(l.name, q, l.unit, recipeOverrides: _book.overrides[_id]);
    final kc = _book.lineCalories(l.name, q, l.unit);
    final price = custom ?? (it?['price'] as num?)?.toDouble();
    return InkWell(
      onTap: () => _openLineSheet(k),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: const TextStyle(fontSize: 15, color: _fg)),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${_qty(q, l.unit)} ${l.unit} · '),
                  if (price == null)
                    const TextSpan(
                        text: 'no price', style: TextStyle(color: _warn, fontWeight: FontWeight.w600))
                  else ...[
                    TextSpan(text: '${_money(price)}/${it?['unit'] ?? 'kg'}'),
                    if (custom != null)
                      const TextSpan(
                          text: '  custom',
                          style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
                  ],
                  if (kc != null && kc > 0) TextSpan(text: ' · ${_group(kc.round())} kcal'),
                ]),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Text(cost == null ? '—' : _money(cost),
              style: TextStyle(
                  fontFamily: cost == null ? null : 'SpaceGrotesk',
                  fontSize: cost == null ? 13 : 15,
                  fontWeight: FontWeight.w600,
                  color: cost == null ? _warn : _fg)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------- try prices
  void _startTry() {
    setState(() {
      _trying = true;
      _tryPrices.clear();
      for (var k = 0; k < _lines.length; k++) {
        final l = _lines[k];
        final custom = _book.overrides[_id]?[PriceBook.key(l.name)];
        final p = custom ?? (_book.find(l.name)?['price'] as num?)?.toDouble();
        _tryCtl[k]?.dispose();
        _tryCtl[k] = TextEditingController(text: p == null ? '' : _plain(p));
      }
    });
  }

  String _plain(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  void _onTry(int k, String v) {
    final l = _lines[k];
    final key = PriceBook.key(l.name);
    final x = double.tryParse(v.trim());
    final base = _book.overrides[_id]?[key] ?? (_book.find(l.name)?['price'] as num?)?.toDouble();
    setState(() {
      if (x == null || x < 0 || x == base) {
        _tryPrices.remove(key);
      } else {
        _tryPrices[key] = x;
      }
    });
  }

  Widget _tryBar() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(color: _fg, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Trying prices',
              style: TextStyle(color: _bg, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(
              _tryPrices.isEmpty
                  ? 'Change any price below · nothing is saved'
                  : '${_tryPrices.length} price${_tryPrices.length == 1 ? '' : 's'} changed · not saved',
              style: TextStyle(color: _bg.withOpacity(0.8), fontSize: 12)),
          const SizedBox(height: 9),
          Row(children: [
            _barBtn('Reset', () => _startTry()),
            const SizedBox(width: 6),
            _barBtn('Keep for this recipe', _tryPrices.isEmpty ? null : _keepTry),
            const SizedBox(width: 6),
            _barBtn('Done', () => setState(() {
                  _trying = false;
                  _tryPrices.clear();
                }), filled: true),
          ]),
        ]),
      );

  Widget _barBtn(String label, VoidCallback? onTap, {bool filled = false}) => Expanded(
        child: SizedBox(
          height: 38,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: filled ? _bg : Colors.transparent,
              foregroundColor: filled ? _fg : _bg,
              disabledForegroundColor: _bg.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: filled ? _bg : _bg.withOpacity(0.25))),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _tryRow(int k) {
    final l = _lines[k];
    final q = l.qty * _f;
    final key = PriceBook.key(l.name);
    final changed = _tryPrices.containsKey(key);
    final cost = _book.lineCost(l.name, q, l.unit,
        recipeOverrides: _book.overrides[_id], tryPrices: _tryPrices);
    final unit = _book.find(l.name)?['unit'] ?? PriceBook.libUnitFor(l.unit);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: _line)),
        color: changed ? _accentSoft : null,
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, style: const TextStyle(fontSize: 14.5, color: _fg)),
            Text('${_qty(q, l.unit)} ${l.unit}', style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        Container(
          width: 112,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: changed ? _accent : _line),
          ),
          child: Row(children: [
            Text(AppSettings.currency, style: const TextStyle(fontSize: 12, color: _muted)),
            Expanded(
              child: TextField(
                controller: _tryCtl[k],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                onChanged: (v) => _onTry(k, v),
                // select the whole number so typing replaces it
                onTap: () {
                  final c = _tryCtl[k]!;
                  c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
                },
                style: const TextStyle(
                    fontFamily: 'SpaceGrotesk', fontSize: 15, fontWeight: FontWeight.w600, color: _fg),
                decoration: const InputDecoration(
                    isDense: true, border: InputBorder.none, hintText: 'price',
                    hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w400, color: _muted),
                    contentPadding: EdgeInsets.symmetric(vertical: 9)),
              ),
            ),
            Text('/$unit', style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        SizedBox(
          width: 64,
          child: Text(cost == null ? '—' : _money(cost),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cost == null ? _warn : _accent)),
        ),
      ]),
    );
  }

  Future<void> _keepTry() async {
    final n = _tryPrices.length;
    for (final e in _tryPrices.entries) {
      final line = _lines.firstWhere((l) => PriceBook.key(l.name) == e.key);
      await _book.setRecipeOverride(_id, line.name, e.value);
    }
    if (!mounted) return;
    setState(() {
      _trying = false;
      _tryPrices.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Kept $n price${n == 1 ? '' : 's'} for this recipe only'),
    ));
  }

  Widget _totalRow(CostSummary sum, CostSummary was, String plus) {
    final diff = sum.total - was.total;
    final showWas = _trying && _tryPrices.isNotEmpty && diff.abs() >= 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: _brown, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_trying ? 'Cost with these prices' : 'Estimated cost',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            if (showWas)
              Text('was ${_money(was.total)} · ${diff > 0 ? '+' : '−'}${_money(diff.abs())}',
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
          ]),
        ),
        Text('${_money(sum.total)}$plus',
            style: const TextStyle(
                fontFamily: 'SpaceGrotesk', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    );
  }

  // ------------------------------------------------------------- line sheet
  Future<void> _openIngredient(RecipeLine l) async {
    var it = _book.find(l.name);
    it ??= await _book.addFromRecipe(l.name, l.unit);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IngredientFormScreen(ingredient: Ingredient.fromJson(it!))));
    await _book.load();
  }

  Future<void> _addFirstMissing() async {
    for (final l in _lines) {
      if (_book.lineCost(l.name, l.qty * _f, l.unit, recipeOverrides: _book.overrides[_id]) == null) {
        await _openIngredient(l);
        return;
      }
    }
  }

  Future<void> _openLineSheet(int k) async {
    final l = _lines[k];
    final key = PriceBook.key(l.name);
    final it = _book.find(l.name);
    final custom = _book.overrides[_id]?[key];
    final used = _book.usedIn(l.name).length;
    final ctl = TextEditingController(text: custom == null ? '' : _plain(custom));
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.name,
                style: const TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.w700, color: _fg)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                if (it != null && it['price'] != null) ...[
                  const TextSpan(text: 'Price list: '),
                  TextSpan(
                      text: '${_money((it['price'] as num).toDouble())}/${it['unit'] ?? 'kg'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: _fg)),
                ] else
                  const TextSpan(
                      text: 'No price in your Ingredients yet',
                      style: TextStyle(color: _warn, fontWeight: FontWeight.w600)),
                TextSpan(text: ' · used in $used recipe${used == 1 ? '' : 's'}'),
              ]),
              style: const TextStyle(fontSize: 14, color: _muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'open'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                backgroundColor: _accentSoft,
                side: const BorderSide(color: _accent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Edit in Ingredients (all recipes)', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 18),
            const Text('PRICE FOR THIS RECIPE ONLY',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: _muted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ctl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'Same as price list',
                    filled: true,
                    fillColor: _surface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('per ${it?['unit'] ?? PriceBook.libUnitFor(l.unit)}',
                  style: const TextStyle(fontSize: 13, color: _muted)),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'set'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Set'),
              ),
            ]),
            if (custom != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, 'remove'),
                  child: const Text('Use the price list again',
                      style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (res == 'open') {
      await _openIngredient(l);
    } else if (res == 'set') {
      final v = double.tryParse(ctl.text.trim());
      if (v == null || v <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a price'), behavior: SnackBarBehavior.floating));
      } else {
        if (it == null) await _book.addFromRecipe(l.name, l.unit);
        await _book.setRecipeOverride(_id, l.name, v);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Price set for this recipe only'), behavior: SnackBarBehavior.floating));
        }
      }
    } else if (res == 'remove') {
      await _book.setRecipeOverride(_id, l.name, null);
    }
    ctl.dispose();
  }
}
