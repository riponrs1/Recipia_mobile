class Ingredient {
  final int id;
  final String name;
  final String? brand;
  final String category;
  final double? price;
  final String? unit;
  final double? calories;

  Ingredient({
    required this.id,
    required this.name,
    this.brand,
    required this.category,
    this.price,
    this.unit,
    this.calories,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: json['id'] is String ? int.parse(json['id']) : json['id'],
      name: json['name'] ?? '',
      brand: json['brand'],
      category: json['category'] ?? 'Uncategorized',
      price: _toDouble(json['price']),
      unit: json['unit'],
      calories: _toDouble(json['calories']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'category': category,
      'price': price,
      'unit': unit,
      'calories': calories,
    };
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
