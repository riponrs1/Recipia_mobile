import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_settings.dart';
import 'package:provider/provider.dart';
// ignore: deprecated_member_use
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import '../models/recipe.dart';
import '../database_helper.dart';
import '../sync_provider.dart';
import '../utils/unit_converter.dart';
import 'recipe_form_screen.dart';
import 'cost_screen.dart';
import '../services/price_book.dart';
import 'recipe_share_screen.dart';

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFFBF6E8);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);
const _accentSoft = Color(0xFFE6EFE9);
const _brown = Color(0xFF8D6E63);

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
    // tapping the number clears it so any amount can be typed;
    // leaving it empty puts the current amount back
    _batchFocus.addListener(() {
      if (_batchFocus.hasFocus) {
        _batchController.clear();
      } else if (_batchController.text.trim().isEmpty) {
        _batchController.text = _formatBatch(_batchMultiplier);
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
    super.dispose();
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final user = await _apiService.getUser();
      if (mounted) setState(() => _currentUserId = user['id']);
    } catch (e) {
      debugPrint('Error fetching current user: $e');
    }
  }

  Future<void> _refreshRecipe() async {
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

  /// − / + change the batch by 1; the buttons never go below 1.
  void _updateBatch(int dir) {
    final next = dir > 0
        ? (_batchMultiplier + 1e-9).floorToDouble() + 1
        : (_batchMultiplier - 1e-9).ceilToDouble() - 1;
    if (next < 1) return;
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

  double _totalGrams() {
    double totalG = 0;
    for (var item in _parsedIngredients) {
      double qty = double.tryParse(item['qty'].toString()) ?? 0;
      String unit = item['unit']?.toString() ?? '';
      totalG += UnitConverter.toGrams(qty, unit);
    }
    return totalG * _batchMultiplier;
  }

  String _fmtWeight(double g) {
    final s = (g % 1 == 0) ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
    final parts = s.split('.');
    final intPart = parts[0]
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return parts.length > 1 ? '$intPart.${parts[1]} g' : '$intPart g';
  }

  CostSummary _summary() => PriceBook.instance.summarize(
      _recipe.id, PriceBook.parseLines(_recipe.ingredients),
      factor: _batchMultiplier);

  String _calculateTotalCalories() => _summary().calories.toStringAsFixed(0);

  String _calculateTotalCost() => _summary().total.toStringAsFixed(2);

  Future<void> _downloadPdf() async {
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          build: (pw.Context context) => [
            pw.Header(
                level: 0,
                child: pw.Text(_recipe.name,
                    style: pw.TextStyle(
                        fontSize: 24, fontWeight: pw.FontWeight.bold))),
            if (_recipe.brandName != null)
              pw.Text('Brand: ${_recipe.brandName}'),
            pw.SizedBox(height: 10),
            pw.Text(
                'Nutrition: ${_calculateTotalCalories()} kcal | Cost: ${AppSettings.currency}${_calculateTotalCost()}'),
            pw.SizedBox(height: 20),
            pw.Text('Ingredients (Batch: ${_batchMultiplier}x)',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              context: context,
              data: <List<String>>[
                <String>['Ingredient', 'Quantity', 'Unit'],
                ..._parsedIngredients.map((item) => [
                      item['name'].toString(),
                      _formatQty(item['qty']),
                      item['unit'].toString()
                    ]),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text('Process',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Paragraph(text: _recipe.process),
          ],
        ),
      );
      final output = await getTemporaryDirectory();
      final file =
          File('${output.path}/${_recipe.name.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)],
          text: 'Here is the PDF for ${_recipe.name}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error creating PDF: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _downloadExcel() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];
      sheetObject.cell(CellIndex.indexByString("A1")).value =
          TextCellValue("Recipe: ${_recipe.name}");
      sheetObject.cell(CellIndex.indexByString("A2")).value = TextCellValue(
          "Kcal: ${_calculateTotalCalories()} | Cost: ${AppSettings.currency}${_calculateTotalCost()}");
      sheetObject.cell(CellIndex.indexByString("A4")).value =
          TextCellValue("Ingredient");
      sheetObject.cell(CellIndex.indexByString("B4")).value =
          TextCellValue("Quantity");
      sheetObject.cell(CellIndex.indexByString("C4")).value =
          TextCellValue("Unit");
      for (var i = 0; i < _parsedIngredients.length; i++) {
        var item = _parsedIngredients[i];
        var row = i + 5;
        sheetObject.cell(CellIndex.indexByString("A$row")).value =
            TextCellValue(item['name'].toString());
        sheetObject.cell(CellIndex.indexByString("B$row")).value =
            DoubleCellValue(double.tryParse(_formatQty(item['qty'])) ?? 0.0);
        sheetObject.cell(CellIndex.indexByString("C$row")).value =
            TextCellValue(item['unit'].toString());
      }
      final output = await getTemporaryDirectory();
      final file =
          File('${output.path}/${_recipe.name.replaceAll(' ', '_')}.xlsx');
      final fileBytes = excel.save();
      if (fileBytes != null) {
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(file.path)],
            text: 'Here is the Excel file for ${_recipe.name}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error creating Excel: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

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
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => RecipeShareScreen(recipe: _recipe)));
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Batch size',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15, color: _fg)),
          ),
          _batchIcon(Icons.remove_rounded,
              _batchMultiplier <= 1 ? null : () => _updateBatch(-1)),
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
        ],
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
          Expanded(child: _btn(Icons.picture_as_pdf_outlined, 'PDF', _downloadPdf)),
          const SizedBox(width: 10),
          Expanded(child: _btn(Icons.table_view_outlined, 'Excel', _downloadExcel)),
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
