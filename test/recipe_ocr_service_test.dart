import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/recipe_ocr_service.dart';

void main() {
  test('parses diverse recipe OCR lines without missing items', () {
    final result = RecipeOcrService.parseLines([
      'Honey Garlic Glaze',
      'Ingredients:',
      '1. Soy Sauce .... 180 ml',
      '2) 25Og Honey',
      'Garlic - 20g (chopped)',
      '½ cup Brown Sugar',
      'l00 ml Water',
      '2-3 tbsp Ginger Paste',
      'Eggs 3',
      '4 Green Chillies',
      'Salt 5g, Black Pepper 3g',
      'Sesame Oil to taste',
      'Cornflour',
      '25 grams',
      'Method:',
      '1. Mix everything and simmer for 10 minutes.',
    ]);

    expect(result['name'], 'Honey Garlic Glaze');
    final ings = (result['ingredients'] as List).cast<Map<String, String>>();
    expect(ings.length, 12);
    expect(ings[0], {'name': 'Soy Sauce', 'qty': '180', 'unit': 'ml'});
    expect(ings[1], {'name': 'Honey', 'qty': '250', 'unit': 'g'});
    expect(ings[2], {'name': 'Garlic', 'qty': '20', 'unit': 'g'});
    expect(ings[3], {'name': 'Brown Sugar', 'qty': '0.5', 'unit': 'cup'});
    expect(ings[4], {'name': 'Water', 'qty': '100', 'unit': 'ml'});
    expect(ings[5], {'name': 'Ginger Paste', 'qty': '2', 'unit': 'tbsp'});
    expect(ings[6], {'name': 'Eggs', 'qty': '3', 'unit': 'piece'});
    expect(ings[7], {'name': 'Green Chillies', 'qty': '4', 'unit': 'piece'});
    expect(ings[8], {'name': 'Salt', 'qty': '5', 'unit': 'g'});
    expect(ings[9], {'name': 'Black Pepper', 'qty': '3', 'unit': 'g'});
    expect(ings[10], {'name': 'Sesame Oil', 'qty': '1', 'unit': 'pinch'});
    expect(ings[11], {'name': 'Cornflour', 'qty': '25', 'unit': 'g'});
    expect(result['process'], contains('simmer for 10 minutes'));
  });
}
