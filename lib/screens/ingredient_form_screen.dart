import 'package:flutter/material.dart';
import '../api_service.dart';
import '../models/ingredient.dart';

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
  late TextEditingController _unitController;
  late TextEditingController _caloriesController;
  
  String _selectedCategory = 'Dry Goods';
  
  final List<String> _categories = [
    'Dry Goods', 'Dairy', 'Produce', 'Meat', 'Seafood', 'Frozen', 'Canned',
    'Beverages', 'Cleaning', 'In-House'
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.ingredient?.name ?? '');
    _brandController = TextEditingController(text: widget.ingredient?.brand ?? '');
    _priceController = TextEditingController(text: widget.ingredient?.price?.toString() ?? '');
    _unitController = TextEditingController(text: widget.ingredient?.unit ?? '');
    _caloriesController = TextEditingController(text: widget.ingredient?.calories?.toString() ?? '');
    
    if (widget.ingredient != null) {
      if (_categories.contains(widget.ingredient!.category)) {
        _selectedCategory = widget.ingredient!.category;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _unitController.dispose();
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
      'unit': _unitController.text,
      'calories': _caloriesController.text,
    };

    String? error;
    if (widget.ingredient == null) {
       error = await _apiService.createIngredient(data);
    } else {
       error = await _apiService.updateIngredient(widget.ingredient!.id, data);
    }

    setState(() => _isLoading = false);

    if (error == null) {
      if (mounted) Navigator.of(context).pop(true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.ingredient != null;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Ingredient' : 'New Ingredient', 
          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1B4D3E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderTitle(isEdit ? 'Refine Your Item' : 'Add to Pantry'),
              const SizedBox(height: 24),
              _buildModernField(
                controller: _nameController,
                label: 'Ingredient Name',
                hint: 'e.g. Organic Flour',
                icon: Icons.restaurant_rounded,
                validator: (val) => val == null || val.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 20),
              _buildCategoryDropdown(),
              const SizedBox(height: 20),
              _buildModernField(
                controller: _brandController,
                label: 'Brand / Producer',
                hint: 'Optional',
                icon: Icons.store_rounded,
              ),
              const SizedBox(height: 24),
              const Text('Calculations Details', 
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1B4D3E))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildModernField(
                      controller: _priceController,
                      label: 'Price',
                      hint: '0.00',
                      icon: Icons.payments_rounded,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModernField(
                      controller: _unitController,
                      label: 'Unit',
                      hint: 'kg / L',
                      icon: Icons.scale_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildModernField(
                controller: _caloriesController,
                label: 'Calories (kcal)',
                hint: 'per unit',
                icon: Icons.local_fire_department_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 48),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF2D3436), letterSpacing: -1)),
        const SizedBox(height: 4),
        Container(width: 60, height: 4, decoration: BoxDecoration(color: const Color(0xFFE1B12C), borderRadius: BorderRadius.circular(2))),
      ],
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF636E72))),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2D3436)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.brown.shade100),
            prefixIcon: Icon(icon, color: const Color(0xFFE1B12C), size: 22),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Color(0xFFE1B12C), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF636E72))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
          onChanged: (val) => setState(() => _selectedCategory = val!),
          icon: const Icon(Icons.expand_more_rounded, color: Color(0xFFE1B12C)),
          dropdownColor: Colors.white,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.category_rounded, color: Color(0xFFE1B12C), size: 22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1B4D3E),
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 4,
          shadowColor: const Color(0xFF1B4D3E).withOpacity(0.4),
        ),
        child: _isLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : Text(widget.ingredient == null ? 'Create Ingredient' : 'Update Pantry', 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
      ),
    );
  }
}
