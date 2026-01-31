import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api_service.dart';
import '../database_helper.dart';
import '../models/recipe.dart';
import '../sync_provider.dart';

class RecipeFormScreen extends StatefulWidget {
  final Recipe? recipe;

  const RecipeFormScreen({super.key, this.recipe});

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _apiService = ApiService();
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  // Basic Info
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  String _selectedSection = 'Other...';

  // Photos
  File? _itemPhoto;
  File? _recipePhoto;
  final _picker = ImagePicker();

  // Ingredients
  final List<Map<String, dynamic>> _ingredientsList = [];

  // Process
  final _processController = TextEditingController();

  final List<String> _sections = [];
  List<String> _availableBrands = [];

  final List<String> _units = [
    'g',
    'kg',
    'ml',
    'l',
    'cup',
    'tbsp',
    'tsp',
    'oz',
    'lb',
    'piece',
    'pinch',
    'Other...'
  ];

  final _customSectionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  Future<void> _initForm() async {
    // Load local sections first
    try {
      final localSections = await DatabaseHelper().getLocalSections();
      final brands = await DatabaseHelper().getUniqueBrands();

      if (mounted) {
        setState(() {
          _sections.clear();
          for (var s in localSections) {
            _sections.add(s['name']);
          }
          if (!_sections.contains('Other...')) {
            _sections.add('Other...');
          }

          _availableBrands = brands;

          _selectedSection =
              _sections.isNotEmpty ? _sections.first : 'Other...';

          if (widget.recipe != null) {
            if (_sections.contains(widget.recipe!.sectionName)) {
              _selectedSection = widget.recipe!.sectionName;
            } else {
              _selectedSection = 'Other...';
              _customSectionController.text = widget.recipe!.sectionName;
            }
          }
        });
      }

      // Sync from API in background
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
            if (!_sections.contains('Other...')) {
              _sections.add('Other...');
            }

            if (widget.recipe != null) {
              if (_sections.contains(widget.recipe!.sectionName)) {
                _selectedSection = widget.recipe!.sectionName;
              }
            }
          });
        }
      }
    } catch (e) {
      if (mounted && _sections.isEmpty) {
        setState(() {
          _sections.addAll([
            'Hot Kitchen',
            'Bakery',
            'Pastry',
            'Sweet',
            'Sauce',
            'Cold/Salad',
            'Pizza',
            'Breakfast',
            'Appetizers',
            'Main Course',
            'Desserts',
            'Beverages',
            'Seafood',
            'Soup',
            'Sides',
            'Vegetarian',
            'Vegan',
            'Other...'
          ]);
          _selectedSection = _sections.first;
        });
      }
    }

    _addIngredientRow();

    if (widget.recipe != null) {
      _nameController.text = widget.recipe!.name;
      _brandController.text = widget.recipe!.brandName ?? '';

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
                  unit: _units.contains(unitVal) ? unitVal : 'Other...',
                  customUnit: _units.contains(unitVal) ? null : unitVal);
            }
          }
        } catch (e) {
          _ingredientsList.clear();
          _addIngredientRow(name: widget.recipe!.ingredients);
        }
      }

      _processController.text = widget.recipe!.process;
    }
  }

  void _addIngredientRow(
      {String name = '',
      String qty = '',
      String unit = 'g',
      String? customUnit}) {
    setState(() {
      _ingredientsList.add({
        'name': TextEditingController(text: name),
        'qty': TextEditingController(text: qty),
        'unit': unit,
        'customUnit': TextEditingController(text: customUnit ?? ''),
      });
    });
  }

  void _removeIngredientRow(int index) {
    if (_ingredientsList.length > 1) {
      setState(() {
        _ingredientsList.removeAt(index);
      });
    }
  }

  Future<File?> _compressImage(File file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          "${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg";
      var result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 75,
        minWidth: 1200,
        minHeight: 1200,
      );
      return result != null ? File(result.path) : null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickImage(bool isItem) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Select Source",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSourceOption(context, Icons.photo_library, "Gallery",
                        ImageSource.gallery),
                    _buildSourceOption(context, Icons.camera_alt, "Camera",
                        ImageSource.camera),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        File originalFile = File(image.path);
        File? compressedFile = await _compressImage(originalFile);
        setState(() {
          if (isItem) {
            _itemPhoto = compressedFile ?? originalFile;
          } else {
            _recipePhoto = compressedFile ?? originalFile;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Widget _buildSourceOption(
      BuildContext context, IconData icon, String label, ImageSource source) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(source),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: const Color(0xFFE74C3C), size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _showQuickAddSection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Section'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Italian'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      final trimmedName = name.trim();
      if (!_sections.contains(trimmedName)) {
        setState(() => _isLoading = true);
        await DatabaseHelper().saveLocalSection({
          'name': trimmedName,
          'is_system': 0,
          'icon': 'category',
          'sort_order': _sections.length,
          'created_at': DateTime.now().toIso8601String()
        });
        _apiService.createSection(trimmedName).catchError((_) => null);
        await _initForm();
        setState(() {
          _selectedSection = trimmedName;
          _isLoading = false;
        });
      } else {
        setState(() => _selectedSection = trimmedName);
      }
    }
  }

  Future<void> _scanWithAI() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Scan Paper Recipe",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                const Text(
                    "Take a photo of your handwritten recipe to auto-fill",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSourceOption(context, Icons.photo_library, "Gallery",
                        ImageSource.gallery),
                    _buildSourceOption(context, Icons.camera_alt, "Camera",
                        ImageSource.camera),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() => _isLoading = true);

      final result = await _apiService.analyzeRecipeImage(image.path);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result != null) {
        setState(() {
          _nameController.text = result['name'] ?? _nameController.text;
          _brandController.text = result['brand_name'] ?? _brandController.text;

          if (result['section_name'] != null) {
            String section = result['section_name'];
            if (_sections.contains(section)) {
              _selectedSection = section;
            } else {
              _selectedSection = 'Other...';
              _customSectionController.text = section;
            }
          }

          if (result['ingredients'] is List) {
            _ingredientsList.clear();
            for (var item in result['ingredients']) {
              String unit = item['unit'] ?? 'g';
              if (_units.contains(unit)) {
                _addIngredientRow(
                  name: item['name'] ?? '',
                  qty: (item['qty'] ?? '').toString(),
                  unit: unit,
                );
              } else {
                _addIngredientRow(
                  name: item['name'] ?? '',
                  qty: (item['qty'] ?? '').toString(),
                  unit: 'Other...',
                  customUnit: unit,
                );
              }
            }
            if (_ingredientsList.isEmpty) _addIngredientRow();
          }

          _processController.text =
              result['process'] ?? _processController.text;
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Form auto-filled! Please check and save."),
            backgroundColor: Color(0xFF27AE60)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("AI Scan failed. Is GEMINI_API_KEY set?"),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final ingredientsData = _ingredientsList
        .map((row) => {
              'name': (row['name'] as TextEditingController).text,
              'qty': (row['qty'] as TextEditingController).text,
              'unit': row['unit'] == 'Other...'
                  ? (row['customUnit'] as TextEditingController).text
                  : row['unit'],
            })
        .toList();

    final data = {
      'name': _nameController.text,
      'brand_name': _brandController.text,
      'section_name': _selectedSection == 'Other...'
          ? _customSectionController.text
          : _selectedSection,
      'ingredients': jsonEncode(ingredientsData),
      'process': _processController.text,
      'visibility': 'private',
    };

    String? error;
    if (widget.recipe == null) {
      error = await _apiService.createRecipe(data,
          itemPhotoPath: _itemPhoto?.path, recipePhotoPath: _recipePhoto?.path);
    } else {
      error = await _apiService.updateRecipe(widget.recipe!.id, data,
          itemPhotoPath: _itemPhoto?.path, recipePhotoPath: _recipePhoto?.path);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      Navigator.of(context).pop(true);
      try {
        final syncProvider = Provider.of<SyncProvider>(context, listen: false);
        syncProvider.triggerAutoBackupIfEnabled();
      } catch (e) {}
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading || _sections.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionCard(
                            title: "Basic Details",
                            icon: Icons.info_outline,
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _nameController,
                                  label: "Recipe Title",
                                  hint: "e.g. Grandma's Apple Pie",
                                  icon: Icons.restaurant_menu,
                                  validator: (v) =>
                                      v!.isEmpty ? "Required" : null,
                                ),
                                const SizedBox(height: 16),
                                _buildAutocompleteField(
                                  controller: _brandController,
                                  label: "Brand / Source",
                                  hint: "Optional",
                                  icon: Icons.label_outline,
                                  options: _availableBrands,
                                ),
                                const SizedBox(height: 16),
                                _buildDropdown(
                                  value: _selectedSection,
                                  label: "Section",
                                  icon: Icons.category_outlined,
                                  items: _sections,
                                  onChanged: (v) =>
                                      setState(() => _selectedSection = v!),
                                  onAddPressed: _showQuickAddSection,
                                ),
                                if (_selectedSection == 'Other...') ...[
                                  const SizedBox(height: 12),
                                  _buildTextField(
                                    controller: _customSectionController,
                                    label: "Custom Section Name",
                                    hint: "e.g. Italian, Fast Food",
                                    icon: Icons.edit_note,
                                    validator: (v) =>
                                        (_selectedSection == 'Other...' &&
                                                (v == null || v.isEmpty))
                                            ? "Required"
                                            : null,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildSectionCard(
                            title: "Ingredients",
                            icon: Icons.list_alt_rounded,
                            child: Column(
                              children: [
                                ..._ingredientsList.asMap().entries.map(
                                    (e) => _buildIngredientRow(e.key, e.value)),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: () => _addIngredientRow(),
                                  icon: const Icon(Icons.add_circle_outline),
                                  label: const Text("Add Ingredient"),
                                  style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFFE74C3C)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildSectionCard(
                            title: "Instructions",
                            icon: Icons.menu_book_outlined,
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _processController,
                                  label: "Cooking Process",
                                  hint: "Step by step instructions...",
                                  maxLines: 8,
                                  validator: (v) =>
                                      v!.isEmpty ? "Required" : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isLoading
          ? null
          : Container(
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE74C3C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.save_outlined),
                    const SizedBox(width: 8),
                    Text(
                      widget.recipe == null ? "SAVE RECIPE" : "UPDATE RECIPE",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAppBar() {
    ImageProvider? image;
    if (_recipePhoto != null) {
      image = FileImage(_recipePhoto!);
    } else if (widget.recipe?.recipePhoto != null) {
      image = CachedNetworkImageProvider(
          ApiService.getImageUrl(widget.recipe!.recipePhoto!));
    }

    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      backgroundColor: const Color(0xFFE74C3C),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              Image(image: image, fit: BoxFit.cover)
            else
              Container(
                color: Colors.grey.shade200,
                child: Icon(Icons.restaurant,
                    size: 80, color: Colors.grey.shade400),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton.small(
                onPressed: () => _pickImage(false),
                backgroundColor: Colors.white,
                child: const Icon(Icons.camera_alt, color: Color(0xFFE74C3C)),
              ),
            ),
          ],
        ),
      ),
      leading: IconButton(
        icon: const CircleAvatar(
          backgroundColor: Colors.white24,
          child: Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: TextButton.icon(
            onPressed: _scanWithAI,
            icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            label: const Text("AI SCAN",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white24,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFFE74C3C)),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF2D3748))),
            ],
          ),
          const Divider(height: 30),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE74C3C)),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
    VoidCallback? onAddPressed,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items:
          items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: onAddPressed != null
            ? IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: Color(0xFFE74C3C), size: 22),
                onPressed: onAddPressed,
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
      ),
    );
  }

  Widget _buildAutocompleteField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required List<String> options,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        return options.where((String option) {
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder:
          (context, fieldController, focusNode, onFieldSubmitted) {
        // Keep the main controller in sync
        fieldController.addListener(() {
          controller.text = fieldController.text;
        });
        return _buildTextField(
          controller: fieldController,
          label: label,
          hint: hint,
          icon: icon,
        );
      },
    );
  }

  Widget _buildIngredientRow(int index, Map<String, dynamic> row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Item #${index + 1}",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade400)),
              IconButton(
                onPressed: () => _removeIngredientRow(index),
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.redAccent, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: row['name'],
            label: "Ingredient",
            hint: "e.g. Extra Virgin Olive Oil",
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: row['qty'],
                  label: "Qty",
                  hint: "0",
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: row['unit'],
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, color: Colors.black),
                  decoration: InputDecoration(
                    labelText: "Unit",
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  items: _units
                      .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setState(() => row['unit'] = v),
                ),
              ),
            ],
          ),
          if (row['unit'] == 'Other...') ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: row['customUnit'],
              label: "Custom Unit",
              hint: "e.g. box, bottle",
              icon: Icons.straighten,
              validator: (v) =>
                  (row['unit'] == 'Other...' && (v == null || v.isEmpty))
                      ? "Required"
                      : null,
            ),
          ],
        ],
      ),
    );
  }
}
