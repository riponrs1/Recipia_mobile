import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../utils/unit_converter.dart';
import 'dart:convert';

class RecipeAnalysisScreen extends StatefulWidget {
  final Recipe recipe;
  final double batchMultiplier;

  const RecipeAnalysisScreen({
    super.key,
    required this.recipe,
    required this.batchMultiplier,
  });

  @override
  State<RecipeAnalysisScreen> createState() => _RecipeAnalysisScreenState();
}

class _RecipeAnalysisScreenState extends State<RecipeAnalysisScreen> {
  List<Map<String, dynamic>> _analysisItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _prepareData();
  }

  void _prepareData() {
    try {
      final List<dynamic> raw = jsonDecode(widget.recipe.ingredients);
      _analysisItems = raw.map((item) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(item);
        // Add override fields if not present
        map['override_price'] = null;
        map['override_calories'] = null;
        return map;
      }).toList();
    } catch (e) {
      _analysisItems = [];
    }
    setState(() => _isLoading = false);
  }

  double _calculateItemCost(Map<String, dynamic> item) {
    try {
      double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
      String unit = item['unit']?.toString() ?? '';
      double price = item['override_price'] ?? (item['price'] ?? 0.0).toDouble();

      if (price <= 0) return 0.0;
      
      double grams = UnitConverter.toGrams(qty, unit);
      double total;
      if (grams > 0) {
        total = (grams / 1000) * price;
      } else {
        total = qty * price;
      }
      return total * widget.batchMultiplier;
    } catch (e) {
      return 0.0;
    }
  }

  double _calculateItemCalories(Map<String, dynamic> item) {
    try {
      double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
      String unit = item['unit']?.toString() ?? '';
      double cals = item['override_calories'] ?? (item['calories'] ?? 0.0).toDouble();

      if (cals <= 0) return 0.0;
      
      double grams = UnitConverter.toGrams(qty, unit);
      double total;
      if (grams > 0) {
        total = (grams / 1000) * cals;
      } else {
        total = qty * cals;
      }
      return total * widget.batchMultiplier;
    } catch (e) {
      return 0.0;
    }
  }

  double get _totalCost {
    return _analysisItems.fold(0.0, (sum, item) => sum + _calculateItemCost(item));
  }

  double get _totalCalories {
    return _analysisItems.fold(0.0, (sum, item) => sum + _calculateItemCalories(item));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        title: const Text('CULINARY ANALYSIS', 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2, color: Color(0xFF1B4D3E))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1B4D3E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildIngredientsList()),
                _buildBottomSummary(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.recipe.name.toUpperCase(), 
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF2D3436), letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text('SESSION BREAKDOWN • ${widget.batchMultiplier}X BATCH', 
            style: const TextStyle(color: Color(0xFFE1B12C), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 16),
          _buildInfoBanner(),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE1B12C).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1B12C).withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFD63031), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Overrides are temporary. They will recalculate totals for this session only.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD63031)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _analysisItems.length,
      itemBuilder: (context, index) {
        final item = _analysisItems[index];
        return _buildIngredientAnalysisCard(item, index);
      },
    );
  }

  Widget _buildIngredientAnalysisCard(Map<String, dynamic> item, int index) {
    final cost = _calculateItemCost(item);
    final cals = _calculateItemCalories(item);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B4D3E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.restaurant_rounded, color: Color(0xFF1B4D3E), size: 20),
        ),
        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2D3436))),
        subtitle: Text('${item['qty']} ${item['unit']}', style: TextStyle(color: Colors.brown.shade200, fontSize: 12, fontWeight: FontWeight.w600)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('\$${cost.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2D3436))),
            Text('${cals.toInt()} kcal', style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text('MANUAL OVERRIDES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildOverrideField(
                  label: 'Price per ${item['unit'] ?? 'unit'}',
                  currentValue: item['override_price']?.toString() ?? item['price']?.toString() ?? '0.00',
                  onChanged: (val) {
                    setState(() {
                      _analysisItems[index]['override_price'] = double.tryParse(val);
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOverrideField(
                  label: 'Calories (kcal)',
                  currentValue: item['override_calories']?.toString() ?? item['calories']?.toString() ?? '0',
                  onChanged: (val) {
                    setState(() {
                      _analysisItems[index]['override_calories'] = double.tryParse(val);
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverrideField({required String label, required String currentValue, required Function(String) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF636E72))),
        const SizedBox(height: 6),
        TextField(
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2D3436)),
          decoration: InputDecoration(
            hintText: currentValue,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: const Color(0xFFFDFBF7),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withOpacity(0.05))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withOpacity(0.05))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE1B12C))),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSummary() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B4D3E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B4D3E).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryCol('ADJUSTED COST', '\$${_totalCost.toStringAsFixed(2)}'),
          _buildSummaryCol('ADJUSTED KCAL', '${_totalCalories.toInt()} kcal'),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE1B12C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCol(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w800)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
