class UnitConverter {
  /// Converts a given quantity and unit to grams.
  ///
  /// Uses standard water density (1ml = 1g) for volume conversions.
  /// Returns 0 if the unit is unknown or 'piece'.
  static double toGrams(double qty, String unit) {
    final u = unit.toLowerCase().trim();

    switch (u) {
      // Weight
      case 'g':
      case 'gram':
      case 'grams':
        return qty;
      case 'kg':
      case 'kilogram':
      case 'kilograms':
        return qty * 1000;
      case 'oz':
      case 'ounce':
      case 'ounces':
        return qty * 28.3495;
      case 'lb':
      case 'lbs':
      case 'pound':
      case 'pounds':
        return qty * 453.592;

      // Volume (assuming water density 1g/ml)
      case 'ml':
      case 'milliliter':
      case 'milliliters':
        return qty; // 1 ml = 1 g
      case 'l':
      case 'liter':
      case 'liters':
        return qty * 1000;
      case 'tsp':
      case 'teaspoon':
      case 'teaspoons':
        return qty * 4.92892; // ~5g
      case 'tbsp':
      case 'tablespoon':
      case 'tablespoons':
        return qty * 14.7868; // ~15g
      case 'cup':
      case 'cups':
        return qty * 236.588; // ~240g (US cup)
      case 'cl':
      case 'centiliter':
        return qty * 10;

      // Abstract / Small units
      case 'pinch':
      case 'pinches':
        return qty *
            0.36; // A pinch is roughly 1/8 tsp -> ~0.6g? 0.36g is a common dry pinch estimate.

      // Non-convertible
      case 'piece':
      case 'pcs':
      case 'item':
      default:
        return 0.0;
    }
  }
}
