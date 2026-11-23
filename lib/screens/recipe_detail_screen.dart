import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../models/recipe.dart';
import '../database_helper.dart';
import '../sync_provider.dart';
import '../utils/unit_converter.dart';
import 'recipe_form_screen.dart';
import 'cost_screen.dart';
import '../services/price_book.dart';
import 'recipe_share_screen.dart';
import 'export_screen.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);
const _brown = Color(0xFF6E2C1E);

/// Returned by [RecipeDetailScreen] when the recipe was moved to Trash,
/// so the list can remove it and offer Undo.
class RecipeDeleted {
  final int id;
  final String name;
  const RecipeDeleted(this.id, this.name);
}

class RecipeDetailScreen extends StatefulWidget {
  final Recipe recipe;
  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  final _apiService = ApiService();
  late Recipe _recipe;
  double _batchMultiplier = 1.0;
  List<Map<String, dynamic>> _parsedIngredients = [];
  int? _currentUserId;
  bool _isLoading = false;
  bool _isFetchingDetails = true;
  late TextEditingController _batchController;
  final _batchFocus = FocusNode();
  bool _weightMode = false;
  String _wtUnit = 'kg';
  late TextEditingController _wtController;
  final _wtFocus = FocusNode();

  List<String> _getSteps() {
    return _recipe.process
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _recipe = widget.recipe;
    _batchController =
        TextEditingController(text: _formatBatch(_batchMultiplier));
    _wtController = TextEditingController();
    // tapping the number selects it so typing replaces it cleanly without blanking it out
    _batchFocus.addListener(() {
      if (_batchFocus.hasFocus) {
        _batchController.selection = TextSelection(
            baseOffset: 0, extentOffset: _batchController.text.length);
      } else if (_batchController.text.trim().isEmpty) {
        _batchController.text = _formatBatch(_batchMultiplier);
      }
    });
    _wtFocus.addListener(() {
      if (_wtFocus.hasFocus) {
        _wtController.selection = TextSelection(
            baseOffset: 0, extentOffset: _wtController.text.length);
      } else {
        _syncWeightInput();
      }
    });
    _parseIngredients();
    _fetchCurrentUser();
    _refreshRecipe();
  }

  @override
  void dispose() {
    _batchController.dispose();
    _batchFocus.dispose();
    _wtController.dispose();
    _wtFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentUser() async {
    // who you are, from the phone first (no waiting for the server)
    final cached = await DatabaseHelper().getCachedData('user_profile');
    if (cached is Map && cached['id'] != null && mounted) {
      setState(() => _currentUserId = cached['id'] as int?);
    }
    try {
      final user = await _apiService.getUser();
      if (mounted) setState(() => _currentUserId = user['id']);
    } catch (e) {
      debugPrint('Error fetching current user: $e');
    }
  }

  Future<void> _refreshRecipe() async {
    // 1) show the copy saved on this phone straight away
    if (_isFetchingDetails) {
      try {
        final localData = await DatabaseHelper().getRecipeById(_recipe.id);
        final local = localData == null ? null : Recipe.fromJson(localData);
        if (local != null &&
            PriceBook.parseLines(local.ingredients).isNotEmpty &&
            mounted) {
          setState(() {
            _recipe = local;
            _parseIngredients();
            _isFetchingDetails = false;
          });
        }
      } catch (_) {}
    }
    // 2) then quietly refresh from the server
    try {
      final data = await _apiService.getRecipe(_recipe.id);
      if (mounted) {
        setState(() {
          _recipe = Recipe.fromJson(data);
          _parseIngredients();
          _isFetchingDetails = false;
        });
        try {
          await DatabaseHelper().saveLocalRecipe(data);
          await PriceBook.instance.migrateIfNeeded();
        } catch (dbError) {
          debugPrint('Background caching error: $dbError');
        }
      }
    } catch (e) {
      if (_isFetchingDetails) {
        try {
          final localData = await DatabaseHelper().getRecipeById(_recipe.id);
          if (localData != null && mounted) {
            setState(() {
              _recipe = Recipe.fromJson(localData);
              _parseIngredients();
            });
          }
        } catch (dbError) {
          debugPrint('DB Fallback Error: $dbError');
        }
        if (mounted) setState(() => _isFetchingDetails = false);
      }
    }
  }

  void _parseIngredients() {
    _parsedIngredients = [];
    if (_recipe.ingredients.isNotEmpty && _recipe.ingredients != 'null') {
      try {
        final decoded = jsonDecode(_recipe.ingredients);
        if (decoded is List) {
          _parsedIngredients = List<Map<String, dynamic>>.from(decoded);
        } else {
          _parsedIngredients = [
            {'name': decoded.toString(), 'qty': '', 'unit': ''}
          ];
        }
      } catch (e) {
        _parsedIngredients = [
          {'name': _recipe.ingredients, 'qty': '', 'unit': ''}
        ];
      }
    }
  }

  String _formatBatch(double val) => val % 1 == 0
      ? val.toInt().toString()
      : val.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');

  /// − / + step cleanly through 0.25, 0.5, 1, 2, 3...
  void _updateBatch(int dir) {
    double next;
    if (dir > 0) {
      if (_batchMultiplier < 0.5 - 1e-9) {
        next = 0.5;
      } else if (_batchMultiplier < 1 - 1e-9) {
        next = 1.0;
      } else {
        next = (_batchMultiplier + 1e-9).floorToDouble() + 1;
      }
    } else {
      if (_batchMultiplier > 1 + 1e-9) {
        next = (_batchMultiplier - 1e-9).ceilToDouble() - 1;
      } else if (_batchMultiplier > 0.5 + 1e-9) {
        next = 0.5;
      } else if (_batchMultiplier > 0.25 + 1e-9) {
        next = 0.25;
      } else {
        return;
      }
    }
    _batchFocus.unfocus();
    setState(() {
      _batchMultiplier = next;
      _batchController.text = _formatBatch(_batchMultiplier);
    });
  }

  String _formatQty(dynamic qty, [String unit = '']) {
    if (qty == null || qty.toString().isEmpty) return '';
    final val = double.tryParse(qty.toString());
    if (val == null) return qty.toString();
    final x = val * _batchMultiplier;
    double v;
    if (PriceBook.isCount(unit)) {
      v = (x * 2).round() / 2;
    } else {
      v = x >= 100 ? x.roundToDouble() : x >= 10 ? (x * 10).round() / 10 : (x * 100).round() / 100;
    }
    final s = v % 1 == 0 ? v.toInt().toString() : v.toString();
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
  }

  double _baseGrams() {
    double totalG = 0;
    for (var item in _parsedIngredients) {
      double qty = double.tryParse(item['qty'].toString()) ?? 0;
      String unit = item['unit']?.toString() ?? '';
      totalG += UnitConverter.toGrams(qty, unit);
    }
    return totalG;
  }

  double _totalGrams() => _baseGrams() * _batchMultiplier;

  String _formatGrams(double g) {
    if (g >= 1000) {
      final kg = g / 1000;
      return '${_formatBatch(kg)} kg';
    }
    return '${_formatBatch(g)} g';
  }

  void _syncWeightInput() {
    final bg = _baseGrams();
    if (bg <= 0) return;
    final curG = bg * _batchMultiplier;
    final val = _wtUnit == 'kg' ? curG / 1000 : curG;
    _wtController.text = _formatBatch(val);
  }

  void _setScaleMode(bool weightMode) {
    final bg = _baseGrams();
    if (weightMode && bg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This recipe has no gram/kg ingredients'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    _batchFocus.unfocus();
    setState(() {
      _weightMode = weightMode;
      if (weightMode) {
        final curG = bg * _batchMultiplier;
        _wtUnit = curG >= 1000 ? 'kg' : 'g';
        _syncWeightInput();
      } else {
        _batchController.text = _formatBatch(_batchMultiplier);
      }
    });
    if (weightMode) {
      Future.microtask(() {
        if (mounted) _wtFocus.requestFocus();
      });
    }
  }

  void _typeTargetWeight(String v) {
    final bg = _baseGrams();
    final num = double.tryParse(v.replaceAll(',', '.'));
    if (num == null || num <= 0 || bg <= 0) return;
    final targetG = _wtUnit == 'kg' ? num * 1000 : num;
    final f = targetG / bg;
    if (f <= 0 || f > 1000) return;
    setState(() {
      _batchMultiplier = f;
      _batchController.text = _formatBatch(f);
    });
  }

  void _resetScale() {
    _batchFocus.unfocus();
    _wtFocus.unfocus();
    setState(() {
      _batchMultiplier = 1.0;
      _batchController.text = '1';
      _syncWeightInput();
    });
  }

  String _fmtWeight(double g) {
    final s = (g % 1 == 0) ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
    final parts = s.split('.');
    final intPart = parts[0]
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return parts.length > 1 ? '$intPart.${parts[1]} g' : '$intPart g';
  }

  void _export({bool excel = false}) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ExportScreen(
              recipe: _recipe, factor: _batchMultiplier, excel: excel)));

  /// Moves the recipe to Trash (no dialog). The list screen shows
  /// "moved to Trash · Undo" when it receives the [RecipeDeleted] result.
  Future<void> _deleteRecipe() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete “${_recipe.name}”?',
                  style: const TextStyle(
                      fontFamily: 'SpaceGrotesk',
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
    if (ok != true || !mounted) return;
    final error = await _apiService.deleteRecipe(_recipe.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    try {
      Provider.of<SyncProvider>(context, listen: false)
          .triggerAutoBackupIfEnabled();
    } catch (_) {}
    Navigator.pop(context, RecipeDeleted(_recipe.id, _recipe.name));
  }

  Future<void> _editRecipe() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => RecipeFormScreen(recipe: _recipe)));
    if (result == true) _refreshRecipe();
  }

  Future<void> _openShare() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RecipeShareScreen(
                recipe: _recipe, batchMultiplier: _batchMultiplier)));
    _refreshRecipe();
  }

  @override
  Widget build(BuildContext context) {
    bool isOwner = _currentUserId == 0 || _currentUserId == _recipe.userId;
    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Column(
              children: [
                _cover(isOwner),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
                    children: [
                      _batchControl(),
                      const SizedBox(height: 20),
                      _sectionTitle('Ingredients'),
                      const SizedBox(height: 6),
                      ..._parsedIngredients.map(_ingredientRow),
                      const SizedBox(height: 14),
                      _totalBar('Total batch weight',
                          _fmtWeight(_totalGrams()), _accent),
                      const SizedBox(height: 12),
                      _costEntry(),
                      const SizedBox(height: 24),
                      _sectionTitle('Method'),
                      const SizedBox(height: 12),
                      _methodBlock(),
                      const SizedBox(height: 28),
                      _actions(isOwner),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _cover(bool isOwner) {
    final weight = _totalGrams();
    final n = _parsedIngredients.length;
    final photo = (_recipe.itemPhoto ?? '').isNotEmpty ? _recipe.itemPhoto : null;
    final scaled = _batchMultiplier != 1;
    final content = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _circleBtn(Icons.arrow_back_rounded,
                    () => Navigator.pop(context)),
                Row(children: [
                  _iconBtn(Icons.share_outlined, 'Share', _openShare),
                  if (isOwner) ...[
                    const SizedBox(width: 8),
                    _iconBtn(Icons.delete_outline_rounded, 'Delete',
                        _deleteRecipe),
                    const SizedBox(width: 8),
                    _pillBtn(Icons.edit_outlined, 'Edit', _editRecipe),
                  ],
                ]),
              ],
            ),
            SizedBox(height: photo != null ? 120 : 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(_recipe.sectionName,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _accent)),
            ),
            const SizedBox(height: 10),
            Text(_recipe.name,
                style: TextStyle(fontFamily: 'SpaceGrotesk',
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    shadows: photo != null
                        ? const [Shadow(color: Colors.black38, blurRadius: 12)]
                        : null)),
            const SizedBox(height: 6),
            Text(
                '${_fmtWeight(weight)} batch${scaled ? ' (${_formatBatch(_batchMultiplier)}×)' : ''} · $n ingredient${n == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withOpacity(0.88))),
          ],
        ),
      ),
    );
    if (photo == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_accent, _brown],
          ),
        ),
        child: content,
      );
    }
    // the recipe photo fills the header; darker at the bottom so text stays readable
    return Stack(children: [
      Positioned.fill(child: _buildRecipeImage(photo)),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.35),
                Colors.black.withOpacity(0.05),
                Colors.black.withOpacity(0.75),
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
      ),
      content,
    ]);
  }

  Widget _costEntry() {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                CostScreen(recipe: _recipe, factor: _batchMultiplier))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _accentSoft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.show_chart_rounded,
                  color: _accent, size: 20),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cost & calories',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                  SizedBox(height: 2),
                  Text('Prices, cost per kg, calories, try other prices',
                      style: TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ]),
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              border: Border.all(color: Colors.white.withOpacity(0.28)),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _pillBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700, color: _fg));

  Widget _batchControl() {
    final scaled = (_batchMultiplier - 1.0).abs() > 1e-6;
    final bg = _baseGrams();
    final showMeta = scaled || _weightMode;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Batch | Weight mode toggle
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scaleModeTab('Batch', !_weightMode, () => _setScaleMode(false)),
                    const SizedBox(width: 2),
                    _scaleModeTab('Weight', _weightMode, () => _setScaleMode(true)),
                  ],
                ),
              ),
              const Spacer(),
              if (!_weightMode) ...[
                _batchIcon(Icons.remove_rounded,
                    _batchMultiplier <= 0.25 + 1e-9 ? null : () => _updateBatch(-1)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 64,
                  height: 40,
                  child: TextField(
                    controller: _batchController,
                    focusNode: _batchFocus,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: _batchFocus.hasFocus ? _fg : Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: _batchFocus.hasFocus ? _surface : _accent,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _accent)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _accent, width: 1.5)),
                    ),
                    onTap: () => setState(() {}),
                    onSubmitted: (_) => setState(() {}),
                    onChanged: (val) {
                      final d = double.tryParse(val.replaceAll(',', '.'));
                      if (d != null && d > 0 && d <= 1000) {
                        setState(() => _batchMultiplier = d);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _batchIcon(Icons.add_rounded, () => _updateBatch(1)),
              ] else
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 76,
                        child: TextField(
                          controller: _wtController,
                          focusNode: _wtFocus,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: _fg),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6),
                          ),
                          onChanged: _typeTargetWeight,
                        ),
                      ),
                      Container(width: 1, height: 22, color: _line),
                      Container(
                        color: _accentSoft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _wtUnit,
                            isDense: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 18, color: _accent),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _accent),
                            items: const [
                              DropdownMenuItem(value: 'g', child: Text('g')),
                              DropdownMenuItem(value: 'kg', child: Text('kg')),
                            ],
                            onChanged: (u) {
                              if (u == null) return;
                              setState(() {
                                _wtUnit = u;
                                _syncWeightInput();
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (showMeta) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: _line),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _weightMode
                      ? '${_formatBatch(_batchMultiplier)}× of 1 batch (${_formatGrams(bg)})'
                      : 'Scaled ${_formatBatch(_batchMultiplier)}× · Total ${_formatGrams(_totalGrams())}',
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
                if (scaled)
                  GestureDetector(
                    onTap: _resetScale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Reset 1×',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _accent)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scaleModeTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : _muted)),
      ),
    );
  }

  Widget _batchIcon(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line)),
          child: Icon(icon, size: 18, color: _fg),
        ),
      ),
    );
  }

  Widget _ingredientRow(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration:
          const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Row(
        children: [
          Expanded(
            child: Text(item['name']?.toString() ?? '',
                style: const TextStyle(fontSize: 15, color: _fg)),
          ),
          const SizedBox(width: 12),
          Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: _formatQty(item['qty'], item['unit']?.toString() ?? ''),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _batchMultiplier != 1 ? _accent : _fg)),
                TextSpan(text: ' ${item['unit'] ?? ''}'),
              ]),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: _muted)),
        ],
      ),
    );
  }

  Widget _totalBar(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(fontFamily: 'SpaceGrotesk',
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _methodBlock() {
    final steps = _getSteps();
    if (steps.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line)),
        child: const Text('No method added.',
            style: TextStyle(color: _muted, fontSize: 15)),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: _accentSoft, shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(steps[i],
                        style: const TextStyle(
                            fontSize: 15, height: 1.5, color: _fg)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(bool isOwner) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _btn(Icons.picture_as_pdf_outlined, 'PDF', _export)),
          const SizedBox(width: 10),
          Expanded(child: _btn(Icons.table_view_outlined, 'Excel', () => _export(excel: true))),
        ]),
      ],
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool destructive = false}) {
    final c = destructive ? const Color(0xFFC0392B) : _accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildRecipeImage(String path) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: _accentSoft),
          errorWidget: (_, __, ___) => Container(color: _accentSoft));
    } else {
      return Image.file(File(imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: _accentSoft));
    }
  }
}
