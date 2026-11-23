import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/recipe.dart';
import '../utils/unit_converter.dart';
import '../app_settings.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

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
      double price =
          item['override_price'] ?? (item['price'] ?? 0.0).toDouble();
      if (price <= 0) return 0.0;
      double grams = UnitConverter.toGrams(qty, unit);
      double total = grams > 0 ? (grams / 1000) * price : qty * price;
      return total * widget.batchMultiplier;
    } catch (e) {
      return 0.0;
    }
  }

  double _calculateItemCalories(Map<String, dynamic> item) {
    try {
      double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
      String unit = item['unit']?.toString() ?? '';
      double cals =
          item['override_calories'] ?? (item['calories'] ?? 0.0).toDouble();
      if (cals <= 0) return 0.0;
      double grams = UnitConverter.toGrams(qty, unit);
      double total = grams > 0 ? (grams / 1000) * cals : qty * cals;
      return total * widget.batchMultiplier;
    } catch (e) {
      return 0.0;
    }
  }

  double get _totalCost =>
      _analysisItems.fold(0.0, (sum, item) => sum + _calculateItemCost(item));

  double get _totalCalories => _analysisItems.fold(
      0.0, (sum, item) => sum + _calculateItemCalories(item));

  String get _cur => AppSettings.currency;

  @override
  Widget build(BuildContext context) {
    final batch = widget.batchMultiplier;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                    child: Row(
                      children: [
                        IconButton(
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: _fg),
                            onPressed: () => Navigator.pop(context)),
                        const Expanded(
                          child: Text('Cost & calories',
                              style: TextStyle(fontFamily: 'SpaceGrotesk',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: _fg)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.recipe.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _fg)),
                        const SizedBox(height: 3),
                        Text(
                            batch == 1
                                ? 'Per-ingredient breakdown'
                                : 'Breakdown · ${_fmt(batch)}× batch',
                            style:
                                const TextStyle(fontSize: 13, color: _muted)),
                        const SizedBox(height: 12),
                        _infoBanner(),
                      ],
                    ),
                  ),
                  Expanded(child: _buildIngredientsList()),
                  _buildBottomSummary(),
                ],
              ),
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9A6B00), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edits here are temporary — they recalculate totals for this view only.',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF9A6B00), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsList() {
    if (_analysisItems.isEmpty) {
      return const Center(
        child: Text('No ingredients to analyse',
            style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      itemCount: _analysisItems.length,
      itemBuilder: (context, index) =>
          _buildIngredientAnalysisCard(_analysisItems[index], index),
    );
  }

  Widget _buildIngredientAnalysisCard(Map<String, dynamic> item, int index) {
    final cost = _calculateItemCost(item);
    final cals = _calculateItemCalories(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          iconColor: _muted,
          collapsedIconColor: _muted,
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: _accentSoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.restaurant_rounded,
                color: _accent, size: 20),
          ),
          title: Text(item['name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: _fg, fontSize: 14)),
          subtitle: Text('${item['qty']} ${item['unit']}',
              style: const TextStyle(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w500)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$_cur${cost.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _accent)),
              Text('${cals.toInt()} kcal',
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
          children: [
            const Divider(height: 1, color: _line),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Adjust for this view',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 0.3)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildOverrideField(
                    label: 'Price per ${item['unit'] ?? 'unit'}',
                    currentValue: item['override_price']?.toString() ??
                        item['price']?.toString() ??
                        '0.00',
                    onChanged: (val) => setState(() => _analysisItems[index]
                        ['override_price'] = double.tryParse(val)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOverrideField(
                    label: 'Calories (kcal)',
                    currentValue: item['override_calories']?.toString() ??
                        item['calories']?.toString() ??
                        '0',
                    onChanged: (val) => setState(() => _analysisItems[index]
                        ['override_calories'] = double.tryParse(val)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverrideField(
      {required String label,
      required String currentValue,
      required Function(String) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
        const SizedBox(height: 6),
        TextField(
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _fg),
          decoration: InputDecoration(
            hintText: currentValue,
            hintStyle: const TextStyle(color: _muted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            filled: true,
            fillColor: _surface2,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accent, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSummary() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).padding.bottom + 18),
      decoration: const BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryCol('Total cost', '$_cur${_totalCost.toStringAsFixed(2)}'),
          _buildSummaryCol('Total kcal', '${_totalCalories.toInt()}'),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            child: const Text('Done',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: _accent)),
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
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontFamily: 'SpaceGrotesk',
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
