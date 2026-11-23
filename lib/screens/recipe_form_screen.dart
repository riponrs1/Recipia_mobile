import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../services/price_book.dart';
import '../services/recipe_ocr_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../models/recipe.dart';
import '../sync_provider.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _warn = Color(0xFFA8650A);
const _accentSoft = Color(0xFFFCEEE9);

class RecipeFormScreen extends StatefulWidget {
  final Recipe? recipe;

  /// Optional data used to pre-fill a brand-new recipe (e.g. from a scan).
  final String? initialName;
  final List<Map<String, dynamic>>? initialIngredients;
  final String? initialProcess;

  const RecipeFormScreen({
    super.key,
    this.recipe,
    this.initialName,
    this.initialIngredients,
    this.initialProcess,
  });

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _showValidation = false;
  final _formKey = GlobalKey<FormState>();
  final _nameFieldKey = GlobalKey();
  final _customSectionKey = GlobalKey();
  final _ingredientsKey = GlobalKey();
  final _methodKey = GlobalKey();

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _servingsController = TextEditingController(text: '1');
  String _selectedSection = 'Other...';
  String _visibility = 'private';

  File? _itemPhoto;
  File? _scannedPhoto;
  bool _isScanning = false;
  final _picker = ImagePicker();

  final List<Map<String, dynamic>> _ingredientsList = [];
  final _processController = TextEditingController();

  final List<String> _sections = [];
  List<String> _availableBrands = [];
  List<Map<String, dynamic>> _allPantryIngredients = [];

  final List<String> _units = [
    'g', 'kg', 'ml', 'l', 'cup', 'tbsp', 'tsp', 'oz', 'lb', 'piece', 'pinch'
  ];

  final _customSectionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  Future<void> _initForm() async {
    try {
      final localSections = await DatabaseHelper().getLocalSections();
      final brands = await DatabaseHelper().getUniqueBrands();
      if (mounted) {
        setState(() {
          _sections.clear();
          for (var s in localSections) {
            _sections.add(s['name']);
          }
          if (!_sections.contains('Other...')) _sections.add('Other...');
          _availableBrands = brands;
          _selectedSection = _sections.isNotEmpty ? _sections.first : 'Other...';
          if (widget.recipe != null) {
            if (_sections.contains(widget.recipe!.sectionName)) {
              _selectedSection = widget.recipe!.sectionName;
            } else {
              _selectedSection = 'Other...';
              _customSectionController.text = widget.recipe!.sectionName;
            }
          }
        });
        final ingredients = await DatabaseHelper().getCachedIngredients();
        if (mounted) setState(() => _allPantryIngredients = ingredients);
      }

      final sectionsJson = await _apiService.getSections();
      if (sectionsJson.isNotEmpty) {
        for (var s in sectionsJson) {
          await DatabaseHelper().saveLocalSection({
            'name': s['name'],
            'is_system': s['user_id'] == null ? 1 : 0,
            'icon': s['icon'] ?? 'category',
            'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
          });
        }
        final refreshedLocal = await DatabaseHelper().getLocalSections();
        if (mounted) {
          setState(() {
            _sections.clear();
            for (var s in refreshedLocal) {
              _sections.add(s['name']);
            }
            if (!_sections.contains('Other...')) _sections.add('Other...');
            if (widget.recipe != null &&
                _sections.contains(widget.recipe!.sectionName)) {
              _selectedSection = widget.recipe!.sectionName;
            }
          });
        }
      }
    } catch (e) {
      if (mounted && _sections.isEmpty) {
        setState(() {
          _sections.addAll([
            'Hot Kitchen', 'Bakery', 'Pastry', 'Sauce', 'Cold/Salad',
            'Appetizers', 'Main Course', 'Desserts', 'Beverages', 'Other...'
          ]);
          _selectedSection = _sections.first;
        });
      }
    }

    if (widget.recipe != null) {
      _nameController.text = widget.recipe!.name;
      _brandController.text = widget.recipe!.brandName ?? '';
      _visibility = widget.recipe!.visibility ?? 'private';
      if (widget.recipe!.ingredients.isNotEmpty) {
        try {
          final decoded = jsonDecode(widget.recipe!.ingredients);
          if (decoded is List) {
            _ingredientsList.clear();
            for (var item in decoded) {
              final unitVal = item['unit'] ?? 'g';
              _addIngredientRow(
                  name: item['name'] ?? '',
                  qty: (item['qty'] ?? '').toString(),
                  unit: _units.contains(unitVal) ? unitVal : 'g');
            }
          }
        } catch (e) {
          _ingredientsList.clear();
          _addIngredientRow(name: widget.recipe!.ingredients);
        }
      }
      _processController.text = widget.recipe!.process;
      _servingsController.text = widget.recipe!.servings.toString();
    } else {
      // Pre-fill a new recipe from scanned data, if provided.
      if ((widget.initialName ?? '').trim().isNotEmpty) {
        _nameController.text = widget.initialName!.trim();
      }
      if ((widget.initialProcess ?? '').trim().isNotEmpty) {
        _processController.text = widget.initialProcess!.trim();
      }
      if (widget.initialIngredients != null) {
        for (final item in widget.initialIngredients!) {
          final unitVal = (item['unit'] ?? 'g').toString();
          _addIngredientRow(
            name: (item['name'] ?? '').toString(),
            qty: (item['qty'] ?? '').toString(),
            unit: _units.contains(unitVal) ? unitVal : 'g',
          );
        }
      }
    }
    if (_ingredientsList.isEmpty) {
      _addIngredientRow(unit: AppSettings.defaultUnit);
      _addIngredientRow(unit: AppSettings.defaultUnit);
    }
    if (mounted) setState(() {});
  }

  void _addIngredientRow(
      {String name = '', String qty = '', String unit = 'g'}) {
    final qtyCtrl = TextEditingController(text: qty);
    qtyCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    final nameCtrl = TextEditingController(text: name);
    String last = name;
    nameCtrl.addListener(() {
      // redraw the hint under the row when the name changes
      if (nameCtrl.text != last && mounted) {
        last = nameCtrl.text;
        setState(() {});
      }
    });
    _ingredientsList.add({
      'name': nameCtrl,
      'qty': qtyCtrl,
      'focusNode': FocusNode(),
      'unit': unit,
      'price': 0.0,
      'calories': 0.0,
    });
  }

  void _removeIngredientRow(int index) {
    if (_ingredientsList.length <= 1) {
      final row = _ingredientsList[index];
      (row['name'] as TextEditingController).clear();
      (row['qty'] as TextEditingController).clear();
      setState(() {});
      return;
    }
    final removed = _ingredientsList[index];
    setState(() => _ingredientsList.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (removed['name'] as TextEditingController).dispose();
      (removed['qty'] as TextEditingController).dispose();
      (removed['focusNode'] as FocusNode?)?.dispose();
    });
  }

  double _liveTotalGrams() {
    double t = 0;
    for (final row in _ingredientsList) {
      final q = double.tryParse((row['qty'] as TextEditingController).text) ?? 0;
      final u = row['unit'].toString().toLowerCase().trim();
      if (u == 'g' || u == 'gm' || u == 'ml') {
        t += q;
      } else if (u == 'kg' || u == 'l') {
        t += q * 1000;
      }
    }
    return t;
  }

  Future<File?> _compressImage(File file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          "${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";
      var result = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path, targetPath,
          quality: 75, minWidth: 1200, minHeight: 1200);
      return result != null ? File(result.path) : null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickImage() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Add photo",
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 17, color: _fg)),
                  InkWell(
                    onTap: () => Navigator.of(ctx).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _sourceOption(ctx, Icons.photo_library_outlined, "Gallery",
                      ImageSource.gallery),
                  _sourceOption(ctx, Icons.camera_alt_outlined, "Camera",
                      ImageSource.camera),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        File original = File(image.path);
        File? compressed = await _compressImage(original);
        setState(() => _itemPhoto = compressed ?? original);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Widget _sourceOption(
      BuildContext context, IconData icon, String label, ImageSource source) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(source),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _accentSoft, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: _accent, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w500, color: _fg)),
        ],
      ),
    );
  }

  Future<void> _showQuickAddSection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('New section'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Italian'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Create', style: TextStyle(color: _accent))),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      final trimmed = name.trim();
      if (!_sections.contains(trimmed)) {
        await DatabaseHelper().saveLocalSection({
          'name': trimmed,
          'is_system': 0,
          'icon': 'category',
          'sort_order': _sections.length,
          'created_at': DateTime.now().toIso8601String()
        });
        _apiService.createSection(trimmed).catchError((_) => null);
        setState(() {
          _sections.insert(_sections.length - 1, trimmed);
          _selectedSection = trimmed;
        });
      } else {
        setState(() => _selectedSection = trimmed);
      }
    }
  }

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
    }
  }

  void _showValidationSnack(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFC0392B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String? _ingredientRowError(int index, Map<String, dynamic> row) {
    if (!_showValidation) return null;
    final name = (row['name'] as TextEditingController).text.trim();
    final qtyText = (row['qty'] as TextEditingController).text.trim();
    final hasAnyNamed = _ingredientsList.any(
        (r) => (r['name'] as TextEditingController).text.trim().isNotEmpty);
    if (!hasAnyNamed && index == 0) {
      return 'Add at least one ingredient';
    }
    if (name.isEmpty && qtyText.isNotEmpty) {
      return 'Enter ingredient name';
    }
    if (name.isNotEmpty && (qtyText.isEmpty || (double.tryParse(qtyText) ?? 0) <= 0)) {
      return 'Enter quantity';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _showValidation = true);
    final formValid = _formKey.currentState!.validate();

    // Determine the first missing field so we can scroll & alert clearly.
    if (_nameController.text.trim().isEmpty) {
      _scrollToKey(_nameFieldKey);
      _showValidationSnack('Please enter a recipe name');
      return;
    }
    if (_selectedSection == 'Other...' && _customSectionController.text.trim().isEmpty) {
      _scrollToKey(_customSectionKey);
      _showValidationSnack('Please enter a custom section name');
      return;
    }
    for (int i = 0; i < _ingredientsList.length; i++) {
      final err = _ingredientRowError(i, _ingredientsList[i]);
      if (err != null) {
        final ingName = (_ingredientsList[i]['name'] as TextEditingController).text.trim();
        _scrollToKey(_ingredientsKey);
        _showValidationSnack(
          ingName.isNotEmpty ? '$err for "$ingName"' : err,
        );
        return;
      }
    }
    if (_processController.text.trim().isEmpty || !formValid) {
      _scrollToKey(_methodKey);
      _showValidationSnack('Please enter the cooking method');
      return;
    }
    setState(() => _isLoading = true);

    // Ingredients is the one price list. Names already in it use the list's
    // spelling; new names are NOT added on their own (the cook adds them).
    final book = PriceBook.instance;
    if (!book.loaded) await book.load();
    for (final row in _ingredientsList) {
      final c = row['name'] as TextEditingController;
      final it = book.find(c.text.trim());
      if (it != null) c.text = it['name'].toString();
    }
    final ingredientsData = _ingredientsList.map((row) {
      final name = (row['name'] as TextEditingController).text.trim();
      final it = book.find(name);
      return {
        'name': name,
        'qty': (row['qty'] as TextEditingController).text,
        'unit': row['unit'],
        // kept for older app versions; cost is always worked out from Ingredients
        'price': book.legacyPerKg(name) ?? 0.0,
        'calories': it?['calories'] ?? 0.0,
      };
    }).where((r) => (r['name'] as String).isNotEmpty).toList();

    final data = {
      'name': _nameController.text,
      'brand_name': _brandController.text,
      'section_name': _selectedSection == 'Other...'
          ? _customSectionController.text
          : _selectedSection,
      'ingredients': jsonEncode(ingredientsData),
      'process': _processController.text,
      'servings': int.tryParse(_servingsController.text) ?? 1,
      'visibility': _visibility,
    };

    String? error;
    if (widget.recipe == null) {
      error = await _apiService.createRecipe(data, itemPhotoPath: _itemPhoto?.path);
    } else {
      error = await _apiService.updateRecipe(widget.recipe!.id, data,
          itemPhotoPath: _itemPhoto?.path);
    }

    await book.load();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error == null) {
      final isEdit = widget.recipe != null;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isEdit ? 'Recipe updated' : 'Recipe saved',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF1F7A45),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      try {
        Provider.of<SyncProvider>(context, listen: false)
            .triggerAutoBackupIfEnabled();
      } catch (e) {}
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.recipe != null;
    if (_sections.isEmpty) {
      return const Scaffold(
          backgroundColor: _bg,
          body: Center(child: CircularProgressIndicator(color: _accent)));
    }
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isEdit ? 'Edit Recipe' : 'New Recipe',
                            style: const TextStyle(fontFamily: 'SpaceGrotesk',
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: _fg)),
                        const SizedBox(height: 2),
                        Text(
                            isEdit
                                ? 'Update the details below'
                                : 'Add it to your collection',
                            style: const TextStyle(fontSize: 13, color: _muted)),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _line)),
                        child: const Icon(Icons.close_rounded, color: _fg, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
                  children: [
                    if (!isEdit) ...[
                      if (_scannedPhoto != null)
                        _scanRefBanner()
                      else
                        _scanFromPhotoCta(),
                      const SizedBox(height: 14),
                    ],
                    _photoPicker(),
                    const SizedBox(height: 18),
                    _label('Recipe name'),
                    const SizedBox(height: 7),
                    KeyedSubtree(
                      key: _nameFieldKey,
                      child: _field(_nameController, 'Recipe name', 'e.g. Honey BBQ Sauce',
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Please enter a recipe name' : null),
                    ),
                    const SizedBox(height: 16),
                    _label('Section'),
                    const SizedBox(height: 7),
                    _sectionRow(),
                    if (_selectedSection == 'Other...') ...[
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: _customSectionKey,
                        child: _field(_customSectionController, 'Custom section',
                            'e.g. Italian',
                            validator: (v) => (_selectedSection == 'Other...' &&
                                    (v == null || v.trim().isEmpty))
                                ? 'Please enter a section name'
                                : null),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _label('Brand (optional)'),
                    const SizedBox(height: 7),
                    _brandField(),
                    const SizedBox(height: 16),
                    _label('Visibility'),
                    const SizedBox(height: 7),
                    _visibilitySeg(),
                    const SizedBox(height: 20),
                    Row(
                      key: _ingredientsKey,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Ingredients',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: _fg,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Servings',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(color: _line),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Semantics(
                                    button: true,
                                    label: 'Decrease servings',
                                    child: InkWell(
                                      onTap: () {
                                        final cur = int.tryParse(_servingsController.text) ?? 1;
                                        if (cur > 1) {
                                          setState(() => _servingsController.text = (cur - 1).toString());
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(13),
                                      child: const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: Icon(Icons.remove_rounded, size: 16, color: _muted),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    constraints: const BoxConstraints(minWidth: 24),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: Text(
                                      _servingsController.text.isEmpty ? '1' : _servingsController.text,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: _fg,
                                      ),
                                    ),
                                  ),
                                  Semantics(
                                    button: true,
                                    label: 'Increase servings',
                                    child: InkWell(
                                      onTap: () {
                                        final cur = int.tryParse(_servingsController.text) ?? 1;
                                        if (cur < 99) {
                                          setState(() => _servingsController.text = (cur + 1).toString());
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(13),
                                      child: const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: Icon(Icons.add_rounded, size: 16, color: _muted),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ..._ingredientsList
                        .asMap()
                        .entries
                        .map((e) => _ingredientRow(e.key, e.value)),
                    const SizedBox(height: 4),
                    _addIngredientButton(),
                    const SizedBox(height: 12),
                    _totalBar(),
                    const SizedBox(height: 18),
                    _label('Method'),
                    const SizedBox(height: 7),
                    KeyedSubtree(
                      key: _methodKey,
                      child: _field(_processController, '', 'How it\'s made…',
                          maxLines: 5,
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Please enter the cooking method' : null),
                    ),
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
                  : Text(isEdit ? 'Save changes' : 'Save recipe',
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

  Future<void> _startScanFromPhoto() async {
    if (_isScanning) return;
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Scan recipe photo',
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: _fg)),
                  InkWell(
                    onTap: () => Navigator.of(ctx).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Pick a handwritten note or printed recipe photo. Recipia reads the items & quantities so you can check and save.',
                style: TextStyle(fontSize: 13, height: 1.4, color: _muted),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _sourceOption(ctx, Icons.camera_alt_outlined, 'Camera',
                      ImageSource.camera),
                  _sourceOption(ctx, Icons.photo_library_outlined, 'Gallery',
                      ImageSource.gallery),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final XFile? picked = await _picker.pickImage(source: source);
      if (picked == null || !mounted) return;
      final original = File(picked.path);
      final compressed = await _compressImage(original) ?? original;

      setState(() => _isScanning = true);
      Map<String, dynamic> result;
      try {
        result = await _apiService.analyzeRecipeImage(compressed.path);
      } catch (_) {
        // Fallback to 100% offline on-device ML Kit OCR using the sharp original photo
        result = await RecipeOcrService.scanPhoto(original.path);
      }
      if (!mounted) return;
      setState(() => _isScanning = false);

      await _showScanReviewSheet(original, result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFB42318),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showScanReviewSheet(
      File photo, Map<String, dynamic> data) async {
    final rawIngs = (data['ingredients'] is List)
        ? (data['ingredients'] as List)
        : const [];
    final items = rawIngs
        .whereType<Map>()
        .map((m) => {
              'name': (m['name'] ?? '').toString().trim(),
              'qty': (m['qty'] ?? '').toString().trim(),
              'unit': (m['unit'] ?? 'g').toString().trim().toLowerCase(),
              'on': true,
            })
        .where((m) => (m['name'] as String).isNotEmpty)
        .toList();

    final title = (data['name'] ?? '').toString().trim();
    final isOffline = data['_source'] == 'offline_ocr';
    final rawText = (data['_rawText'] ?? '').toString().trim();
    bool showRaw = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title.isNotEmpty
                            ? 'Scanned: $title'
                            : 'Review scanned items',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _fg),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(ctx, false),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _line),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: _muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Found ${items.length} ingredient${items.length == 1 ? '' : 's'} (${isOffline ? 'Offline OCR' : 'AI Vision'}) — uncheck any to skip.',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _accent),
                        ),
                      ),
                      if (rawText.isNotEmpty)
                        InkWell(
                          onTap: () => setS(() => showRaw = !showRaw),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              showRaw ? 'Hide text' : 'Raw text',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _accent,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showRaw && rawText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 110),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _line),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        rawText,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: _muted,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _line),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: _accent,
                        value: it['on'] as bool,
                        onChanged: (v) => setS(() => it['on'] = v ?? true),
                        title: Text(it['name'].toString(),
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: _fg)),
                        secondary: Text(
                          '${it['qty']} ${it['unit']}'.trim(),
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _accent),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Fill form to check & save',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final picked = items.where((x) => x['on'] == true).toList();
    setState(() {
      _scannedPhoto = photo;
      if (title.isNotEmpty) _nameController.text = title;
      final brand = (data['brand_name'] ?? '').toString().trim();
      if (brand.isNotEmpty) _brandController.text = brand;
      final sec = (data['section_name'] ?? '').toString().trim();
      if (sec.isNotEmpty && _sections.contains(sec)) {
        _selectedSection = sec;
      }
      final process = (data['process'] ?? '').toString().trim();
      if (process.isNotEmpty) _processController.text = process;
      if (picked.isNotEmpty) {
        _ingredientsList.clear();
        for (final it in picked) {
          final rawU = it['unit'].toString();
          final normU = rawU == 'gm'
              ? 'g'
              : rawU == 'pcs'
                  ? 'piece'
                  : rawU;
          _addIngredientRow(
            name: it['name'].toString(),
            qty: it['qty'].toString(),
            unit: _units.contains(normU) ? normU : 'g',
          );
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Filled ${picked.length} items — check qty & tap Save'),
      backgroundColor: _accent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _openScannedPhotoZoom() {
    if (_scannedPhoto == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.file(_scannedPhoto!, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: InkWell(
                onTap: () => Navigator.pop(ctx),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanFromPhotoCta() {
    return GestureDetector(
      onTap: _isScanning ? null : _startScanFromPhoto,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isScanning
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.2),
                    )
                  : const Icon(Icons.document_scanner_outlined,
                      color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isScanning ? 'Reading recipe photo…' : 'Scan from photo',
                    style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isScanning
                        ? 'Extracting items, quantities & units'
                        : 'Read recipe items & qty from your phone',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _scanRefBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openScannedPhotoZoom,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(_scannedPhoto!,
                  width: 44, height: 44, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filled from your photo',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _accent)),
                SizedBox(height: 1),
                Text('Tap photo to compare · check qty & save',
                    style: TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => _scannedPhoto = null),
            borderRadius: BorderRadius.circular(14),
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Icon(Icons.close_rounded, size: 16, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPicker() {
    ImageProvider? img;
    if (_itemPhoto != null) {
      img = FileImage(_itemPhoto!);
    } else if (widget.recipe?.itemPhoto != null) {
      img = CachedNetworkImageProvider(
          ApiService.getImageUrl(widget.recipe!.itemPhoto!));
    }
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
          image: img != null
              ? DecorationImage(image: img, fit: BoxFit.cover)
              : null,
        ),
        child: img != null
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_a_photo_outlined, color: _muted, size: 26),
                  SizedBox(height: 6),
                  Text('Add a photo',
                      style: TextStyle(color: _muted, fontSize: 13)),
                ],
              ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: _muted));

  Widget _field(TextEditingController c, String label, String hint,
      {int maxLines = 1,
      bool dense = false,
      TextInputType? keyboardType,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      autovalidateMode: _showValidation
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      style: const TextStyle(fontSize: 15, color: _fg),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 15),
        errorStyle: const TextStyle(
            color: Color(0xFFC0392B), fontSize: 12.5, fontWeight: FontWeight.w600),
        filled: true,
        fillColor: _surface,
        isDense: dense,
        contentPadding: EdgeInsets.symmetric(
            horizontal: 14, vertical: dense ? 10 : 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _accent, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC0392B), width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC0392B), width: 1.8)),
      ),
    );
  }

  Widget _sectionRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSection,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded, color: _muted),
                style: const TextStyle(fontSize: 15, color: _fg),
                dropdownColor: _surface,
                items: _sections
                    .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedSection = v!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _showQuickAddSection,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accent)),
            child: const Icon(Icons.add_rounded, color: _accent),
          ),
        ),
      ],
    );
  }

  bool _addingBrand = false;
  final _newBrandCtl = TextEditingController();

  void _addBrand() {
    final v = _newBrandCtl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      if (!_availableBrands.any((b) => b.toLowerCase() == v.toLowerCase())) {
        _availableBrands = [..._availableBrands, v]..sort();
      }
      _brandController.text =
          _availableBrands.firstWhere((b) => b.toLowerCase() == v.toLowerCase());
      _newBrandCtl.clear();
      _addingBrand = false;
    });
  }

  InputDecoration _boxDeco([String? hint]) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 15),
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _accent, width: 1.5)),
      );

  Widget _brandField() {
    final current = _brandController.text.trim();
    final brands = {
      ..._availableBrands.where((b) => b.trim().isNotEmpty),
      if (current.isNotEmpty) current,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Column(children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: current,
            isExpanded: true,
            icon: const Icon(Icons.expand_more_rounded, color: _muted),
            style: const TextStyle(fontSize: 15, color: _fg),
            dropdownColor: _surface,
            decoration: _boxDeco(),
            items: [
              const DropdownMenuItem(value: '', child: Text('No brand')),
              ...brands.map((b) => DropdownMenuItem(value: b, child: Text(b))),
            ],
            onChanged: (v) => setState(() => _brandController.text = v ?? ''),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Add brand',
          child: GestureDetector(
            onTap: () => setState(() => _addingBrand = !_addingBrand),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _accent)),
              child: Icon(_addingBrand ? Icons.close_rounded : Icons.add_rounded,
                  color: _accent),
            ),
          ),
        ),
      ]),
      if (_addingBrand) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _newBrandCtl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _addBrand(),
              style: const TextStyle(fontSize: 15, color: _fg),
              decoration: _boxDeco('New brand name'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _addBrand,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ],
    ]);
  }

  Widget _visibilitySeg() {
    final opts = {'private': 'Private', 'friends': 'Friends', 'public': 'Public'};
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line)),
      child: Row(
        children: opts.entries.map((e) {
          final on = _visibility == e.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _visibility = e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: on ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(e.value,
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

  /// What will happen to this line: found (with its price), "did you mean", or new.
  Widget _rowHint(Map<String, dynamic> row) {
    final c = row['name'] as TextEditingController;
    final name = c.text.trim();
    if (name.isEmpty) return const SizedBox.shrink();
    final book = PriceBook.instance;
    final it = book.find(name);
    const small = TextStyle(fontSize: 12, height: 1.3);
    if (it != null) {
      final price = it['price'];
      if (price == null) {
        return const Text('In Ingredients · no price yet',
            style: TextStyle(fontSize: 12, color: _warn, fontWeight: FontWeight.w600));
      }
      final q = double.tryParse((row['qty'] as TextEditingController).text) ?? 0;
      final lc = q > 0 ? book.lineCost(name, q, row['unit'].toString()) : null;
      final cal = it['calories'];
      final p = (price as num).toDouble();
      return Text(
          [
            '${AppSettings.currency}${p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(1)}/${it['unit'] ?? 'kg'}',
            if (lc != null) 'this line ${AppSettings.currency}${lc.round()}',
            if (cal != null && (cal as num) > 0) '${cal.round()} cal/100g',
          ].join(' · '),
          style: small.copyWith(color: _accent));
    }
    final sim = book.similar(name);
    if (sim != null) {
      return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        const Text('Did you mean', style: TextStyle(fontSize: 12, color: _muted)),
        GestureDetector(
          onTap: () => setState(() => c.text = sim['name'].toString()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent)),
            child: Text(sim['name'].toString(),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: _accent)),
          ),
        ),
        const Text('? Otherwise it’s saved as you wrote it.',
            style: TextStyle(fontSize: 12, color: _muted)),
      ]);
    }
    return const Text('Not in Ingredients · no price (add it there if you want a cost)',
        style: TextStyle(fontSize: 12, color: _warn));
  }

  Widget _ingredientRow(int index, Map<String, dynamic> row) {
    const dividerColor = Color(0xFFF0EDE6);
    const placeholderColor = Color(0xFF9CA3AF);
    const errColor = Color(0xFFC0392B);
    final rowError = _ingredientRowError(index, row);
    final hasErr = rowError != null;
    final hintWidget = _rowHint(row);

    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: hasErr ? const Color(0xFFFFF5F5) : _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasErr ? errColor : _line,
                width: hasErr ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                // Row 1: Full-width Ingredient Name + Remove icon
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 4),
                          child: _ingredientAutocomplete(row),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Remove ingredient',
                        child: InkWell(
                          onTap: () => _removeIngredientRow(index),
                          borderRadius: BorderRadius.circular(16),
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(Icons.close_rounded, color: _muted, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                // 1px Horizontal Hairline Divider
                const Divider(height: 1, thickness: 1, color: dividerColor),
                // Row 2: 50% Qty + 50% Unit
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      // Left 50%: Qty
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Text(
                                'Qty',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: row['qty'],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: _fg,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: '0',
                                    hintStyle: TextStyle(
                                      color: placeholderColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 1px Vertical Hairline Divider
                      Container(width: 1, height: 48, color: dividerColor),
                      // Right 50%: Unit dropdown
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _units.contains(row['unit']) ? row['unit'] : 'g',
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: _muted,
                                size: 20,
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                color: _fg,
                                fontWeight: FontWeight.w400,
                              ),
                              items: _units
                                  .map((u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(u, style: const TextStyle(fontSize: 16)),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => row['unit'] = v),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasErr)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: errColor),
                  const SizedBox(width: 4),
                  Text(
                    rowError,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: errColor,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
              child: hintWidget,
            ),
        ],
      ),
    );
  }

  Widget _ingredientAutocomplete(Map<String, dynamic> row) {
    const placeholderColor = Color(0xFF9CA3AF);
    final nameCtrl = row['name'] as TextEditingController;
    final focusNode = (row['focusNode'] as FocusNode?) ?? FocusNode();
    row['focusNode'] = focusNode;

    return RawAutocomplete<String>(
      key: ObjectKey(row),
      textEditingController: nameCtrl,
      focusNode: focusNode,
      optionsBuilder: (v) => v.text.isEmpty
          ? const Iterable<String>.empty()
          : (PriceBook.instance.items.isNotEmpty
                  ? PriceBook.instance.items
                  : _allPantryIngredients)
              .map((i) => i['name'].toString())
              .toSet()
              .where((n) => n.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: (s) {
        setState(() => nameCtrl.text = s);
      },
      fieldViewBuilder: (context, c, fn, onSub) {
        return TextField(
          controller: c,
          focusNode: fn,
          style: const TextStyle(fontSize: 16, color: _fg, fontWeight: FontWeight.w400),
          decoration: const InputDecoration(
            hintText: 'Ingredient name',
            hintStyle: TextStyle(
              color: placeholderColor,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(opt, style: const TextStyle(fontSize: 14.5, color: _fg)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _addIngredientButton() {
    return Semantics(
      button: true,
      label: 'Add ingredient',
      child: InkWell(
        onTap: () => setState(
            () => _addIngredientRow(unit: AppSettings.defaultUnit)),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF6EDE8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.add_rounded, color: _accent, size: 18),
              SizedBox(width: 6),
              Text(
                'Add ingredient',
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalBar() {
    final g = _liveTotalGrams();
    final gs = g % 1 == 0 ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
    final lines = _ingredientsList
        .map((r) => RecipeLine(
            (r['name'] as TextEditingController).text.trim(),
            double.tryParse((r['qty'] as TextEditingController).text) ?? 0,
            r['unit'].toString()))
        .where((l) => l.name.isNotEmpty)
        .toList();
    final sum = PriceBook.instance.summarize(widget.recipe?.id ?? -1, lines);
    final costText = lines.isEmpty
        ? '—'
        : '${AppSettings.currency}${sum.total.round()}${sum.missing > 0 ? ' · ${sum.missing} without price' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: _accentSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total batch weight',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _accent)),
            const SizedBox(height: 3),
            Text('Est. cost $costText',
                style: const TextStyle(fontSize: 12, color: _accent)),
          ]),
          Text('$gs g',
              style: const TextStyle(fontFamily: 'SpaceGrotesk',
                  fontSize: 18, fontWeight: FontWeight.w800, color: _accent)),
        ],
      ),
    );
  }
}
