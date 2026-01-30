import 'package:flutter/material.dart';
import '../api_service.dart';
import 'ingredients_screen.dart'; // For Ingredient class

class IngredientFormScreen extends StatefulWidget {
  final Ingredient? ingredient; // If null, creating new

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
  
  String _selectedCategory = 'Dry Goods'; // Default
  
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
      } else {
        // Handle case where category might not match exactly or is new
        _selectedCategory = _categories.first; 
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
       // Create
       // We need an API method for createIngredient
       error = await _apiService.createIngredient(data);
    } else {
       // Update
       error = await _apiService.updateIngredient(widget.ingredient!.id, data);
    }

    setState(() => _isLoading = false);

    if (error == null) {
      if (mounted) {
         Navigator.of(context).pop(true); // Return true to indicate refresh needed
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ingredient == null ? 'Add Ingredient' : 'Edit Ingredient'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Name',
                  icon: Icons.label,
                  validator: (val) => val == null || val.isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    prefixIcon: const Icon(Icons.category, color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: _categories.map((cat) => DropdownMenuItem(
                    value: cat,
                    child: Text(cat),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _brandController,
                  label: 'Brand (Optional)',
                  icon: Icons.branding_watermark,
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _priceController,
                        label: 'Price',
                        icon: Icons.attach_money,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _unitController,
                        label: 'Unit (kg, L)',
                        icon: Icons.scale,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _caloriesController,
                  label: 'Calories (kcal)',
                  icon: Icons.local_fire_department,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 32),
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFE74C3C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.ingredient == null ? 'Add Ingredient' : 'Update Ingredient', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      keyboardType: keyboardType,
      validator: validator,
    );
  }
}
