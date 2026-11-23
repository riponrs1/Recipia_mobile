import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: deprecated_member_use
import 'package:share_plus/share_plus.dart';
import '../api_service.dart';
import '../app_settings.dart';
import '../models/recipe.dart';
import '../services/price_book.dart';
import '../utils/unit_converter.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

class RecipeShareScreen extends StatefulWidget {
  final Recipe recipe;
  final double batchMultiplier;
  const RecipeShareScreen(
      {super.key, required this.recipe, this.batchMultiplier = 1.0});

  @override
  State<RecipeShareScreen> createState() => _RecipeShareScreenState();
}

class _RecipeShareScreenState extends State<RecipeShareScreen> {
  final _api = ApiService();
  final _userCtrl = TextEditingController();
  late Recipe _recipe;
  String _visibility = 'private';
  bool _busy = false;
  bool _optMethod = true;
  bool _optWeight = true;
  bool _optBold = true;
  bool _optCost = false;

  @override
  void initState() {
    super.initState();
    _recipe = widget.recipe;
    _visibility = _recipe.visibility ?? 'private';
    _refresh();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final data = await _api.getRecipe(_recipe.id);
      if (mounted) {
        setState(() {
          _recipe = Recipe.fromJson(data);
          _visibility = _recipe.visibility ?? 'private';
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic> _recipeData(String visibility) => {
        'name': _recipe.name,
        'brand_name': _recipe.brandName ?? '',
        'section_name': _recipe.sectionName,
        'ingredients': _recipe.ingredients,
        'process': _recipe.process,
        'servings': _recipe.servings,
        'visibility': visibility,
      };

  Future<void> _setVisibility(String v) async {
    final prev = _visibility;
    setState(() => _visibility = v);
    final err = await _api.updateRecipe(_recipe.id, _recipeData(v));
    if (err != null && mounted) {
      setState(() => _visibility = prev);
      _toast(err);
    }
  }

  Future<void> _addShare() async {
    final names = _userCtrl.text.trim();
    if (names.isEmpty) return;
    setState(() => _busy = true);
    final msg = await _api.shareRecipeAccess(_recipe.id, names);
    _userCtrl.clear();
    await _refresh();
    if (mounted) {
      setState(() => _busy = false);
      _toast(msg ?? 'Shared');
    }
  }

  Future<void> _removeShare(int userId) async {
    setState(() => _busy = true);
    await _api.removeRecipeAccess(_recipe.id, userId);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating));
  }

  String _fmtNum(double v) => v % 1 == 0
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

  String _fmtGrams(double g) =>
      g >= 1000 ? '${_fmtNum(g / 1000)} kg' : '${_fmtNum(g)} g';

  String _buildShareText() {
    String b(String t) => _optBold ? '*$t*' : t;
    final f = widget.batchMultiplier > 0 ? widget.batchMultiplier : 1.0;
    final rawLines = PriceBook.parseLines(_recipe.ingredients);
    final book = PriceBook.instance;
    final ov = book.overrides[_recipe.id];

    double totG = 0;
    for (final l in rawLines) {
      totG += UnitConverter.toGrams(l.qty * f, l.unit);
    }

    final meta = <String>[];
    if (_recipe.sectionName.trim().isNotEmpty) meta.add(_recipe.sectionName.trim());
    if ((f - 1.0).abs() > 1e-6) meta.add('${_fmtNum(f)}× batch');
    if (_optWeight && totG > 0) meta.add('Total: ${_fmtGrams(totG)}');
    if (_optCost) {
      final sum = book.summarize(_recipe.id, rawLines, factor: f);
      if (sum.total > 0) {
        meta.add('Est. cost: ${AppSettings.currency}${sum.total.round()}');
      }
    }

    final out = <String>[b(_recipe.name)];
    if (meta.isNotEmpty) out.add(meta.join(' · '));
    out.add('');
    out.add(b('Ingredients'));

    for (final l in rawLines) {
      final q = l.qty * f;
      final qs = PriceBook.isCount(l.unit)
          ? _fmtNum((q * 2).round() / 2)
          : _fmtNum(q >= 100
              ? q.roundToDouble()
              : q >= 10
                  ? (q * 10).round() / 10
                  : (q * 100).round() / 100);
      var row = '• ${l.name} — $qs ${l.unit}';
      if (_optCost) {
        final lc = book.lineCost(l.name, q, l.unit, recipeOverrides: ov);
        if (lc != null) row += ' (${AppSettings.currency}${lc.round()})';
      }
      out.add(row);
    }

    if (_optMethod && _recipe.process.trim().isNotEmpty) {
      out.add('');
      out.add(b('Method'));
      final rows = _recipe.process
          .split('\n')
          .map((s) => s.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
          .where((s) => s.isNotEmpty)
          .toList();
      final steps = rows.length > 1
          ? rows
          : _recipe.process
              .split(RegExp(r'(?<=[.;])\s+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
      for (var i = 0; i < steps.length; i++) {
        out.add('${i + 1}. ${steps[i]}');
      }
    }

    out.add('');
    out.add('— Shared from Recipia');
    return out.join('\n');
  }

  void _copyAsText() {
    Clipboard.setData(ClipboardData(text: _buildShareText()));
    _toast('Recipe text copied');
  }

  void _shareAsText() {
    Share.share(_buildShareText(), subject: _recipe.name);
  }

  @override
  Widget build(BuildContext context) {
    final shared = _recipe.sharedWith ?? [];
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Share recipe',
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                children: [
                  Text(_recipe.name,
                      style: const TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                  const SizedBox(height: 18),
                  _blockLabel('Who can see it'),
                  const SizedBox(height: 8),
                  _visibilitySeg(),
                  const SizedBox(height: 22),
                  _blockLabel('Share with people'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _userCtrl,
                          style: const TextStyle(fontSize: 15, color: _fg),
                          decoration: InputDecoration(
                            hintText: 'username or email',
                            hintStyle:
                                const TextStyle(color: _muted, fontSize: 15),
                            filled: true,
                            fillColor: _surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: _line)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: _line)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: _accent, width: 1.5)),
                          ),
                          onSubmitted: (_) => _addShare(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _busy ? null : _addShare,
                        child: Container(
                          height: 50,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(14)),
                          child: const Text('Add',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _blockLabel('Shared with (${shared.length})'),
                  const SizedBox(height: 8),
                  if (shared.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _line)),
                      child: const Text('Not shared with anyone yet.',
                          style: TextStyle(color: _muted, fontSize: 14)),
                    )
                  else
                    ...shared.map((u) => _friendTile(u)),
                  const SizedBox(height: 22),
                  _blockLabel('Share as text'),
                  const SizedBox(height: 8),
                  _shareTextCard(),
                  const SizedBox(height: 22),
                  _blockLabel('Share link'),
                  const SizedBox(height: 8),
                  _copyLink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareTextCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _optChip('Method', _optMethod, () => setState(() => _optMethod = !_optMethod)),
              _optChip('Total weight', _optWeight, () => setState(() => _optWeight = !_optWeight)),
              _optChip('WhatsApp *bold*', _optBold, () => setState(() => _optBold = !_optBold)),
              _optChip('Include cost', _optCost, () => setState(() => _optCost = !_optCost)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: SingleChildScrollView(
              child: Text(
                _buildShareText(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                  color: _fg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _copyAsText,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _line),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy_rounded, size: 16, color: _fg),
                        SizedBox(width: 6),
                        Text('Copy text',
                            style: TextStyle(
                                color: _fg,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _shareAsText,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.share_outlined, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Share text',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optChip(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: on ? _accentSoft : _surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? _accent : _line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? _accent : _muted)),
      ),
    );
  }

  Widget _blockLabel(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: _muted));

  Widget _visibilitySeg() {
    final opts = {
      'private': 'Private',
      'friends': 'Friends',
      'public': 'Public'
    };
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
              onTap: () => _setVisibility(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
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

  Widget _friendTile(dynamic u) {
    final name = (u is Map ? (u['name'] ?? u['username'] ?? 'User') : 'User')
        .toString();
    final email = (u is Map ? (u['email'] ?? '') : '').toString();
    final id = (u is Map ? u['id'] : null);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
                color: _accentSoft, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: _accent, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _fg)),
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          if (id != null)
            GestureDetector(
              onTap: () => _removeShare(id as int),
              child: const Icon(Icons.close_rounded, color: _muted, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _copyLink() {
    final link = 'recipia.bicitra.com/recipe/${_recipe.id}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line, style: BorderStyle.solid)),
      child: Row(
        children: [
          Expanded(
            child: Text(link,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _muted)),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: 'https://$link'));
              _toast('Link copied');
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: _accent, borderRadius: BorderRadius.circular(10)),
              child: const Text('Copy',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
