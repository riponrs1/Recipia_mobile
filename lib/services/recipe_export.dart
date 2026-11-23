import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api_service.dart';
import '../app_settings.dart';
import '../models/recipe.dart';
import '../utils/unit_converter.dart';
import 'price_book.dart';

/// What goes into an exported recipe. Prices are private, so they are off
/// unless the cook turns them on for this export.
class ExportOptions {
  bool cost = false;
  bool calories = true;
  bool photo = true;
  bool ticks = true;
}

/// One ingredient line after the batch size is applied.
class ExportLine {
  final String name;
  final double qty;
  final String unit;
  final double? cost;
  final double? kcal;
  final double? price; // in the ingredient's own unit
  final String? priceUnit;
  ExportLine(this.name, this.qty, this.unit, this.cost, this.kcal, this.price, this.priceUnit);
}

class RecipeExport {
  final Recipe recipe;
  final double factor;
  final ExportOptions opt;
  RecipeExport(this.recipe, this.factor, this.opt);

  PriceBook get _book => PriceBook.instance;

  List<ExportLine> get lines {
    final ov = _book.overrides[recipe.id];
    return PriceBook.parseLines(recipe.ingredients).map((l) {
      final q = l.qty * factor;
      final it = _book.find(l.name);
      final custom = ov?[PriceBook.key(l.name)];
      final price = custom ?? (it?['price'] as num?)?.toDouble();
      return ExportLine(l.name, q, l.unit, _book.lineCost(l.name, q, l.unit, recipeOverrides: ov),
          _book.lineCalories(l.name, q, l.unit), price, it?['unit']?.toString());
    }).toList();
  }

  CostSummary get summary =>
      _book.summarize(recipe.id, PriceBook.parseLines(recipe.ingredients), factor: factor);

  List<String> get steps {
    final rows = recipe.process
        .split('\n')
        .map((s) => s.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
    if (rows.length > 1) return rows;
    return recipe.process
        .split(RegExp(r'(?<=[.;])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String get fileBase {
    final s = recipe.name.trim().replaceAll(RegExp(r'[^\w]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return s.isEmpty ? 'recipe' : s;
  }

  // ------------------------------------------------------------------ text
  /// PDF fonts have no ৳ or Arabic currency signs, so those print as codes.
  static String get pdfCurrency {
    const codes = {'৳': 'Tk ', 'د.إ': 'AED ', '﷼': 'SAR ', '₨': 'Rs '};
    return codes[AppSettings.currency] ?? AppSettings.currency;
  }

  static String group(num n) =>
      n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  static String money(double v) => '$pdfCurrency${group(v)}';
  static String qty(double q, String u) {
    if (PriceBook.isCount(u)) {
      final v = (q * 2).round() / 2;
      return v % 1 == 0 ? v.toInt().toString() : v.toString();
    }
    final v = q >= 100 ? q.roundToDouble() : q >= 10 ? (q * 10).round() / 10 : (q * 100).round() / 100;
    return v % 1 == 0 ? group(v) : v.toString();
  }

  static String grams(double g) {
    final v = (g * 10).round() / 10;
    return '${v % 1 == 0 ? group(v) : v.toString()} g';
  }

  String get batchText => factor == 1 ? '' : ' (${factor % 1 == 0 ? factor.toInt() : factor}×)';

  static String today() {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.now();
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ------------------------------------------------------------------ PDF
  static const _ink = PdfColor.fromInt(0xFF1E1916);
  static const _body = PdfColor.fromInt(0xFF4A5356);
  static const _soft = PdfColor.fromInt(0xFF7A8285);
  static const _green = PdfColor.fromInt(0xFFC84B31);
  static const _greenSoft = PdfColor.fromInt(0xFFFCEEE9);
  static const _rule = PdfColor.fromInt(0xFFE6E1D6);
  static const _zebra = PdfColor.fromInt(0xFFFBF9F4);

  Future<Uint8List?> _photoBytes() async {
    final p = recipe.itemPhoto;
    if (!opt.photo || p == null || p.isEmpty) return null;
    try {
      final url = ApiService.getImageUrl(p);
      if (url.startsWith('http')) {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        return r.statusCode == 200 ? r.bodyBytes : null;
      }
      final f = File(url);
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> pdf() async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-400.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-700.ttf'));
    final head = pw.Font.ttf(await rootBundle.load('assets/fonts/SpaceGrotesk-700.ttf'));
    final photo = await _photoBytes();
    final ls = lines, sum = summary;
    final showCost = opt.cost;
    final showK = opt.calories && sum.calories > 0;
    final plus = sum.missing > 0 ? '+' : '';
    final noPrice = sum.total == 0;
    String costText(double v) => noPrice ? '–' : '${money(v)}$plus';

    pw.TextStyle t(double size, {pw.Font? font, PdfColor color = _body, double? spacing}) =>
        pw.TextStyle(font: font ?? regular, fontSize: size, color: color, letterSpacing: spacing);
    pw.Widget cap(String s) => pw.Text(s.toUpperCase(), style: t(7.5, font: bold, color: _soft, spacing: .6));

    final facts = <List<String>>[
      ['Batch', '${grams(sum.grams)}$batchText'],
      ['Ingredients', '${ls.length}'],
      if (showK) ['Calories', '${group(sum.calories)} kcal'],
      if (showK && sum.kcalPer100g != null) ['Per 100 g', '${sum.kcalPer100g!.round()} kcal'],
      if (showCost) ['Batch cost', costText(sum.total)],
      if (showCost && sum.perKg != null) ['Per kg', costText(sum.perKg!)],
    ];
    final perRow = facts.length <= 4 ? facts.length : 3;

    final doc = pw.Document(title: recipe.name, author: 'Recipia', creator: 'Recipia');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(44, 38, 44, 34),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        margin: pw.EdgeInsets.only(bottom: ctx.pageNumber == 1 ? 22 : 14),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Row(children: [
            pw.Container(width: 11, height: 11, decoration: pw.BoxDecoration(color: _green, borderRadius: pw.BorderRadius.circular(3))),
            pw.SizedBox(width: 6),
            pw.Text(ctx.pageNumber == 1 ? 'Recipia' : 'Recipia · ${recipe.name}', style: t(10, font: head, color: _green)),
          ]),
          pw.Text(today(), style: t(8.5, color: _soft)),
        ]),
      ),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _rule))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Made with Recipia', style: t(7.5, color: _soft)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: t(7.5, color: _soft)),
        ]),
      ),
      build: (ctx) => [
        // title + photo
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: pw.BoxDecoration(color: _greenSoft, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Text(recipe.sectionName.toUpperCase(), style: t(7.5, font: bold, color: _green, spacing: .6)),
              ),
              pw.SizedBox(height: 7),
              pw.Text(recipe.name, style: t(26, font: head, color: _ink)),
              if ((recipe.brandName ?? '').trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(recipe.brandName!.trim(), style: t(9.5, color: _soft)),
              ],
            ]),
          ),
          if (photo != null) ...[
            pw.SizedBox(width: 18),
            pw.ClipRRect(
              horizontalRadius: 8,
              verticalRadius: 8,
              child: pw.Image(pw.MemoryImage(photo), width: 100, height: 100, fit: pw.BoxFit.cover),
            ),
          ],
        ]),
        pw.SizedBox(height: 16),
        // summary strip
        pw.Container(
          decoration: pw.BoxDecoration(color: _rule, border: pw.Border.all(color: _rule), borderRadius: pw.BorderRadius.circular(7)),
          child: pw.Column(children: [
            for (var i = 0; i < facts.length; i += perRow)
              pw.Row(children: [
                for (var j = i; j < i + perRow; j++)
                  pw.Expanded(
                    child: pw.Container(
                      margin: pw.EdgeInsets.only(right: j < i + perRow - 1 ? 1 : 0, top: i > 0 ? 1 : 0),
                      color: PdfColors.white,
                      padding: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),
                      child: j < facts.length
                          ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                              cap(facts[j][0]),
                              pw.SizedBox(height: 2),
                              pw.Text(facts[j][1], style: t(12, font: head, color: _ink)),
                            ])
                          : pw.SizedBox(),
                    ),
                  ),
              ]),
          ]),
        ),
        pw.SizedBox(height: 20),
        pw.Text('INGREDIENTS', style: t(10.5, font: head, color: _green, spacing: .5)),
        pw.SizedBox(height: 6),
        // ingredients table
        pw.Table(
          columnWidths: {
            if (opt.ticks) 0: const pw.FixedColumnWidth(20),
            (opt.ticks ? 1 : 0): const pw.FlexColumnWidth(),
            for (var c = (opt.ticks ? 2 : 1); c < (opt.ticks ? 3 : 2) + (showK ? 1 : 0) + (showCost ? 1 : 0); c++)
              c: const pw.FixedColumnWidth(72),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _green, width: 1.2))),
              children: [
                if (opt.ticks) pw.SizedBox(),
                _cell(cap('Ingredient')),
                _cell(cap('Amount'), right: true),
                if (showK) _cell(cap('kcal'), right: true),
                if (showCost) _cell(cap('Cost'), right: true),
              ],
            ),
            for (var i = 0; i < ls.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isOdd ? _zebra : null,
                  border: const pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFEFEBE2), width: .6)),
                ),
                verticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  if (opt.ticks)
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(left: 3),
                        width: 9,
                        height: 9,
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: const PdfColor.fromInt(0xFF9AA2A5), width: .9),
                            borderRadius: pw.BorderRadius.circular(2)),
                      ),
                    ),
                  _cell(pw.Text(ls[i].name, style: t(10, color: _ink))),
                  _cell(pw.RichText(
                      textAlign: pw.TextAlign.right,
                      text: pw.TextSpan(children: [
                        pw.TextSpan(text: qty(ls[i].qty, ls[i].unit), style: t(10, font: bold, color: _ink)),
                        pw.TextSpan(text: ' ${ls[i].unit}', style: t(10)),
                      ])), right: true),
                  if (showK)
                    _cell(pw.Text(ls[i].kcal == null || ls[i].kcal == 0 ? '–' : group(ls[i].kcal!), style: t(10)), right: true),
                  if (showCost)
                    _cell(pw.Text(ls[i].cost == null ? '–' : money(ls[i].cost!), style: t(10)), right: true),
                ],
              ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _green, width: 1.2))),
              children: [
                if (opt.ticks) pw.SizedBox(),
                _cell(pw.Text('Total', style: t(10, font: bold, color: _ink)), top: 8),
                _cell(pw.Text(grams(sum.grams), style: t(10, font: bold, color: _ink)), right: true, top: 8),
                if (showK) _cell(pw.Text(group(sum.calories), style: t(10, font: bold, color: _ink)), right: true, top: 8),
                if (showCost) _cell(pw.Text(costText(sum.total), style: t(10, font: bold, color: _ink)), right: true, top: 8),
              ],
            ),
          ],
        ),
        if (showCost && sum.missing > 0 && !noPrice)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('+ ${sum.missing} ingredient${sum.missing == 1 ? ' has' : 's have'} no price, so the cost is a minimum.',
                style: t(8, color: const PdfColor.fromInt(0xFF9A6A1F))),
          ),
        if (steps.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('METHOD', style: t(10.5, font: head, color: _green, spacing: .5)),
          pw.SizedBox(height: 6),
          for (var i = 0; i < steps.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(
                  width: 16,
                  height: 16,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(color: _green, shape: pw.BoxShape.circle),
                  child: pw.Text('${i + 1}', style: t(8, font: bold, color: PdfColors.white)),
                ),
                pw.SizedBox(width: 9),
                pw.Expanded(child: pw.Text(steps[i], style: t(10, color: _ink).copyWith(lineSpacing: 2.5))),
              ]),
            ),
        ],
      ],
    ));
    return doc.save();
  }

  pw.Widget _cell(pw.Widget child, {bool right = false, double top = 6}) => pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(5, top, 5, 6),
        child: pw.Align(alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft, child: child),
      );

  // ------------------------------------------------------------------ Excel
  /// Rows as shown in the app's preview (and written to the file).
  List<String> get xlsHeader => [
        'Ingredient', 'Qty', 'Unit',
        if (opt.cost) ...['Price', 'Per', 'Cost'],
        if (opt.calories && summary.calories > 0) 'kcal',
      ];

  List<int> xlsx() {
    final book = xl.Excel.createExcel();
    final first = book.getDefaultSheet() ?? 'Sheet1';
    book.rename(first, 'Ingredients');
    final sh = book['Ingredients'];
    final ls = lines, sum = summary;
    final showK = opt.calories && sum.calories > 0;
    final head = xlsHeader;
    final green = xl.ExcelColor.fromHexString('FF1F7A45');
    final greenSoft = xl.ExcelColor.fromHexString('FFE3F2E7');
    xl.CellIndex at(int c, int r) => xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
    String col(int c) => String.fromCharCode(65 + c);

    sh.updateCell(at(0, 0), xl.TextCellValue(recipe.name),
        cellStyle: xl.CellStyle(bold: true, fontSize: 14));
    sh.updateCell(at(0, 1),
        xl.TextCellValue('${recipe.sectionName} · batch ${factor % 1 == 0 ? factor.toInt() : factor}× · ${today()}'),
        cellStyle: xl.CellStyle(fontColorHex: xl.ExcelColor.fromHexString('FF666666')));
    const hr = 3; // header row (row 4 in Excel)
    for (var c = 0; c < head.length; c++) {
      sh.updateCell(at(c, hr), xl.TextCellValue(head[c]),
          cellStyle: xl.CellStyle(
              bold: true,
              fontColorHex: xl.ExcelColor.white,
              backgroundColorHex: green,
              horizontalAlign: c == 0 || c == 2 || (opt.cost && c == 4) ? xl.HorizontalAlign.Left : xl.HorizontalAlign.Right));
    }
    for (var i = 0; i < ls.length; i++) {
      final r = hr + 1 + i, l = ls[i];
      var c = 0;
      sh.updateCell(at(c++, r), xl.TextCellValue(l.name));
      sh.updateCell(at(c++, r), xl.DoubleCellValue(double.parse(l.qty.toStringAsFixed(3))));
      sh.updateCell(at(c++, r), xl.TextCellValue(l.unit));
      if (opt.cost) {
        sh.updateCell(at(c++, r), l.price == null ? null : xl.DoubleCellValue(l.price!));
        sh.updateCell(at(c++, r), l.priceUnit == null ? null : xl.TextCellValue(l.priceUnit!));
        sh.updateCell(at(c++, r), l.cost == null ? null : xl.DoubleCellValue(double.parse(l.cost!.toStringAsFixed(2))));
      }
      if (showK) {
        sh.updateCell(at(c++, r), l.kcal == null ? null : xl.DoubleCellValue(l.kcal!.roundToDouble()));
      }
    }
    // totals are real formulas, so they update when an amount is changed
    final tr = hr + 1 + ls.length;
    final first1 = hr + 2, last1 = hr + 1 + ls.length; // 1-based Excel rows
    final totalStyle = xl.CellStyle(bold: true, backgroundColorHex: greenSoft,
        topBorder: xl.Border(borderStyle: xl.BorderStyle.Medium, borderColorHex: green));
    sh.updateCell(at(0, tr), xl.TextCellValue('Total'), cellStyle: totalStyle);
    sh.updateCell(at(1, tr), xl.FormulaCellValue('SUMIF(C$first1:C$last1,"g",B$first1:B$last1)+SUMIF(C$first1:C$last1,"ml",B$first1:B$last1)+1000*SUMIF(C$first1:C$last1,"kg",B$first1:B$last1)'), cellStyle: totalStyle);
    sh.updateCell(at(2, tr), xl.TextCellValue('g'), cellStyle: totalStyle);
    for (var c = 3; c < head.length; c++) {
      final isSum = (opt.cost && c == 5) || (showK && c == head.length - 1);
      sh.updateCell(at(c, tr), isSum ? xl.FormulaCellValue('SUM(${col(c)}$first1:${col(c)}$last1)') : null,
          cellStyle: totalStyle);
    }
    sh.setColumnWidth(0, 28);
    for (var c = 1; c < head.length; c++) {
      sh.setColumnWidth(c, 11);
    }

    final m = book['Method'];
    m.updateCell(at(0, 0), xl.TextCellValue('Step'),
        cellStyle: xl.CellStyle(bold: true, fontColorHex: xl.ExcelColor.white, backgroundColorHex: green));
    m.updateCell(at(1, 0), xl.TextCellValue('Method'),
        cellStyle: xl.CellStyle(bold: true, fontColorHex: xl.ExcelColor.white, backgroundColorHex: green));
    final st = steps;
    for (var i = 0; i < st.length; i++) {
      m.updateCell(at(0, i + 1), xl.IntCellValue(i + 1));
      m.updateCell(at(1, i + 1), xl.TextCellValue(st[i]));
    }
    m.setColumnWidth(0, 6);
    m.setColumnWidth(1, 90);
    book.setDefaultSheet('Ingredients');
    return book.save() ?? <int>[];
  }

  /// grams helper used by the Excel preview
  static double gramsOf(double q, String u) => UnitConverter.toGrams(q, u);
}
