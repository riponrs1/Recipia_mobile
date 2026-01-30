import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../api_service.dart';
import '../models/recipe.dart';

class RecipeFormScreen extends StatefulWidget {
  final Recipe? recipe;

  const RecipeFormScreen({super.key, this.recipe});

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final _apiService = ApiService();
  bool _isLoading = false;
  int _currentStep = 0;

  // Form Key (Main one for the whole process)
  final _formKey = GlobalKey<FormState>();

  // Basic Info
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();

  // Photos
  File? _itemPhoto;
  File? _recipePhoto;
  final _picker = ImagePicker();

  // Ingredients
  // List of maps {name: controller, qty: controller, unit: value}
  final List<Map<String, dynamic>> _ingredientsList = [];

  // Process & Visibility
  final _processController = TextEditingController();
  String _visibility = 'private';

  late String _selectedSection;
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

    // Default ingredients row
    _addIngredientRow();

    if (widget.recipe != null) {
      _nameController.text = widget.recipe!.name;
      _brandController.text = widget.recipe!.brandName ?? '';
      if (_sections.contains(widget.recipe!.sectionName)) {
        _selectedSection = widget.recipe!.sectionName;
      }

      // Populate Ingredients
      if (widget.recipe!.ingredients.isNotEmpty) {
        try {
          final decoded = jsonDecode(widget.recipe!.ingredients);
          if (decoded is List) {
            _ingredientsList.clear();
            for (var item in decoded) {
              _addIngredientRow(
                  name: item['name'] ?? '',
                  qty: (item['qty'] ?? '').toString(),
                  unit: item['unit'] ?? '');
            }
          }
          if (_ingredientsList.isEmpty) _addIngredientRow();
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
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      bool granted = false;
      if (Platform.isAndroid) {
        if (source == ImageSource.camera) {
          final status = await Permission.camera.request();
          granted = status.isGranted;
        } else {
          Map<Permission, PermissionStatus> statuses = await [
            Permission.photos,
            Permission.storage,
          ].request();
          if ((statuses[Permission.photos]?.isGranted ?? false) ||
              (statuses[Permission.storage]?.isGranted ?? false)) {
            granted = true;
          }
        }
      } else {
        final status = source == ImageSource.camera
            ? await Permission.camera.request()
            : await Permission.photos.request();
        granted = status.isGranted || status.isLimited;
      }

      if (!granted && Platform.isAndroid && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permission not granted. Action might fail.')));
      }

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form')),
      );
      return;
    }

    bool hasValidIngredient = _ingredientsList.any(
        (row) => (row['name'] as TextEditingController).text.trim().isNotEmpty);

    if (!hasValidIngredient) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one ingredient')),
      );
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recipe saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_currentStep > 0) {
          setState(() => _currentStep--);
        } else {
          final shouldPop = await _confirmDiscard();
          if (shouldPop && mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text(widget.recipe == null ? 'Create Recipe' : 'Edit Recipe'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Stepper(
                  type: StepperType.horizontal,
                  currentStep: _currentStep,
                  elevation: 0,
                  onStepContinue: () {
                    // Step 0: Info Validation
                    if (_currentStep == 0) {
                      if (_nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please enter a recipe name')),
                        );
                        return;
                      }

                      setState(() => _currentStep++);
                    }
                    // Step 1: Items Validation
                    else if (_currentStep == 1) {
                      bool hasValid = _ingredientsList.any((row) =>
                          (row['name'] as TextEditingController)
                              .text
                              .trim()
                              .isNotEmpty);
                      if (!hasValid) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Please add at least one ingredient')),
                        );
                        return;
                      }
                      setState(() => _currentStep++);
                    } else {
                      _submit();
                    }
                  },
                  onStepCancel: () async {
                    if (_currentStep > 0) {
                      setState(() => _currentStep--);
                    } else {
                      final shouldPop = await _confirmDiscard();
                      if (shouldPop && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  controlsBuilder: (context, details) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: details.onStepContinue,
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE74C3C),
                                  minimumSize: const Size(0, 48)),
                              child: Text(_currentStep == 2 ? 'FINISH' : 'NEXT',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: details.onStepCancel,
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48)),
                              child:
                                  Text(_currentStep == 0 ? 'CANCEL' : 'BACK'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  steps: [
                    // Step 1: Info
                    Step(
                      title: const Text('Info'),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0
                          ? StepState.complete
                          : StepState.editing,
                      content: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Recipe Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.book),
                            ),
                            validator: (v) => v!.trim().isEmpty
                                ? 'Recipe name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _brandController,
                            decoration: const InputDecoration(
                              labelText: 'Brand (Optional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.branding_watermark),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedSection,
                            decoration: const InputDecoration(
                              labelText: 'Section',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.category),
                            ),
                            items: _sections
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedSection = v!),
                          ),
                          const SizedBox(height: 16),
                          _buildPhotoPicker(
                              title: 'Item Photo',
                              file: _itemPhoto,
                              existingUrl: widget.recipe?.itemPhoto,
                              isItem: true),
                          const SizedBox(height: 16),
                          _buildPhotoPicker(
                              title: 'Recipe Photo',
                              file: _recipePhoto,
                              existingUrl: widget.recipe?.recipePhoto,
                              isItem: false),
                        ],
                      ),
                    ),

                    // Step 2: Ingredients
                    Step(
                      title: const Text('Items'),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1
                          ? StepState.complete
                          : StepState.editing,
                      content: Column(
                        children: [
                          ..._ingredientsList.asMap().entries.map((entry) {
                            int index = entry.key;
                            Map<String, dynamic> row = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              color: Colors.grey.shade50,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side:
                                      BorderSide(color: Colors.grey.shade200)),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  children: [
                                    // Row 1: Name and Delete Link
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: row['name'],
                                            decoration: const InputDecoration(
                                              labelText: 'Ingredient Name',
                                              prefixIcon:
                                                  Icon(Icons.restaurant),
                                              border: OutlineInputBorder(),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12),
                                            ),
                                            validator: (v) =>
                                                v == null || v.trim().isEmpty
                                                    ? 'Required'
                                                    : null,
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8.0),
                                          child: IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red),
                                            onPressed: () =>
                                                _removeIngredientRow(index),
                                            tooltip: 'Remove',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Row 2: Quantity and Unit
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: row['qty'],
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Quantity',
                                              border: OutlineInputBorder(),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12),
                                            ),
                                            validator: (v) =>
                                                v == null || v.trim().isEmpty
                                                    ? 'Required'
                                                    : null,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child:
                                              DropdownButtonFormField<String>(
                                            value: row['unit'],
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Unit',
                                              border: OutlineInputBorder(),
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12),
                                            ),
                                            items: _units
                                                .map((u) => DropdownMenuItem(
                                                    value: u, child: Text(u)))
                                                .toList(),
                                            onChanged: (v) =>
                                                setState(() => row['unit'] = v),
                                          ),
                                        ),
                                        // Balance the delete button space from above
                                        const SizedBox(width: 48),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _addIngredientRow,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Ingredient'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFE74C3C),
                              side: const BorderSide(color: Color(0xFFE74C3C)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Step 3: Process
                    Step(
                      title: const Text('Done'),
                      isActive: _currentStep >= 2,
                      state: StepState.editing,
                      content: Column(
                        children: [
                          TextFormField(
                            controller: _processController,
                            decoration: const InputDecoration(
                              labelText: 'Process / Method',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                              hintText: 'Describe how to prepare this dish...',
                            ),
                            minLines: 3,
                            maxLines: 5,
                            validator: (v) => v!.trim().isEmpty
                                ? 'Instructions are required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _visibility,
                            decoration: const InputDecoration(
                              labelText: 'Visibility',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.visibility),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'public', child: Text('Public')),
                              DropdownMenuItem(
                                  value: 'friends',
                                  child: Text('Friends Only')),
                              DropdownMenuItem(
                                  value: 'private', child: Text('Private')),
                            ],
                            onChanged: (v) => setState(() => _visibility = v!),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPhotoPicker(
      {required String title,
      File? file,
      String? existingUrl,
      required bool isItem}) {
    return InkWell(
      onTap: () => _pickImage(isItem),
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          image: file != null
              ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
              : existingUrl != null
                  ? DecorationImage(
                      image: NetworkImage(ApiService.getImageUrl(existingUrl)),
                      fit: BoxFit.cover)
                  : null,
        ),
        child: file == null && existingUrl == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(title, style: TextStyle(color: Colors.grey.shade600)),
                ],
              )
            : null,
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard Changes?'),
            content:
                const Text('Are you sure you want to discard your changes?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard',
                      style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
  }
}
