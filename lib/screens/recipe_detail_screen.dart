import 'dart:convert';
import 'dart:io';
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
import '../sync_provider.dart';
import '../utils/unit_converter.dart';
import 'recipe_form_screen.dart';

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
    } catch (e) {}
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
      }
    } catch (e) {
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
    return val.toString();
  }

  void _updateBatch(double delta) {
    setState(() {
      _batchMultiplier = (_batchMultiplier + delta).clamp(0.5, 10.0);
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

  String _calculateTotalWeight() {
    double total = 0.0;
    for (var item in _parsedIngredients) {
      try {
        if (item['qty'] != null) {
          double val = double.parse(item['qty'].toString());
          String unit = item['unit']?.toString() ?? '';
          total += UnitConverter.toGrams(val, unit);
        }
      } catch (e) {}
    }
    total = total * _batchMultiplier;
    return total % 1 == 0 ? total.toInt().toString() : total.toStringAsFixed(2);
  }

  Future<void> _shareRecipe() async {
    final String text = '''
Check out this recipe: ${_recipe.name}
${_recipe.brandName != null ? 'Brand: ${_recipe.brandName}\n' : ''}
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
                <String>['Total', '${_calculateTotalWeight()} g', ''],
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
      sheetObject.cell(CellIndex.indexByString("A3")).value =
          TextCellValue("Ingredient");
      sheetObject.cell(CellIndex.indexByString("B3")).value =
          TextCellValue("Quantity");
      sheetObject.cell(CellIndex.indexByString("C3")).value =
          TextCellValue("Unit");

      for (var i = 0; i < _parsedIngredients.length; i++) {
        var item = _parsedIngredients[i];
        var row = i + 4;
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

          // Trigger auto backup if enabled
          try {
            final syncProvider =
                Provider.of<SyncProvider>(context, listen: false);
            syncProvider.triggerAutoBackupIfEnabled();
          } catch (e) {
            // Ignore
          }
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

  Widget _buildRecipeImage(String path) {
    final imageUrl = ApiService.getImageUrl(path);
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey.shade400),
        errorWidget: (context, url, error) => Container(
            color: Colors.orange.shade100,
            child:
                const Icon(Icons.restaurant, size: 100, color: Colors.orange)),
      );
    } else {
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.orange.shade100,
            child:
                const Icon(Icons.restaurant, size: 100, color: Colors.orange)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isOwner = _currentUserId == _recipe.userId;
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildModernAppBar(isOwner),
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderSection(isOwner),
                          const SizedBox(height: 32),
                          _buildBatchControl(),
                          const SizedBox(height: 32),
                          _buildIngredientsSection(),
                          const SizedBox(height: 32),
                          _buildPreparationSection(),
                          const SizedBox(height: 40),
                          _buildActionButtons(isOwner),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModernAppBar(bool isOwner) {
    return SliverAppBar(
      expandedHeight: 350.0,
      elevation: 0,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.share_outlined,
                  color: Colors.white, size: 20),
            ),
            onPressed: _shareRecipe,
            tooltip: 'Share Recipe',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            _recipe.itemPhoto != null
                ? _buildRecipeImage(_recipe.itemPhoto!)
                : Container(
                    color: const Color(0xFFF7F7F7),
                    child: Icon(Icons.restaurant,
                        size: 80, color: Colors.grey.shade300),
                  ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black26,
                    Colors.transparent,
                    Colors.black54,
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(bool isOwner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _recipe.name,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            if (_recipe.brandName != null && _recipe.brandName!.isNotEmpty)
              _buildTag(
                  _recipe.brandName!,
                  const Color(0xFFE74C3C).withOpacity(0.1),
                  const Color(0xFFE74C3C)),
            _buildTag(
                _recipe.sectionName,
                const Color(0xFF3498DB).withOpacity(0.1),
                const Color(0xFF3498DB)),
            if (_currentUserId != null && !isOwner && _recipe.ownerName != null)
              _buildTag('By ${_recipe.ownerName}', Colors.teal.withOpacity(0.1),
                  Colors.teal),
          ],
        ),
      ],
    );
  }

  Widget _buildTag(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBatchControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE74C3C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.scale_outlined,
                color: Color(0xFFE74C3C), size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch Size',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  'Adjust portions',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _buildBatchButton(Icons.remove, () => _updateBatch(-0.5)),
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _batchController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) return;
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        setState(() => _batchMultiplier = parsed);
                      }
                    },
                  ),
                ),
                _buildBatchButton(Icons.add, () => _updateBatch(0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, size: 18, color: const Color(0xFF1A1A1A)),
      ),
    );
  }

  Widget _buildIngredientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.restaurant_menu_rounded,
                color: Color(0xFFE74C3C), size: 22),
            SizedBox(width: 8),
            Text(
              'Ingredients',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_parsedIngredients.isEmpty &&
            _recipe.ingredients.isNotEmpty &&
            !_recipe.ingredients.startsWith('['))
          _buildLegacyIngredientsText()
        else if (_parsedIngredients.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF0F0F0)),
            ),
            child: Column(
              children: [
                ..._parsedIngredients.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isLast = index == _parsedIngredients.length - 1;
                  return _buildIngredientItem(item, !isLast);
                }),
                _buildTotalWeightFooter(),
              ],
            ),
          )
        else if (_isFetchingDetails)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()))
        else
          const Center(
              child: Text('No ingredients listed.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey))),
      ],
    );
  }

  Widget _buildLegacyIngredientsText() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(_recipe.ingredients,
          style: const TextStyle(fontSize: 15, height: 1.5)),
    );
  }

  Widget _buildIngredientItem(Map<String, dynamic> item, bool showDivider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.check, size: 16, color: Colors.green),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item['name'] ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF333333)),
                ),
              ),
              Text(
                '${_formatQty(item['qty'])} ${item['unit'] ?? ''}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFFE74C3C)),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
          ),
      ],
    );
  }

  Widget _buildTotalWeightFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFD),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Total Weight",
              style:
                  TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
          Text(
            '${_calculateTotalWeight()} g',
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF1A1A1A)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreparationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFFE74C3C), size: 22),
            SizedBox(width: 8),
            Text(
              'Preparation',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF0F0F0)),
          ),
          child: Text(
            _recipe.process,
            style: const TextStyle(
                fontSize: 16, height: 1.8, color: Color(0xFF444444)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isOwner) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildExportButton(
                Icons.picture_as_pdf_rounded,
                'Download PDF',
                const Color(0xFFE74C3C),
                _downloadPdf,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildExportButton(
                Icons.table_view_rounded,
                'Export Excel',
                const Color(0xFF27AE60),
                _downloadExcel,
              ),
            ),
          ],
        ),
        if (isOwner) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  Icons.edit_rounded,
                  'Edit Recipe',
                  const Color(0xFF3498DB),
                  _editRecipe,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  Icons.delete_outline_rounded,
                  'Delete',
                  const Color(0xFFE74C3C),
                  _deleteRecipe,
                  outline: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildExportButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withOpacity(0.2)),
        ),
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, Color color, VoidCallback onTap,
      {bool outline = false}) {
    if (outline) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: color),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
