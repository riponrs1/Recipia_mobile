import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// ignore: deprecated_member_use
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import '../models/recipe.dart';
import '../database_helper.dart';
import '../sync_provider.dart';
import '../utils/unit_converter.dart';
import 'recipe_form_screen.dart';
import 'recipe_analysis_screen.dart';

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
  Set<int> _checkedIngredients = {};
  int? _currentUserId;
  bool _isLoading = false;
  bool _isFetchingDetails = true;

  late TextEditingController _batchController;

  List<String> _getSteps() {
    return _recipe.process
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
  }

  void _toggleIngredient(int index) {
    setState(() {
      if (_checkedIngredients.contains(index)) {
        _checkedIngredients.remove(index);
      } else {
        _checkedIngredients.add(index);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _recipe = widget.recipe;
    _batchController =
        TextEditingController(text: _formatBatch(_batchMultiplier));
    _parseIngredients();
    _fetchCurrentUser();
    _refreshRecipe();
  }

  @override
  void dispose() {
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentUser() async {
    try {
      final user = await _apiService.getUser();
      if (mounted) {
        setState(() {
          _currentUserId = user['id'];
        });
      }
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
        // FIX: Auto-cache full details for offline use
        await DatabaseHelper().saveLocalRecipe(data);
      }
    } catch (e) {
      debugPrint('Error refreshing recipe: $e');
      // Offline fallback: Attempt to load full recipe from local database
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

  void _parseIngredients() {
    if (_recipe.ingredients.isNotEmpty) {
      try {
        final decoded = jsonDecode(_recipe.ingredients);
        if (decoded is List) {
          _parsedIngredients = List<Map<String, dynamic>>.from(decoded);
        }
      } catch (e) {
        _parsedIngredients = [];
      }
    }
  }

  String _formatBatch(double val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(1);
  }

  void _updateBatch(double delta) {
    setState(() {
      _batchMultiplier = (_batchMultiplier + delta).clamp(0.5, 100.0);
      _batchController.text = _formatBatch(_batchMultiplier);
    });
  }

  String _formatQty(dynamic qty) {
    if (qty == null || qty.toString().isEmpty) return '';
    try {
      double val = double.parse(qty.toString());
      double scaled = val * _batchMultiplier;
      if (scaled % 1 == 0) return scaled.toInt().toString();
      return scaled.toStringAsFixed(2);
    } catch (e) {
      return qty.toString();
    }
  }

  String _calculateTotalCalories() {
    double total = 0.0;
    for (var item in _parsedIngredients) {
      try {
        double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
        String unit = item['unit']?.toString() ?? '';
        double calPerKg = (item['calories'] ?? 0.0).toDouble();

        if (calPerKg > 0) {
          double grams = UnitConverter.toGrams(qty, unit);
          if (grams > 0) {
            total += (grams / 1000) * calPerKg;
          } else {
            total += qty * calPerKg;
          }
        }
      } catch (e) {
        debugPrint('Error calculating calories: $e');
      }
    }
    total = total * _batchMultiplier;
    return total.toStringAsFixed(0);
  }

  String _calculateTotalCost() {
    double total = 0.0;
    for (var item in _parsedIngredients) {
      try {
        double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
        String unit = item['unit']?.toString() ?? '';
        double pricePerKg = (item['price'] ?? 0.0).toDouble();

        if (pricePerKg > 0) {
          double grams = UnitConverter.toGrams(qty, unit);
          if (grams > 0) {
            total += (grams / 1000) * pricePerKg;
          } else {
            total += qty * pricePerKg;
          }
        }
      } catch (e) {
        debugPrint('Error calculating cost: $e');
      }
    }
    total = total * _batchMultiplier;
    return total.toStringAsFixed(2);
  }

  String _calculateCostPerServing() {
    double total = double.tryParse(_calculateTotalCost()) ?? 0.0;
    int servings = _recipe.servings > 0 ? _recipe.servings : 1;
    double perServing = total / servings; // Total is already batch-multiplied
    return perServing.toStringAsFixed(2);
  }

  Future<void> _shareRecipe() async {
    final String text = '''
Check out this recipe: ${_recipe.name}
${_recipe.brandName != null ? 'Brand: ${_recipe.brandName}\n' : ''}
Calories: ${_calculateTotalCalories()} kcal
Total Cost: \$${_calculateTotalCost()}
Ingredients:
${_parsedIngredients.map((i) => '- ${i['name']}: ${_formatQty(i['qty'])} ${i['unit'] ?? ''}').join('\n')}

Process:
${_recipe.process}
''';
    await Share.share(text);
  }

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
            pw.Text('Nutrition: ${_calculateTotalCalories()} kcal | Cost: \$${_calculateTotalCost()}'),
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF Ready: ${_recipe.name}.pdf'),
            backgroundColor: Colors.green,
          ),
        );
      }

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
      sheetObject.cell(CellIndex.indexByString("A2")).value =
          TextCellValue("Kcal: ${_calculateTotalCalories()} | Cost: \$${_calculateTotalCost()}");
      
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excel Ready: ${_recipe.name}.xlsx'),
              backgroundColor: Colors.green,
            ),
          );
        }
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

  Future<void> _deleteRecipe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recipe?'),
        content: const Text(
            'Are you sure you want to delete this recipe? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final error = await _apiService.deleteRecipe(_recipe.id);
      setState(() => _isLoading = false);

      if (error == null) {
        if (mounted) {
          Navigator.pop(context, true);
          try {
            final syncProvider =
                Provider.of<SyncProvider>(context, listen: false);
            syncProvider.triggerAutoBackupIfEnabled();
          } catch (e) {}
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
      }
    }
  }

  Future<void> _editRecipe() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => RecipeFormScreen(recipe: _recipe)));
    if (result == true) {
      _refreshRecipe();
    }
  }




  @override
  Widget build(BuildContext context) {
    bool isOwner = _currentUserId == _recipe.userId;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      extendBody: true, // Allow content to flow behind the glass bar
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D4037)))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildRecipeAppBar(),
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFDFBF7),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderSection(),
                          const SizedBox(height: 24),
                          _buildMetricBar(),
                          const SizedBox(height: 32),
                          _buildBatchControl(),
                          const SizedBox(height: 32),
                          _buildIngredientsSection(),
                          const SizedBox(height: 32),
                          _buildPreparationSection(),
                          const SizedBox(height: 48),
                          _buildActionButtons(isOwner),
                          const SizedBox(height: 80), // Normal padding
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }


  Widget _buildRecipeAppBar() {
    return SliverAppBar(
      expandedHeight: 340.0,
      elevation: 0,
      pinned: true,
      stretch: true, // Allow stretch effect
      backgroundColor: const Color(0xFF5D4037),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
          ),
          onPressed: _shareRecipe,
        ),
        const SizedBox(width: 16),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            _recipe.itemPhoto != null
                ? _buildRecipeImage(_recipe.itemPhoto!)
                : Container(color: const Color(0xFF5D4037)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black38, Colors.transparent, Colors.transparent],
                  stops: [0.0, 0.3, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_recipe.sectionName.toUpperCase(), 
          style: const TextStyle(color: Color(0xFFFAB1A0), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 8),
        Text(
          _recipe.name,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF2D3436), letterSpacing: -1),
        ),
        if (_recipe.brandName != null && _recipe.brandName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text('By ${_recipe.brandName}', 
              style: TextStyle(color: Colors.brown.shade200, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }

  Widget _buildMetricBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildMetricItem('${_calculateTotalCalories()} kcal', 'CALORIES'),
          _buildMetricSeparator(),
          _buildMetricItem('\$${_calculateTotalCost()}', 'TOTAL COST'),
          _buildMetricSeparator(),
          _buildMetricItem('\$${_calculateCostPerServing()}', 'PER SERV'),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF5D4037))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFFAB1A0), letterSpacing: 1)),
      ],
    );
  }

  Widget _buildMetricSeparator() => Container(width: 1, height: 20, color: Colors.black.withOpacity(0.05));

  Widget _buildBatchControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('SCALE BATCH', 
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.5, color: Color(0xFF5D4037))),
          ),
          _buildBatchIcon(Icons.remove_rounded, () => _updateBatch(-0.5)),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: TextField(
              controller: _batchController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF5D4037)),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                suffixText: 'x',
                suffixStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF5D4037)),
              ),
              onChanged: (val) {
                final double? newMultiplier = double.tryParse(val);
                if (newMultiplier != null && newMultiplier > 0) {
                  setState(() {
                    _batchMultiplier = newMultiplier;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          _buildBatchIcon(Icons.add_rounded, () => _updateBatch(0.5)),
        ],
      ),
    );
  }

  Widget _buildBatchIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFFDFBF7), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: const Color(0xFF5D4037)),
      ),
    );
  }

  Widget _buildIngredientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('INGREDIENTS', 
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFAB1A0))),
            Text('${_checkedIngredients.length}/${_parsedIngredients.length} PREPPED', 
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFB2BEC3))),
          ],
        ),
        const SizedBox(height: 16),
        ..._parsedIngredients.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isChecked = _checkedIngredients.contains(i);
          
          return GestureDetector(
            onTap: () => _toggleIngredient(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isChecked ? 0.5 : 1.0,
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isChecked ? const Color(0xFF5D4037) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isChecked ? const Color(0xFF5D4037) : const Color(0xFFFAB1A0).withOpacity(0.4)),
                      ),
                      child: isChecked ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Text(item['name'] ?? '', style: TextStyle(
                            fontSize: 14, 
                            fontWeight: FontWeight.w700, 
                            color: const Color(0xFF2D3436),
                            decoration: isChecked ? TextDecoration.lineThrough : null,
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('.' * 100, 
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(color: const Color(0xFF5D4037).withOpacity(0.1), letterSpacing: 2, fontWeight: FontWeight.w900)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Text('${_formatQty(item['qty'])} ${item['unit'] ?? ''}', 
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF5D4037))),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        _buildTotalWeightFooter(),
      ],
    );
  }

  Widget _buildTotalWeightFooter() {
    double totalG = 0;
    for (var item in _parsedIngredients) {
      double qty = double.tryParse(item['qty'].toString()) ?? 0;
      String unit = item['unit'] ?? '';
      totalG += UnitConverter.toGrams(qty, unit);
    }
    totalG *= _batchMultiplier;
    if (totalG <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAB1A0).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFAB1A0).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Color(0xFFFAB1A0), shape: BoxShape.circle),
            child: const Icon(Icons.scale_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('ESTIMATED BATCH WEIGHT', 
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF5D4037), letterSpacing: 0.5)),
          ),
          Text('${totalG.toStringAsFixed(0)} g', 
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF5D4037))),
        ],
      ),
    );
  }

  Widget _buildPreparationSection() {
    final steps = _getSteps();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PREPARATION STEPS', 
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFAB1A0))),
        const SizedBox(height: 20),
        ...steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((i + 1).toString().padLeft(2, '0'), 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF5D4037), letterSpacing: -0.5)),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(step, 
                    style: const TextStyle(fontSize: 16, height: 1.7, color: Color(0xFF636E72), fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionButtons(bool isOwner) {
    return Column(
      children: [
        _buildRecipeButton(Icons.insights_rounded, 'CULINARY ANALYSIS', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeAnalysisScreen(recipe: _recipe, batchMultiplier: _batchMultiplier)));
        }),
        const SizedBox(height: 12),
        _buildRecipeButton(Icons.picture_as_pdf_rounded, 'SAVE AS PDF', _downloadPdf),
        const SizedBox(height: 12),
        _buildRecipeButton(Icons.table_view_rounded, 'EXPORT EXCEL', _downloadExcel),
        if (isOwner) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildRecipeButton(Icons.edit_rounded, 'EDIT', _editRecipe, isBrief: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildRecipeButton(Icons.delete_outline_rounded, 'DELETE', _deleteRecipe, isBrief: true, isDestructive: true)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRecipeButton(IconData icon, String label, VoidCallback onTap, {bool isBrief = false, bool isDestructive = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDestructive ? const Color(0xFFE74C3C) : const Color(0xFF5D4037),
        padding: EdgeInsets.symmetric(vertical: isBrief ? 16 : 22),
        minimumSize: const Size(double.infinity, 0),
        side: BorderSide(color: isDestructive ? const Color(0xFFE74C3C).withOpacity(0.2) : Colors.black.withOpacity(0.05)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildRecipeImage(String path) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey.shade100),
        errorWidget: (_, __, ___) => Container(color: Colors.grey.shade100, child: const Icon(Icons.broken_image)),
      );
    } else {
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade100, child: const Icon(Icons.broken_image)),
      );
    }
  }
}
