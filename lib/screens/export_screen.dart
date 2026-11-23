import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
// ignore: deprecated_member_use
import 'package:share_plus/share_plus.dart';

import '../models/recipe.dart';
import '../services/recipe_export.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

/// Export one recipe as a PDF or an Excel file. The cook picks what goes in
/// (prices are off every time), sees a preview, then saves or shares it.
class ExportScreen extends StatefulWidget {
  final Recipe recipe;
  final double factor;
  final bool excel;
  const ExportScreen({super.key, required this.recipe, required this.factor, this.excel = false});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _opt = ExportOptions();
  late bool _excel = widget.excel;
  bool _busy = false;
  int _version = 0; // forces the PDF preview to rebuild

  RecipeExport get _ex => RecipeExport(widget.recipe, widget.factor, _opt);
  String get _fileName => '${_ex.fileBase}.${_excel ? 'xlsx' : 'pdf'}';

  Future<Uint8List> _bytes() async =>
      _excel ? Uint8List.fromList(_ex.xlsx()) : await _ex.pdf();

  void _toggle(void Function() f) => setState(() {
        f();
        _version++;
      });

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final b = await _bytes();
      final path = await FilePicker.saveFile(
          dialogTitle: 'Save ${_excel ? 'Excel file' : 'PDF'}',
          fileName: _fileName,
          mimeType: _excel
              ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
              : 'application/pdf',
          bytes: b);
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating, content: Text('Saved $_fileName')));
      }
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$_fileName');
      await f.writeAsBytes(await _bytes());
      await Share.shareXFiles([XFile(f.path)], text: widget.recipe.name);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFC0392B),
        content: Text('Couldn’t make the file: $e')));
  }

  Widget _chip(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _accent : _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? _accent : _line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.check_rounded : Icons.add_rounded,
                size: 15, color: on ? Colors.white : _muted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : _fg)),
          ]),
        ),
      );

  Widget _formatTab(String label, IconData icon, bool excel) {
    final on = _excel == excel;
    return Expanded(
      child: GestureDetector(
        onTap: () => _toggle(() => _excel = excel),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? _surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: on
                ? [BoxShadow(color: const Color(0x0F000000), blurRadius: 6)]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: on ? _accent : _muted),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: on ? _accent : _muted)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        foregroundColor: _fg,
        title: const Text('Export recipe',
            style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: const Color(0xFFF3EDDF), borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                _formatTab('PDF', Icons.picture_as_pdf_outlined, false),
                _formatTab('Excel', Icons.table_view_outlined, true),
              ]),
            ),
            const SizedBox(height: 14),
            const Text('INCLUDE',
                style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                    color: _muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Prices & cost', _opt.cost, () => _toggle(() => _opt.cost = !_opt.cost)),
              _chip('Calories', _opt.calories,
                  () => _toggle(() => _opt.calories = !_opt.calories)),
              if (!_excel) ...[
                _chip('Photo', _opt.photo, () => _toggle(() => _opt.photo = !_opt.photo)),
                _chip('Tick boxes', _opt.ticks, () => _toggle(() => _opt.ticks = !_opt.ticks)),
              ],
            ]),
            if (!_opt.cost)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Prices stay private unless you turn them on.',
                    style: TextStyle(fontSize: 12.5, color: _muted)),
              ),
            const SizedBox(height: 12),
          ]),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EAE3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            clipBehavior: Clip.antiAlias,
            child: _excel
                ? _excelPreview()
                : PdfPreview(
                    key: ValueKey(_version),
                    build: (_) => _ex.pdf(),
                    useActions: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    pdfFileName: _fileName,
                    scrollViewDecoration: const BoxDecoration(color: Color(0xFFF1EAE3)),
                    loadingWidget: const CircularProgressIndicator(color: _accent),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Save to phone'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// A spreadsheet-looking preview of the Ingredients sheet.
  Widget _excelPreview() {
    final ex = _ex;
    final head = ex.xlsHeader;
    final ls = ex.lines, sum = ex.summary;
    final showK = _opt.calories && sum.calories > 0;
    String n(double? v, [int d = 0]) => v == null ? '' : v.toStringAsFixed(d);
    List<String> row(ExportLine l) => [
          l.name,
          RecipeExport.qty(l.qty, l.unit),
          l.unit,
          if (_opt.cost) ...[n(l.price, 2), l.priceUnit ?? '', n(l.cost, 2)],
          if (showK) n(l.kcal),
        ];
    final total = [
      'Total',
      RecipeExport.group(sum.grams),
      'g',
      if (_opt.cost) ...['', '', sum.total.toStringAsFixed(2)],
      if (showK) RecipeExport.group(sum.calories),
    ];
    Widget cell(String s, int c, {bool bold = false, Color? color, Color? bg}) => Container(
          width: c == 0 ? 150 : 72,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
              color: bg,
              border: const Border(
                  right: BorderSide(color: Color(0xFFEFE4DD)),
                  bottom: BorderSide(color: Color(0xFFEFE4DD)))),
          child: Text(s,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: c == 0 || c == 2 ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  color: color ?? _fg)),
        );
    return Container(
      color: _surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.recipe.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _fg)),
                const SizedBox(height: 2),
                Text('${widget.recipe.sectionName} · batch ${ex.batchText.isEmpty ? '1×' : ex.batchText.trim().replaceAll(RegExp(r'[()]'), '')}',
                    style: const TextStyle(fontSize: 12, color: _muted)),
                const SizedBox(height: 10),
                Row(children: [
                  for (var c = 0; c < head.length; c++)
                    cell(head[c], c, bold: true, color: Colors.white, bg: const Color(0xFF1F7A45)),
                ]),
                for (final l in ls)
                  Row(children: [
                    for (final (c, s) in row(l).indexed) cell(s, c),
                  ]),
                Row(children: [
                  for (final (c, s) in total.indexed)
                    cell(s, c, bold: true, bg: const Color(0xFFE3F2E7)),
                ]),
              ]),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _accentSoft,
          child: const Text(
              'Two sheets: Ingredients and Method. Totals are formulas, so they update if you change an amount.',
              style: TextStyle(fontSize: 12, color: _accent)),
        ),
      ]),
    );
  }
}
