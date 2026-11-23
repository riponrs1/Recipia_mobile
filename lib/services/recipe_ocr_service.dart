import 'dart:math' as math;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Offline on-device OCR + recipe parser using Google ML Kit.
/// Extracts `{name, ingredients: [{name, qty, unit}], process, _source, _rawText}`
/// from a photo with zero internet or API key required.
class RecipeOcrService {
  static const Map<String, String> _unitAliases = {
    'g': 'g',
    'gm': 'g',
    'gms': 'g',
    'gr': 'g',
    'gram': 'g',
    'grams': 'g',
    'kg': 'kg',
    'kgs': 'kg',
    'kilo': 'kg',
    'kilos': 'kg',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'ml': 'ml',
    'mls': 'ml',
    'l': 'l',
    'lt': 'l',
    'ltr': 'l',
    'ltrs': 'l',
    'liter': 'l',
    'liters': 'l',
    'litre': 'l',
    'litres': 'l',
    'cup': 'cup',
    'cups': 'cup',
    'tbsp': 'tbsp',
    'tbs': 'tbsp',
    'tb': 'tbsp',
    'tbspn': 'tbsp',
    'tablespoon': 'tbsp',
    'tablespoons': 'tbsp',
    'tsp': 'tsp',
    'ts': 'tsp',
    'tspn': 'tsp',
    'teaspoon': 'tsp',
    'teaspoons': 'tsp',
    'oz': 'oz',
    'ounce': 'oz',
    'ounces': 'oz',
    'lb': 'lb',
    'lbs': 'lb',
    'pound': 'lb',
    'pounds': 'lb',
    'pc': 'piece',
    'pcs': 'piece',
    'piece': 'piece',
    'pieces': 'piece',
    'no': 'piece',
    'nos': 'piece',
    'ea': 'piece',
    'each': 'piece',
    'clove': 'piece',
    'cloves': 'piece',
    'slice': 'piece',
    'slices': 'piece',
    'pkt': 'piece',
    'pkts': 'piece',
    'pack': 'piece',
    'packs': 'piece',
    'packet': 'piece',
    'packets': 'piece',
    'can': 'piece',
    'cans': 'piece',
    'tin': 'piece',
    'tins': 'piece',
    'bag': 'piece',
    'bags': 'piece',
    'bunch': 'piece',
    'bunches': 'piece',
    'bottle': 'piece',
    'bottles': 'piece',
    'box': 'piece',
    'boxes': 'piece',
    'stick': 'piece',
    'sticks': 'piece',
    'sprig': 'piece',
    'sprigs': 'piece',
    'leaf': 'piece',
    'leaves': 'piece',
    'whole': 'piece',
    'pinch': 'pinch',
    'pinches': 'pinch',
    'dash': 'pinch',
    'dashes': 'pinch',
    'drop': 'pinch',
    'drops': 'pinch',
  };

  /// Longest-first alternation so `grams` matches before `gram` before `gm` before `g`.
  static final String _unitPattern = () {
    final keys = _unitAliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return keys.join('|');
  }();

  static const String _qtyToken =
      r'(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?)';

  /// Runs on-device ML Kit OCR on [imagePath] and parses recipe fields.
  static Future<Map<String, dynamic>> scanPhoto(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);

      final allLines = <TextLine>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) {
            allLines.add(line);
          }
        }
      }

      if (allLines.isEmpty) {
        throw Exception(
            'No readable text found in this photo. Try a clearer, brighter shot.');
      }

      final visualRows = _reconstructVisualRows(allLines);
      final parsed = parseLines(visualRows);
      parsed['_rawText'] = visualRows.join('\n');
      return parsed;
    } finally {
      await recognizer.close();
    }
  }

  /// Reconstructs visual horizontal rows from ML Kit [TextLine] bounding boxes.
  /// Fixes 2-column recipe tables where ML Kit puts ingredient names in one block
  /// and quantities in a separate block.
  static List<String> _reconstructVisualRows(List<TextLine> lines) {
    final sorted = List<TextLine>.from(lines)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rows = <List<TextLine>>[];
    for (final line in sorted) {
      final box = line.boundingBox;
      final cy = (box.top + box.bottom) / 2.0;
      final h = math.max(1.0, box.height.toDouble());

      List<TextLine>? bestRow;
      double bestDist = double.infinity;

      for (final row in rows) {
        double sumCy = 0;
        double sumH = 0;
        double rowTop = double.infinity;
        double rowBottom = -double.infinity;
        for (final r in row) {
          sumCy += (r.boundingBox.top + r.boundingBox.bottom) / 2.0;
          sumH += math.max(1.0, r.boundingBox.height.toDouble());
          rowTop = math.min(rowTop, r.boundingBox.top.toDouble());
          rowBottom = math.max(rowBottom, r.boundingBox.bottom.toDouble());
        }
        final avgCy = sumCy / row.length;
        final avgH = sumH / row.length;

        final overlap =
            math.min(box.bottom.toDouble(), rowBottom) -
            math.max(box.top.toDouble(), rowTop);
        final minH = math.min(h, avgH);
        final dist = (cy - avgCy).abs();

        final sameRow = (overlap >= minH * 0.35) || (dist <= math.max(10.0, avgH * 0.55));
        if (sameRow && dist < bestDist) {
          bestDist = dist;
          bestRow = row;
        }
      }

      if (bestRow != null) {
        bestRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    // Sort rows top-to-bottom, and within each row left-to-right.
    rows.sort((a, b) {
      final ay = a.map((e) => e.boundingBox.top).reduce(math.min);
      final by = b.map((e) => e.boundingBox.top).reduce(math.min);
      return ay.compareTo(by);
    });

    final result = <String>[];
    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final joined = row.map((e) => e.text.trim()).where((s) => s.isNotEmpty).join(' ');
      if (joined.isNotEmpty) result.add(joined);
    }
    return result;
  }

  /// Normalizes Unicode fractions and common OCR digit/unit typos.
  static String _normalizeLine(String raw) {
    var s = raw
        .replaceAll('½', ' 1/2 ')
        .replaceAll('¼', ' 1/4 ')
        .replaceAll('¾', ' 3/4 ')
        .replaceAll('⅓', ' 1/3 ')
        .replaceAll('⅔', ' 2/3 ')
        .replaceAll('⅛', ' 1/8 ')
        .replaceAll('⅜', ' 3/8 ')
        .replaceAll('⅝', ' 5/8 ')
        .replaceAll('⅞', ' 7/8 ');

    // Collapse spaced decimals like "1 . 5 kg" -> "1.5 kg"
    s = s.replaceAllMapped(
      RegExp(r'(\d)\s*\.\s*(\d)'),
      (m) => '${m.group(1)}.${m.group(2)}',
    );

    // Fix OCR 'O'/'o' inside numbers (e.g. "25Og" -> "250g", "1OO ml" -> "100 ml")
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d)[Oo]+(?=\d|\s*(?:g|gm|gms|kg|ml|l|oz|lb|cup|tbsp|tsp)\b)',
          caseSensitive: false),
      (m) => '0' * m.group(0)!.length,
    );

    // Fix OCR 'l'/'I' at the start of a quantity (e.g. "l00 g" -> "100 g")
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)[lI](?=\d{1,3}\s*(?:g|gm|gms|kg|ml|l|oz|lb|cup|tbsp|tsp)\b)',
          caseSensitive: false),
      (m) => m.group(0)!.replaceFirst(RegExp(r'[lI]'), '1'),
    );

    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// Parses OCR text lines into `{name, ingredients, process}`.
  static Map<String, dynamic> parseLines(List<String> lines) {
    String? title;
    final ingredients = <Map<String, String>>[];
    final methodLines = <String>[];
    bool inMethod = false;

    final methodHeaderRe = RegExp(
      r'^(method|instructions?|directions?|process|steps?|preparation|how to make)\s*:?\s*$',
      caseSensitive: false,
    );
    final ingHeaderRe = RegExp(
      r'^(ingredients?|items?|materials?|recipe|list)\s*:?\s*$',
      caseSensitive: false,
    );
    final qtyUnitOnlyRe = RegExp(
      '^($_qtyToken)\\s*($_unitPattern)\\.?\$',
      caseSensitive: false,
    );

    final normalizedLines = lines
        .map(_normalizeLine)
        .where((l) => l.isNotEmpty)
        .toList();

    // Pre-merge 2-line pairs where "Flour" is on one line and "250 g" on the next
    // OR "250 g" is on one line and "Flour" is on the next.
    final merged = <String>[];
    for (int i = 0; i < normalizedLines.length; i++) {
      final cur = normalizedLines[i];
      if (i + 1 < normalizedLines.length) {
        final next = normalizedLines[i + 1];
        if (qtyUnitOnlyRe.hasMatch(next) &&
            !qtyUnitOnlyRe.hasMatch(cur) &&
            !ingHeaderRe.hasMatch(cur) &&
            !methodHeaderRe.hasMatch(cur) &&
            _parseIngredientLine(cur) == null) {
          merged.add('$cur $next');
          i++;
          continue;
        }
        if (qtyUnitOnlyRe.hasMatch(cur) &&
            !qtyUnitOnlyRe.hasMatch(next) &&
            !ingHeaderRe.hasMatch(next) &&
            !methodHeaderRe.hasMatch(next) &&
            _parseIngredientLine(next) == null) {
          merged.add('$cur $next');
          i++;
          continue;
        }
      }
      merged.add(cur);
    }

    for (final raw in merged) {
      var line = raw
          .replaceFirst(RegExp(r'^[•\-\*\u2022\u25CF\u25AA\u2023☐☑✓✔]+\s*'), '')
          .trim();
      if (line.isEmpty) continue;

      if (methodHeaderRe.hasMatch(line)) {
        inMethod = true;
        continue;
      }
      if (ingHeaderRe.hasMatch(line)) {
        inMethod = false;
        continue;
      }

      if (inMethod) {
        methodLines.add(line);
        continue;
      }

      // Skip obvious total / table header / metadata rows
      if (RegExp(
        r'^(total|subtotal|batch|servings?|yield|cost|date|qty|quantity|unit|weight|sl\.?\s*no|sr\.?\s*no|#)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }

      // Strip leading item index ("1. Flour 250g" or "02) 180ml Soy Sauce")
      final withoutIndex =
          line.replaceFirst(RegExp(r'^\d{1,2}\s*[.)]\s+'), '').trim();

      // Check for multiple ingredients on a single line (e.g. "Salt 5g, Pepper 3g")
      final multi = _tryParseMultiple(withoutIndex);
      if (multi != null && multi.isNotEmpty) {
        ingredients.addAll(multi);
        continue;
      }

      final parsed = _parseIngredientLine(withoutIndex) ??
          (withoutIndex != line ? _parseIngredientLine(line) : null);
      if (parsed != null) {
        ingredients.add(parsed);
        continue;
      }

      // Numbered cooking step (e.g. "1. Mix all ingredients well and simmer")
      if (RegExp(r'^\d+[.)]\s+[A-Za-z]{3,}.*\s+').hasMatch(line) &&
          line.length > 28) {
        methodLines.add(line);
        continue;
      }

      // First clean short line before ingredients is likely the recipe title
      if (title == null &&
          ingredients.isEmpty &&
          line.length >= 3 &&
          line.length <= 60 &&
          !RegExp(r'^\d+$').hasMatch(line)) {
        title = line;
      } else if (ingredients.isNotEmpty && line.length > 24) {
        methodLines.add(line);
      }
    }

    return {
      'name': title ?? '',
      'ingredients': ingredients,
      'process': methodLines.join('\n'),
      '_source': 'offline_ocr',
    };
  }

  static List<Map<String, String>>? _tryParseMultiple(String line) {
    if (!line.contains('|') && !line.contains(';')) {
      // Only split on comma if there are at least 2 numeric tokens
      final numMatches = RegExp(r'\d').allMatches(line).length;
      if (!line.contains(',') || numMatches < 2) return null;
    }
    final parts = line
        .split(RegExp(r'\s*[|;,]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;

    final out = <Map<String, String>>[];
    for (final p in parts) {
      final parsed = _parseIngredientLine(p);
      if (parsed == null) return null;
      out.add(parsed);
    }
    return out;
  }

  static Map<String, String>? _parseIngredientLine(String line) {
    // Pattern 1: "250 g Flour" / "1 1/2 cups Sugar" / "2-3 tbsp Soy Sauce"
    final qtyFirst = RegExp(
      '^($_qtyToken)\\s*($_unitPattern)\\.?\\s+(?:of\\s+)?(.+)\$',
      caseSensitive: false,
    ).firstMatch(line);
    if (qtyFirst != null) {
      final qty = _normalizeQty(qtyFirst.group(1)!);
      final unit = _unitAliases[qtyFirst.group(2)!.toLowerCase()] ?? 'g';
      final name = _cleanName(qtyFirst.group(3)!);
      if (name.isNotEmpty) {
        return {'name': name, 'qty': qty, 'unit': unit};
      }
    }

    // Pattern 2: "Soy Sauce .... 180 ml" / "Garlic - 20g (chopped)" / "Salt: 5 g"
    final qtyLast = RegExp(
      '^(.+?)[\\s.:\\-—–=]+($_qtyToken)\\s*($_unitPattern)\\.?(?:\\s*(?:\\([^)]*\\)|,\\s*[A-Za-z\\s]+))?\$',
      caseSensitive: false,
    ).firstMatch(line);
    if (qtyLast != null) {
      final name = _cleanName(qtyLast.group(1)!);
      final qty = _normalizeQty(qtyLast.group(2)!);
      final unit = _unitAliases[qtyLast.group(3)!.toLowerCase()] ?? 'g';
      if (name.isNotEmpty && !RegExp(r'^\d+$').hasMatch(name)) {
        return {'name': name, 'qty': qty, 'unit': unit};
      }
    }

    // Pattern 3: "3 Eggs" / "1/2 Lemon" (count first without explicit unit)
    final countFirst = RegExp(
      '^($_qtyToken)\\s+([A-Za-z][A-Za-z\\s,&\\-()]{1,40})\$',
    ).firstMatch(line);
    if (countFirst != null) {
      final qty = _normalizeQty(countFirst.group(1)!);
      final name = _cleanName(countFirst.group(2)!);
      if (name.isNotEmpty &&
          !RegExp(r'^(step|part|day|min|mins|minute|minutes|hr|hrs|hour|hours|sec|degree|degrees)\b',
                  caseSensitive: false)
              .hasMatch(name)) {
        return {'name': name, 'qty': qty, 'unit': 'piece'};
      }
    }

    // Pattern 4: "Eggs 3" / "Bay leaf - 2" / "Green chilli: 4" (count last without unit)
    final countLast = RegExp(
      '^([A-Za-z][A-Za-z\\s,&\\-()]{1,40}?)[\\s.:\\-—–=]+($_qtyToken)\$',
    ).firstMatch(line);
    if (countLast != null) {
      final name = _cleanName(countLast.group(1)!);
      final qty = _normalizeQty(countLast.group(2)!);
      if (name.isNotEmpty &&
          !RegExp(r'^(step|part|day|page|recipe|batch|serving|servings|no)\b',
                  caseSensitive: false)
              .hasMatch(name)) {
        return {'name': name, 'qty': qty, 'unit': 'piece'};
      }
    }

    // Pattern 5: "Salt to taste" / "Water as needed" / "Oil for frying"
    final toTaste = RegExp(
      r'^([A-Za-z][A-Za-z\s,&\-]{1,35}?)\s*[-–:,]?\s*(to taste|as needed|as required|for frying|for garnish|optional)\.?$',
      caseSensitive: false,
    ).firstMatch(line);
    if (toTaste != null) {
      final name = _cleanName(toTaste.group(1)!);
      if (name.isNotEmpty) {
        return {'name': name, 'qty': '1', 'unit': 'pinch'};
      }
    }

    return null;
  }

  static String _cleanName(String s) {
    return s
        .replaceAll(RegExp(r'^[\s.\-:—–•*=]+|[\s.\-:—–=]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static String _normalizeQty(String raw) {
    var s = raw.trim().replaceAll(',', '.');
    // Range like "2-3" or "100–150" -> use the first number
    final range = RegExp(r'^(\d+(?:\.\d+)?)\s*[-–]\s*\d+(?:\.\d+)?$').firstMatch(s);
    if (range != null) {
      s = range.group(1)!;
    }
    // Mixed fraction: "1 1/2"
    final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(s);
    if (mixed != null) {
      final whole = double.parse(mixed.group(1)!);
      final num = double.parse(mixed.group(2)!);
      final den = double.parse(mixed.group(3)!);
      if (den != 0) return _fmtDouble(whole + num / den);
    }
    // Simple fraction: "1/2"
    final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(s);
    if (frac != null) {
      final num = double.parse(frac.group(1)!);
      final den = double.parse(frac.group(2)!);
      if (den != 0) return _fmtDouble(num / den);
    }
    final d = double.tryParse(s);
    return d != null ? _fmtDouble(d) : s;
  }

  static String _fmtDouble(double v) => v % 1 == 0
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
