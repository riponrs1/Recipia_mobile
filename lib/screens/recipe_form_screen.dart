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
  late String _selectedSection;

  // Photos
  File? _itemPhoto;
  File? _recipePhoto;
  final _picker = ImagePicker();

  // Ingredients
  final List<Map<String, dynamic>> _ingredientsList = [];

  // Process & Visibility
  final _processController = TextEditingController();
  String _visibility = 'private';

  final List<String> _sections = [
    'Hot Kitchen',
    'Bakery',
    'Pastry',
    'Sweet',
    'Sauce',
    'Cold/Salad',
    'Pizza'
  ];

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
    'pinch'
  ];

  @override
  void initState() {
    super.initState();
    _selectedSection = _sections.first;
    _addIngredientRow();

    if (widget.recipe != null) {
      _nameController.text = widget.recipe!.name;
      _brandController.text = widget.recipe!.brandName ?? '';
      if (_sections.contains(widget.recipe!.sectionName)) {
        _selectedSection = widget.recipe!.sectionName;
      }

      if (widget.recipe!.ingredients.isNotEmpty) {
        try {
          final decoded = jsonDecode(widget.recipe!.ingredients);
          if (decoded is List) {
            _ingredientsList.clear();
            for (var item in decoded) {
              _addIngredientRow(
                  name: item['name'] ?? '',
                  qty: (item['qty'] ?? '').toString(),
                  unit: item['unit'] ?? 'g');
            }
          }
        } catch (e) {
          _ingredientsList.clear();
          _addIngredientRow(name: widget.recipe!.ingredients);
        }
      }

      _processController.text = widget.recipe!.process;
      _visibility = widget.recipe!.visibility ?? 'private';
    }
  }

  void _addIngredientRow(
      {String name = '', String qty = '', String unit = 'g'}) {
    setState(() {
      _ingredientsList.add({
        'name': TextEditingController(text: name),
        'qty': TextEditingController(text: qty),
        'unit': unit,
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final ingredientsData = _ingredientsList
        .map((row) => {
              'name': (row['name'] as TextEditingController).text,
              'qty': (row['qty'] as TextEditingController).text,
              'unit': row['unit'],
            })
        .toList();

    final data = {
      'name': _nameController.text,
      'brand_name': _brandController.text,
      'section_name': _selectedSection,
      'ingredients': jsonEncode(ingredientsData),
      'process': _processController.text,
      'visibility': _visibility,
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
      body: _isLoading
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
                                _buildTextField(
                                  controller: _brandController,
                                  label: "Brand / Source",
                                  hint: "Optional",
                                  icon: Icons.label_outline,
                                ),
                                const SizedBox(height: 16),
                                _buildDropdown(
                                  value: _selectedSection,
                                  label: "Section",
                                  icon: Icons.category_outlined,
                                  items: _sections,
                                  onChanged: (v) =>
                                      setState(() => _selectedSection = v!),
                                ),
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
                                const SizedBox(height: 16),
                                _buildDropdown(
                                  value: _visibility,
                                  label: "Visibility",
                                  icon: Icons.lock_outline,
                                  items: ['public', 'friends', 'private'],
                                  onChanged: (v) =>
                                      setState(() => _visibility = v!),
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
                    const Icon(Icons.cloud_upload_outlined),
                    const SizedBox(width: 8),
                    Text(
                      widget.recipe == null
                          ? "PUBLISH RECIPE"
                          : "UPDATE RECIPE",
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
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items:
          items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
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

  Widget _buildIngredientRow(int index, Map<String, dynamic> row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _buildTextField(
              controller: row['name'],
              label: "Name",
              hint: "Item",
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildTextField(
              controller: row['qty'],
              label: "Qty",
              hint: "0",
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: row['unit'],
              style: const TextStyle(fontSize: 12, color: Colors.black),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => row['unit'] = v),
            ),
          ),
          IconButton(
            onPressed: () => _removeIngredientRow(index),
            icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
