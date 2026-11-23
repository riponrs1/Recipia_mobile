import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../perf.dart';
import '../services/price_book.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

/// Names used in recipes that are not in Ingredients yet. Similar spellings
/// are one row; the cook ticks what to add and taps one button.
class MissingNamesScreen extends StatefulWidget {
  const MissingNamesScreen({super.key});

  @override
  State<MissingNamesScreen> createState() => _MissingNamesScreenState();
}

class _MissingNamesScreenState extends State<MissingNamesScreen> {
  final _book = PriceBook.instance;
  late final List<MissingName> _groups = _book.missingFromList();
  // nothing ticked to start: the cook chooses what to add
  final Set<MissingName> _picked = {};
  bool _busy = false;

  Future<void> _rename(MissingName g) async {
    final c = TextEditingController(text: g.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Name in Ingredients'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) setState(() => g.name = v);
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    final n = await perfAsync('add names', () => _book.addMissing(_picked.toList()));
    if (!mounted) return;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final n = _picked.length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: _fg,
        elevation: 0,
        title: const Text('Names in your recipes',
            style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _picked.length == _groups.length
                    ? _picked.clear()
                    : _picked.addAll(_groups)),
            child: Text(_picked.length == _groups.length ? 'Untick all' : 'Tick all',
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _groups.isEmpty
          ? const Center(
              child: Text('Every name in your recipes is in Ingredients.',
                  style: TextStyle(color: _muted)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              itemCount: _groups.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 14 : 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return const Text(
                      'These are used in recipes but aren’t in your Ingredients list, so they have no price. '
                      'Similar spellings are shown together and become one ingredient.',
                      style: TextStyle(fontSize: 14, height: 1.45, color: _muted));
                }
                return _row(_groups[i - 1]);
              },
            ),
      bottomNavigationBar: _groups.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _busy || n == 0 ? null : _add,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  child: Text(_busy
                      ? 'Adding…'
                      : n == 0
                          ? 'Tick names to add'
                          : 'Add $n to Ingredients'),
                ),
              ),
            ),
    );
  }

  Widget _row(MissingName g) {
    final on = _picked.contains(g);
    final others = g.spellings.where((x) => PriceBook.key(x) != PriceBook.key(g.name)).toSet();
    final m = g.matches;
    return Container(
      decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : () => setState(() => on ? _picked.remove(g) : _picked.add(g)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
            child: Row(children: [
              Checkbox(
                  value: on,
                  activeColor: _accent,
                  onChanged: _busy ? null : (_) => setState(() => on ? _picked.remove(g) : _picked.add(g))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(g.name,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _fg)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 17, color: _muted),
                      tooltip: 'Change name',
                      onPressed: _busy ? null : () => _rename(g),
                    ),
                  ]),
                  Text(
                      'in ${g.recipeCount} recipe${g.recipeCount == 1 ? '' : 's'}'
                      '${g.price != null ? ' · ${AppSettings.currency}${g.price!.round()}/${g.unit}' : ' · no price yet'}',
                      style: const TextStyle(fontSize: 13, color: _muted)),
                  if (others.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('Also written as: ${others.take(4).join(', ')}${others.length > 4 ? '…' : ''}',
                          style: const TextStyle(fontSize: 12.5, color: _muted, fontStyle: FontStyle.italic)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        if (m != null && on)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              _choice('Use “${m['name']}”', g.useExisting, () => setState(() => g.useExisting = true)),
              _choice('Add as new', !g.useExisting, () => setState(() => g.useExisting = false)),
            ]),
          ),
      ]),
    );
  }

  Widget _choice(String label, bool on, VoidCallback tap) => Expanded(
        child: GestureDetector(
          onTap: _busy ? null : tap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
                color: on ? _surface : Colors.transparent, borderRadius: BorderRadius.circular(9)),
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: on ? _accent : _muted)),
          ),
        ),
      );
}

/// Ingredients that look like the same thing ("Mayo" / "Mayonnaise").
/// Tick the pairs to merge and tap one button.
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  final _book = PriceBook.instance;
  // each pair: [from, into]; the longer name with a price is kept by default
  // [from, into]: keep the name used in more recipes, then the one with a
  // price, then the longer one ("mayo" goes into "Mayonnaise")
  late final List<List<Map<String, dynamic>>> _pairs = _book.duplicatePairs().map((p) {
    final a = p[0], b = p[1];
    int score(Map<String, dynamic> x) => _book.usedIn(x['name'].toString()).length;
    final sa = score(a), sb = score(b);
    if (sa != sb) return sa > sb ? [b, a] : [a, b];
    final pa = a['price'] != null, pb = b['price'] != null;
    if (pa != pb) return pa ? [b, a] : [a, b];
    return a['name'].toString().length > b['name'].toString().length ? [b, a] : [a, b];
  }).toList();
  // nothing ticked to start: some look-alikes are different things ("batter" / "butter")
  final Set<int> _picked = {};
  bool _busy = false;

  Future<void> _merge() async {
    setState(() => _busy = true);
    final picks = [for (final i in _picked) (_pairs[i][0], _pairs[i][1])];
    await perfAsync('merge', () => _book.mergeMany(picks));
    if (!mounted) return;
    Navigator.pop(context, picks.length);
  }

  @override
  Widget build(BuildContext context) {
    final n = _picked.length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: _fg,
        elevation: 0,
        title: const Text('Look-alike ingredients',
            style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _picked.length == _pairs.length
                    ? _picked.clear()
                    : _picked.addAll([for (var i = 0; i < _pairs.length; i++) i])),
            child: Text(_picked.length == _pairs.length ? 'Untick all' : 'Tick all',
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        itemCount: _pairs.length + 1,
        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 14 : 8),
        itemBuilder: (_, i) {
          if (i == 0) {
            return const Text(
                'These pairs might be the same ingredient. Tick the ones that are, then merge: recipes move over and one price is kept. '
                'Tap ⇄ to keep the other name.',
                style: TextStyle(fontSize: 14, height: 1.45, color: _muted));
          }
          final k = i - 1, p = _pairs[k], on = _picked.contains(k);
          final used = _book.usedIn(p[0]['name'].toString()).length;
          return Container(
            decoration: BoxDecoration(
                color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(children: [
              Checkbox(
                  value: on,
                  activeColor: _accent,
                  onChanged: _busy ? null : (_) => setState(() => on ? _picked.remove(k) : _picked.add(k))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${p[0]['name']}', style: const TextStyle(color: _muted, decoration: TextDecoration.lineThrough)),
                    const TextSpan(text: '  →  ', style: TextStyle(color: _muted)),
                    TextSpan(text: '${p[1]['name']}', style: const TextStyle(fontWeight: FontWeight.w700, color: _fg)),
                  ]), style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('$used recipe${used == 1 ? '' : 's'} move over',
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ]),
              ),
              IconButton(
                tooltip: 'Keep the other name',
                icon: const Icon(Icons.swap_horiz_rounded, color: _accent),
                onPressed: _busy ? null : () => setState(() => _pairs[k] = [p[1], p[0]]),
              ),
            ]),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy || n == 0 ? null : _merge,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            child: Text(_busy ? 'Merging…' : n == 0 ? 'Tick pairs to merge' : 'Merge $n pair${n == 1 ? '' : 's'}'),
          ),
        ),
      ),
    );
  }
}
