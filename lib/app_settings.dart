import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight app-wide settings (currency symbol, etc.).
/// Loaded once at startup; read synchronously where prices are shown.
class AppSettings {
  static String currency = '৳';

  /// Unit for new ingredient rows in the recipe form (g, ml, kg, piece).
  static String defaultUnit = 'g';
  static const units = {'g': 'g', 'ml': 'ml', 'kg': 'kg', 'piece': 'pcs'};

  /// Show total weight on recipe cards.
  static bool showWeights = true;

  /// Bumped on every change so open screens can redraw.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// name -> symbol. Add more as needed.
  static const Map<String, String> currencies = {
    'BDT ৳': '৳',
    'USD \$': '\$',
    'EUR €': '€',
    'GBP £': '£',
    'INR ₹': '₹',
    'AED د.إ': 'د.إ',
    'SAR ﷼': '﷼',
    'PKR ₨': '₨',
  };

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      currency = prefs.getString('currency_symbol') ?? '৳';
      defaultUnit = prefs.getString('default_unit') ?? 'g';
      if (!units.containsKey(defaultUnit)) defaultUnit = 'g';
      showWeights = prefs.getBool('show_weights') ?? true;
    } catch (_) {
      currency = '৳';
    }
  }

  static Future<void> setCurrency(String symbol) async {
    currency = symbol;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currency_symbol', symbol);
    } catch (_) {}
    changes.value++;
  }

  static Future<void> setDefaultUnit(String unit) async {
    defaultUnit = unit;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_unit', unit);
    } catch (_) {}
    changes.value++;
  }

  static Future<void> setShowWeights(bool v) async {
    showWeights = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_weights', v);
    } catch (_) {}
    changes.value++;
  }
}
