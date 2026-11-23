import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/price_book.dart';
import 'recipe_detail_screen.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _warn = Color(0xFFA8650A);
const _warnSoft = Color(0xFFFBEFD9);
const _red = Color(0xFFC0392B);
const _green = Color(0xFF2F9E5E);

class IngredientFormScreen extends StatefulWidget {
  final Ingredient? ingredient;
  const IngredientFormScreen({super.key, this.ingredient});

  @override
  State<IngredientFormScreen> createState() => _IngredientFormScreenState();
}

class _IngredientFormScreenState extends State<IngredientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  bool _isLoading = false;

  late TextEditingController _nameController;
  late TextEditingController _brandController;
  late TextEditingController _priceController;
  late TextEditingController _caloriesController;

  String _selectedCategory = 'Dry Goods';
  String _selectedUnit = 'kg';

  final List<String> _categories = [
    'Dairy', 'Produce', 'Meat', 'Seafood', 'Spices', 'Oils', 'Sauces',
    'Dry Goods', 'Beverages', 'In-House'
  ];
  final List<String> _units = ['kg', 'g', 'L', 'ml', 'pcs', 'dozen'];

  final _book = PriceBook.instance;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.ingredient?.name ?? '');
    _brandController =
        TextEditingController(text: widget.ingredient?.brand ?? '');
    String plain(double? v) => v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toString());
    _priceController = TextEditingController(text: plain(widget.ingredient?.price));
    _caloriesController = TextEditingController(text: plain(widget.ingredient?.calories));

    if (widget.ingredient != null) {
      final c = widget.ingredient!.category;
      if (c.trim().isNotEmpty && !_categories.contains(c)) _categories.add(c);
      if (c.trim().isNotEmpty) _selectedCategory = c;
      final u = widget.ingredient!.unit;
      if (u != null && !_units.contains(u) && u.trim().isNotEmpty) _units.add(u);
      if (u != null && _units.contains(u)) _selectedUnit = u;
      DatabaseHelper()
          .getPriceHistory(PriceBook.key(widget.ingredient!.name))
          .then((h) {
        if (mounted) setState(() => _history = h);
      });
    }
    _priceController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final data = {
      'name': _nameController.text,
      'brand': _brandController.text,
      'category': _selectedCategory,
      'price': _priceController.text,
      'unit': _selectedUnit,
      'calories': _caloriesController.text,
    };

    final newName = _nameController.text.trim();
    final clash = _book.find(newName);
    if (clash != null && clash['id'] != widget.ingredient?.id) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('“${clash['name']}” is already in your list'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    String? error;
    if (widget.ingredient == null) {
      error = await _apiService.createIngredient(data);
    } else {
      error = await _apiService.updateIngredient(widget.ingredient!.id, data);
    }
    if (error == null) {
      await _book.afterIngredientSaved(
        oldName: widget.ingredient?.name,
        newName: newName,
        oldPrice: widget.ingredient?.price,
        newPrice: double.tryParse(_priceController.text.trim()),
        unit: _selectedUnit,
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      final used = widget.ingredient == null ? 0 : _book.usedIn(newName).length;
      final priceChanged = widget.ingredient != null &&
          widget.ingredient!.price != double.tryParse(_priceController.text.trim());
      if (priceChanged && used > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(widget.ingredient!.price == null
              ? 'Price added · $used recipe${used == 1 ? ' now has' : 's now have'} a full cost'
              : 'Price updated in $used recipe${used == 1 ? '' : 's'}'),
        ));
      }
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: const Color(0xFFC0392B),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.ingredient != null;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(isEdit ? 'Edit ingredient' : 'New ingredient',
                      style: const TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  children: [
                    if (isEdit && widget.ingredient!.price == null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: _warnSoft,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                            'No price yet. Add one so recipe costs are complete.',
                            style: TextStyle(fontSize: 13, height: 1.4, color: _fg)),
                      ),
                    _field(
                      controller: _nameController,
                      label: 'Name',
                      hint: 'e.g. Mayonnaise',
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _label('Category'),
                    const SizedBox(height: 7),
                    _dropdown(),
                    const SizedBox(height: 16),
                    _field(
                      controller: _brandController,
                      label: 'Brand (optional)',
                      hint: 'e.g. Delicio',
                    ),
                    const SizedBox(height: 16),
                    _label('Measured in'),
                    const SizedBox(height: 7),
                    _unitSeg(),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            controller: _priceController,
                            label: 'Price (per $_selectedUnit)',
                            hint: '${AppSettings.currency} 0',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            controller: _caloriesController,
                            label: 'Calories',
                            hint: 'cal / 100g',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    if (isEdit) ..._extras(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3))
                  : Text(
                      widget.ingredient == null
                          ? 'Save ingredient'
                          : 'Save changes',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: _muted));

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, color: _fg),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _muted, fontSize: 15),
            filled: true,
            fillColor: _surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      items: _categories
          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
          .toList(),
      onChanged: (val) => setState(() => _selectedCategory = val!),
      icon: const Icon(Icons.expand_more_rounded, color: _muted),
      dropdownColor: _surface,
      style: const TextStyle(fontSize: 15, color: _fg),
      decoration: InputDecoration(
        filled: true,
        fillColor: _surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _unitSeg() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: _units.map((u) {
          final on = _selectedUnit == u;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedUnit = u),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(u,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: on ? Colors.white : _muted)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------- extras
  List<Widget> _extras() {
    final it = widget.ingredient!;
    final used = _book.usedIn(it.name);
    return [
      _impact(it, used),
      if (used.isNotEmpty) ...[
        _blockTitle('Used in ${used.length} recipe${used.length == 1 ? '' : 's'}'),
        _box(used.map((u) => InkWell(
              onTap: () => _openRecipe(u.recipeId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  Expanded(
                      child: Text(u.recipeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: _fg))),
                  Text('${_fmtQty(u.line.qty)} ${u.line.unit}',
                      style: const TextStyle(fontSize: 13, color: _muted)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: _muted),
                ]),
              ),
            ))),
      ],
      if (_history.isNotEmpty) ...[
        _blockTitle('Price history'),
        _box(_history.map((h) {
          final from = (h['old_price'] as num?)?.toDouble();
          final to = (h['new_price'] as num?)?.toDouble() ?? 0;
          final pct = from == null || from == 0 ? null : (to - from) / from * 100;
          final d = DateTime.tryParse(h['changed_at']?.toString() ?? '');
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                  child: Text(d == null ? '' : _date(d),
                      style: const TextStyle(fontSize: 13, color: _fg))),
              if (from != null)
                Text(_money(from),
                    style: const TextStyle(
                        fontSize: 13,
                        color: _muted,
                        decoration: TextDecoration.lineThrough)),
              const Text('  →  ', style: TextStyle(fontSize: 13, color: _muted)),
              Text(_money(to),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _fg)),
              SizedBox(
                width: 52,
                child: Text(
                    pct == null ? '' : '${pct > 0 ? '+' : ''}${pct.round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: pct != null && pct > 0 ? _red : _green)),
              ),
            ]),
          );
        })),
      ],
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton(
          onPressed: _askDelete,
          style: OutlinedButton.styleFrom(
            foregroundColor: _red,
            side: const BorderSide(color: _line),
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Delete ingredient',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    ];
  }

  /// Live preview: what the new price does to every recipe that uses it.
  Widget _impact(Ingredient it, List<RecipeUse> used) {
    final v = double.tryParse(_priceController.text.trim());
    if (v == null || v <= 0 || v == it.price || _selectedUnit != (it.unit ?? _selectedUnit)) {
      return const SizedBox.shrink();
    }
    final k = PriceBook.key(it.name);
    final rows = <MapEntry<String, double>>[];
    var ownPrice = 0;
    for (final u in used) {
      if ((_book.overrides[u.recipeId] ?? const {}).containsKey(k)) {
        ownPrice++;
        continue;
      }
      final before = _book.lineCost(it.name, u.line.qty, u.line.unit) ?? 0;
      final after = _book.lineCost(it.name, u.line.qty, u.line.unit, tryPrices: {k: v}) ?? 0;
      if ((after - before).abs() >= 0.5) rows.add(MapEntry(u.recipeName, after - before));
    }
    if (rows.isEmpty && ownPrice == 0) return const SizedBox.shrink();
    final total = rows.fold<double>(0, (t, e) => t + e.value);
    String signed(double d) => '${d > 0 ? '+' : '−'}${AppSettings.currency}${d.abs().round()}';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warn),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: _warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'This changes the cost of '),
              TextSpan(
                  text: '${rows.length} recipe${rows.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' (${signed(total)} total)'),
            ]), style: const TextStyle(fontSize: 13, height: 1.35, color: _fg)),
          ),
        ]),
        const SizedBox(height: 6),
        ...rows.map((e) => Container(
              padding: const EdgeInsets.fromLTRB(26, 7, 0, 7),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
              child: Row(children: [
                Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, color: _fg))),
                Text(signed(e.value),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: e.value > 0 ? _red : _green)),
              ]),
            )),
        if (ownPrice > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(26, 7, 0, 7),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
            child: Text(
                '$ownPrice recipe${ownPrice == 1 ? ' keeps its' : 's keep their'} own price for this (set on the recipe’s Cost page), so ${ownPrice == 1 ? 'it doesn’t' : 'they don’t'} change.',
                style: const TextStyle(fontSize: 12, height: 1.35, color: _muted)),
          ),
      ]),
    );
  }

  Future<void> _openRecipe(int recipeId) async {
    final row = await DatabaseHelper().getRecipeById(recipeId);
    if (row == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(recipe: Recipe.fromJson(row))));
  }

  Future<void> _askDelete() async {
    final it = widget.ingredient!;
    final used = _book.usedIn(it.name);
    final choice = await showModalBottomSheet<String>(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Delete “${it.name}”?',
                        style: const TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _fg)),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(ctx),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (used.isEmpty)
                Text(
                    'It isn’t used in any recipe. Its price${_history.isNotEmpty ? ' and price history' : ''} will be removed.',
                    style: const TextStyle(fontSize: 14, height: 1.45, color: _fg))
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: _warnSoft, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                      'Used in ${used.length} recipe${used.length == 1 ? '' : 's'}: '
                      '${used.take(3).map((u) => u.recipeName).join(', ')}'
                      '${used.length > 3 ? ' and ${used.length - 3} more' : ''}.\n'
                      'Those recipes keep the amount, but their cost will show “no price”.',
                      style: const TextStyle(fontSize: 14, height: 1.45, color: _fg)),
                ),
              const SizedBox(height: 16),
              _sheetBtn(used.isEmpty ? 'Delete' : 'Delete anyway', _red, Colors.white,
                  () => Navigator.pop(ctx, 'delete')),
              const SizedBox(height: 8),
              _sheetBtn('Cancel', _surface, _fg, () => Navigator.pop(ctx), border: true),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice != 'delete') return;
    setState(() => _isLoading = true);
    final backup = {
      'name': it.name,
      'brand': it.brand ?? '',
      'category': it.category,
      'price': it.price?.toString() ?? '',
      'unit': it.unit ?? 'kg',
      'calories': it.calories?.toString() ?? '',
    };
    final error = await _apiService.deleteIngredient(it.id);
    await _book.load();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error), behavior: SnackBarBehavior.floating));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Text('“${it.name}” deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await ApiService().createIngredient(backup);
          await PriceBook.instance.load();
        },
      ),
    ));
    Navigator.of(context).pop(true);
  }

  Widget _sheetBtn(String label, Color bg, Color fg, VoidCallback onTap,
          {bool border = false}) =>
      SizedBox(
        height: 50,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            elevation: 0,
            side: border ? const BorderSide(color: _line) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _blockTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: _muted)),
      );

  Widget _box(Iterable<Widget> rows) {
    final list = rows.toList();
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: _line),
          list[i],
        ]
      ]),
    );
  }


  String _money(double v) => '${AppSettings.currency}${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}';
  String _fmtQty(double q) => q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
  String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    return '${d.day} ${m[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
  }
}
