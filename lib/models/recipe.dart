import 'dart:convert';

class Recipe {
  final int id;
  final int userId;
  final String name;
  final String? brandName;
  final String sectionName;
  final String ingredients;
  final String process;
  final String? visibility;
  final String? itemPhoto;
  final String? recipePhoto;
  final String? createdAt;
  final int isPending;
  final String? ownerName;
  final int? sharedWithCount;
  final List<dynamic>? sharedWith;

  Recipe({
    required this.id,
    required this.userId,
    required this.name,
    this.brandName,
    required this.sectionName,
    required this.ingredients,
    required this.process,
    this.visibility,
    this.itemPhoto,
    this.recipePhoto,
    this.createdAt,
    this.isPending = 0,
    this.ownerName,
    this.sharedWithCount,
    this.sharedWith,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      brandName: json['brand_name'],
      sectionName: json['section_name'] ?? 'General',
      ingredients: (json['ingredients'] is String)
          ? json['ingredients']
          : (json['ingredients'] != null
              ? jsonEncode(json['ingredients'])
              : ''),
      process: json['process'] ?? '',
      visibility: json['visibility'] ?? 'private',
      itemPhoto: json['item_photo'],
      recipePhoto: json['recipe_photo'],
      createdAt: json['created_at'],
      isPending: json['is_pending'] ?? 0,
      ownerName: json['owner_name'],
      sharedWithCount: json['shared_with_count'],
      sharedWith: json['shared_with'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'brand_name': brandName,
      'section_name': sectionName,
      'ingredients': ingredients,
      'process': process,
      'visibility': visibility,
      'item_photo': itemPhoto,
      'recipe_photo': recipePhoto,
      'created_at': createdAt,
      'is_pending': isPending,
      'owner_name': ownerName,
      'shared_with_count': sharedWithCount,
      'shared_with': sharedWith,
    };
  }
}
