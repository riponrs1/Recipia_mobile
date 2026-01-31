import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'database_helper.dart';

class GeminiService {
  static const String _modelName = 'gemini-1.5-flash';

  Future<Map<String, dynamic>?> analyzeRecipeImage(String imagePath) async {
    try {
      // 1. Get API Key from cache or secure storage (using DatabaseHelper's app_cache for now)
      // If none found, we'll need the user to provide it or use a default if you have one.
      final apiKeyData = await DatabaseHelper().getCachedData('gemini_api_key');
      final apiKey = apiKeyData ?? '';

      if (apiKey.isEmpty) {
        throw Exception(
            "Gemini API Key is not set. Please add it in settings.");
      }

      final model = GenerativeModel(
        model: _modelName,
        apiKey: apiKey,
      );

      final imageBytes = await File(imagePath).readAsBytes();

      final prompt = """
      Analyze this image of a handwritten or printed recipe. Extract the following information into a structured JSON object:
      - name: The title of the recipe
      - brand_name: The brand or source (or null if not found)
      - section_name: Suggest one from existing categories or use a general one.
      - ingredients: An array of objects, each with 'name', 'qty', and 'unit'. 
      - process: The cooking instructions as a single string.

      Return ONLY the raw JSON object. Do not include markdown code blocks or any other text.
      """;

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await model.generateContent(content);

      if (response.text != null) {
        String text = response.text!.trim();
        // Clean markdown code blocks if present
        text = text.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(text) as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('Gemini Service Error: $e');
      rethrow;
    }
  }

  Future<void> saveApiKey(String key) async {
    await DatabaseHelper().cacheData('gemini_api_key', key);
  }

  Future<String?> getApiKey() async {
    return await DatabaseHelper().getCachedData('gemini_api_key');
  }
}
