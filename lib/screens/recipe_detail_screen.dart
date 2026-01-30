import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
// ignore: deprecated_member_use
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import '../models/recipe.dart';
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

  Future<void> _manageAccess() async {
    final usernameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Manage Access'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Give access via username or email:',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: usernameController,
                          decoration: const InputDecoration(
                              hintText: 'Username / Email'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue),
                        onPressed: () async {
                          if (usernameController.text.isEmpty) return;
                          final msg = await _apiService.shareRecipeAccess(
                              _recipe.id, usernameController.text);
                          usernameController.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg ?? 'Error')));
                            await _refreshRecipe();
                            setDialogState(() {});
                          }
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('People with access:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_recipe.sharedWith == null || _recipe.sharedWith!.isEmpty)
                    const Text('No shared users yet.',
                        style: TextStyle(fontStyle: FontStyle.italic))
                  else
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _recipe.sharedWith!.length,
                        itemBuilder: (ctx, i) {
                          final user = _recipe.sharedWith![i];
                          final name = user['name'] ?? 'Unknown';
                          final username = user['username'] ?? 'User';
                          final uid = user['id'];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                                maxRadius: 12,
                                child: Text(name[0].toUpperCase())),
                            title: Text('$name (@$username)'),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red, size: 20),
                              onPressed: () async {
                                final msg = await _apiService
                                    .removeRecipeAccess(_recipe.id, uid);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg ?? 'Error')));
                                  await _refreshRecipe();
                                  setDialogState(() {});
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'))
            ],
          );
        },
      ),
    );
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 300.0,
                  floating: false,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      _recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, shadows: [
                        Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3.0,
                            color: Colors.black)
                      ]),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        _recipe.itemPhoto != null
                            ? _buildRecipeImage(_recipe.itemPhoto!)
                            : Container(
                                color: Colors.orange.shade100,
                                child: const Icon(Icons.restaurant,
                                    size: 100, color: Colors.orange)),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black54,
                                Colors.transparent,
                                Colors.black54
                              ],
                              stops: [0.0, 0.3, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    if (isOwner)
                      Container(
                        margin: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.black45, shape: BoxShape.circle),
                        child: IconButton(
                            icon: const Icon(Icons.person_add,
                                color: Colors.white),
                            onPressed: _manageAccess,
                            tooltip: 'Manage Access'),
                      ),
                    Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.black45, shape: BoxShape.circle),
                      child: IconButton(
                          icon: const Icon(Icons.share, color: Colors.white),
                          onPressed: _shareRecipe,
                          tooltip: 'Share Text'),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: [
                            if (_recipe.brandName != null &&
                                _recipe.brandName!.isNotEmpty)
                              Chip(
                                  label: Text(_recipe.brandName!),
                                  backgroundColor: Colors.orange.shade50),
                            Chip(
                                label: Text(_recipe.sectionName),
                                backgroundColor: Colors.blue.shade50),
                            if (_currentUserId != null &&
                                !isOwner &&
                                _recipe.ownerName != null)
                              Chip(
                                avatar: const Icon(Icons.person,
                                    size: 16, color: Colors.white),
                                label: Text('By ${_recipe.ownerName}'),
                                backgroundColor: Colors.teal,
                                labelStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Batch Size',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              Row(
                                children: [
                                  IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline),
                                      onPressed: () => _updateBatch(-0.5)),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      controller: _batchController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: (val) {
                                        if (val.isEmpty) return;
                                        final parsed = double.tryParse(val);
                                        if (parsed != null && parsed > 0) {
                                          setState(
                                              () => _batchMultiplier = parsed);
                                        }
                                      },
                                    ),
                                  ),
                                  IconButton(
                                      icon:
                                          const Icon(Icons.add_circle_outline),
                                      onPressed: () => _updateBatch(0.5)),
                                ],
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Ingredients',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo)),
                        const SizedBox(height: 8),
                        if (_parsedIngredients.isEmpty &&
                            _recipe.ingredients.isNotEmpty &&
                            !_recipe.ingredients.startsWith('['))
                          Text(_recipe.ingredients)
                        else if (_parsedIngredients.isNotEmpty)
                          Card(
                            elevation: 2,
                            surfaceTintColor: Colors.white,
                            child: Column(
                              children: [
                                ..._parsedIngredients.map((item) => ListTile(
                                      leading: const Icon(Icons.circle,
                                          size: 8, color: Colors.orange),
                                      title: Text(item['name'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      trailing: Container(
                                        constraints:
                                            const BoxConstraints(maxWidth: 100),
                                        child: Text(
                                          '${_formatQty(item['qty'])} ${item['unit'] ?? ''}',
                                          style: const TextStyle(
                                              color: Colors.grey, fontSize: 14),
                                          textAlign: TextAlign.end,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )),
                                const Divider(),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Total:",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16)),
                                      Flexible(
                                        child: Text(
                                          '${_calculateTotalWeight()} g',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: Colors.indigo),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ),
                          )
                        else if (_isFetchingDetails)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          const Text('No ingredients listed.',
                              style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey)),
                        const SizedBox(height: 24),
                        const Text('Preparation',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            _recipe.process,
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const Divider(),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          alignment: WrapAlignment.spaceEvenly,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _downloadPdf,
                              icon: const Icon(Icons.picture_as_pdf,
                                  color: Colors.red),
                              label: const Text('PDF'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _downloadExcel,
                              icon: const Icon(Icons.table_view,
                                  color: Colors.green),
                              label: const Text('Excel'),
                            ),
                            if (isOwner)
                              FilledButton.icon(
                                onPressed: _editRecipe,
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit'),
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor),
                              ),
                            if (isOwner)
                              FilledButton.icon(
                                onPressed: _deleteRecipe,
                                icon: const Icon(Icons.delete),
                                label: const Text('Delete'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red),
                              ),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
