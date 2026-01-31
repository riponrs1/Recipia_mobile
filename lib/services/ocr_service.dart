import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<Map<String, dynamic>> scanRecipe(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return _parseRecipeText(recognizedText.text);
    } catch (e) {
      print('OCR Error: $e');
      return {};
    }
  }

  Map<String, dynamic> _parseRecipeText(String text) {
    List<String> lines = text.split('\n');
    String title = '';
    List<Map<String, dynamic>> ingredients = [];
    StringBuffer processBuffer = StringBuffer();

    bool foundIngredientsParams = false;
    bool inIngredientsSection = false;
    bool inProcessSection = false;

    // Keywords to identify sections
    final ingredientKeywords = ['ingredients', 'shopping list', 'needs'];
    final processKeywords = [
      'instructions',
      'method',
      'preparation',
      'steps',
      'directions'
    ];

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      String lowerLine = line.toLowerCase();

      // HEURISTIC 1: Detect Section Headers
      bool isIngredientHeader =
          ingredientKeywords.any((k) => lowerLine.contains(k));
      bool isProcessHeader = processKeywords.any((k) => lowerLine.contains(k));

      if (isIngredientHeader) {
        inIngredientsSection = true;
        inProcessSection = false;
        foundIngredientsParams = true;
        continue;
      }
      if (isProcessHeader) {
        inIngredientsSection = false;
        inProcessSection = true;
        continue;
      }

      // HEURISTIC 2: Fallback if no headers found yet
      // If we haven't found any headers, assume the first non-empty line is the Title
      if (title.isEmpty) {
        title = line;
        continue;
      }

      // If we are in ingredients section OR (no headers found yet but line looks like amount)
      if (inIngredientsSection ||
          (!foundIngredientsParams && _looksLikeIngredient(line))) {
        // Parse ingredient line
        final parsed = _parseIngredientLine(line);
        if (parsed != null) {
          ingredients.add(parsed);
        } else {
          // If it doesn't look like an ingredient, maybe it's part of the title or garbage,
          // or maybe we should just add it to process if we are confused.
          // For now, let's treat it as possibly process text if we strictly found ingredients before.
        }
      }
      // Everything else goes to process
      else {
        if (processBuffer.isNotEmpty) processBuffer.write('\n');
        processBuffer.write(line);
      }
    }

    // Post-processing: If we didn't find any explicit ingredients, maybe the prompt was unstructured.
    // But ML Kit usually returns blocks. Simpler approach is better for v1.

    return {
      'name': title,
      'ingredients': ingredients,
      'process': processBuffer.toString(),
      'brand_name': null,
      'section_name': null,
    };
  }

  bool _looksLikeIngredient(String line) {
    // Starts with a number? "1 cup..."
    return RegExp(r'^[\d½¼¾⅛⅓⅔]+').hasMatch(line);
  }

  Map<String, dynamic>? _parseIngredientLine(String line) {
    // Very basic parsing: try to split first number as quantity
    // "1 cup flour" -> qty: 1, unit: cup, name: flour

    final RegExp regex = RegExp(r'^([\d\.\,\/½¼¾⅛⅓⅔]+)\s*([a-zA-Z]+)?\s*(.*)');
    final match = regex.firstMatch(line);

    if (match != null) {
      String qty = match.group(1)?.trim() ?? '';
      String possibleUnit = match.group(2)?.trim() ?? '';
      String name = match.group(3)?.trim() ?? '';

      // If unit is missing (e.g. "2 eggs"), the name captured both.
      // We rely on the app's dropdown to fuzzy match or default to 'Other...'

      // Simplify fractions
      qty = qty
          .replaceAll('½', '0.5')
          .replaceAll('¼', '0.25')
          .replaceAll('¾', '0.75')
          .replaceAll('⅓', '0.33')
          .replaceAll('⅔', '0.66');

      return {
        'qty': qty,
        'unit': possibleUnit, // The UI will try to match this to known units
        'name': name.isEmpty
            ? possibleUnit
            : name, // Swap if unit was actually the name
      };
    }

    return {'name': line, 'qty': '', 'unit': ''};
  }
}
