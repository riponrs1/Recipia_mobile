import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'services/price_book.dart';

/// Every plain request gives up after 20 s, so a slow or unreachable server
/// never leaves a screen spinning; callers then fall back to the phone copy.
class _TimeoutClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 20));
}

final _http = _TimeoutClient();

class ApiService {
  static const String baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://recipia.bicitra.com/api');

  static String get storageUrl {
    const envStorage = String.fromEnvironment('STORAGE_URL');
    if (envStorage.isNotEmpty) return envStorage;
    if (baseUrl.contains('192.168.') ||
        baseUrl.contains('10.0.2.2') ||
        baseUrl.contains('localhost')) {
      return baseUrl.replaceAll('/api', '');
    }
    return 'https://recipia.bicitra.com';
  }

  static String getImageUrl(String path) {
    if (path.isEmpty) return '';
    // the server may still hand out http:// links; Android blocks plain http
    if (path.startsWith('http://recipia.bicitra.com')) {
      return path.replaceFirst('http://', 'https://');
    }
    if (path.startsWith('http')) return path;
    // Local file path check
    if (path.startsWith('/') ||
        path.startsWith('file://') ||
        path.contains('com.recipia.com') ||
        path.contains('data/user')) {
      return path;
    }

    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('storage/')) {
      path = 'storage/$path';
    }

    return '$storageUrl/$path';
  }

  Future<String?> login(String email, String password) async {
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        // set while the account waits to be deleted (30-day grace period)
        final scheduled = data['deletion_scheduled_for'];
        if (scheduled is String && scheduled.isNotEmpty) {
          await prefs.setString('deletion_scheduled_for', scheduled);
        } else {
          await prefs.remove('deletion_scheduled_for');
        }
        return null;
      } else {
        final data = jsonDecode(response.body);
        return data['message'] ?? 'Login failed';
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  /// Sends the reset link. Returns null when sent; otherwise the reason
  /// (e.g. "We can't find a user with that email address.").
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/password/email'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) return null;
      final data = jsonDecode(response.body);
      return (data['message'] ?? 'Could not send the link').toString();
    } catch (e) {
      return 'No connection. Check your internet and try again.';
    }
  }

  /// Create an account. Returns null on success, or field -> message
  /// ('name', 'email', 'password' or '_' for a general problem).
  Future<Map<String, String>?> registerAccount(
      String name, String email, String password, String confirmation) async {
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'password_confirmation': confirmation,
        }),
      );
      final data = jsonDecode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['access_token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token']);
        return null;
      }
      final out = <String, String>{};
      final errors = data['errors'];
      if (errors is Map) {
        errors.forEach((k, v) {
          if (v is List && v.isNotEmpty) out[k.toString()] = v.first.toString();
        });
      }
      if (out.isEmpty) out['_'] = (data['message'] ?? 'Could not create the account').toString();
      return out;
    } catch (e) {
      return {'_': 'No connection. Check your internet and try again.'};
    }
  }

  Future<String?> register(String name, String email, String password,
      String passwordConfirmation) async {
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'password_confirmation': passwordConfirmation,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['access_token'] != null) {
          final token = data['access_token'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
        }
        return null;
      } else {
        final data = jsonDecode(response.body);
        return data['message'] ?? 'Registration failed';
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  Future<Map<String, dynamic>> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await DatabaseHelper().cacheData('user_profile', data);
        return data;
      } else {
        throw Exception('Failed to load user profile');
      }
    } catch (e) {
      final cached = await DatabaseHelper().getCachedData('user_profile');
      if (cached != null) return cached;

      // Fallback for any connection error (Offline mode support)
      return {'id': 0, 'name': 'Offline Chef', 'email': 'local'};
    }
  }

  Future<Map<String, dynamic>> getHomeStats() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      final recipes = await DatabaseHelper().getCachedRecipes();
      final ingredients = await DatabaseHelper().getCachedIngredients();
      return {
        'total_recipes': recipes.length,
        'total_ingredients': ingredients.length,
        'total_shared': 0,
        'recent_recipes': recipes.take(5).toList(),
      };
    }

    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/home'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await DatabaseHelper().cacheData('home_stats', data);
        return data;
      } else {
        throw Exception('Failed to load home stats');
      }
    } catch (e) {
      final cached = await DatabaseHelper().getCachedData('home_stats');
      if (cached != null) return cached;

      // Fallback for any connection error (Offline mode support)
      final recipes = await DatabaseHelper().getCachedRecipes();
      final ingredients = await DatabaseHelper().getCachedIngredients();
      return {
        'total_recipes': recipes.length,
        'total_ingredients': ingredients.length,
        'total_shared': 0,
        'recent_recipes': recipes.take(5).toList(),
      };
    }
  }

  Future<List<dynamic>> getRecipes() async {
    syncPendingActions();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      return await DatabaseHelper().getCachedRecipes();
    }

    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/recipes'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final recipes = jsonDecode(response.body);
        await DatabaseHelper().cacheRecipes(recipes);
        return recipes;
      } else {
        throw Exception('Failed to load recipes');
      }
    } catch (e) {
      final localRecipes = await DatabaseHelper().getCachedRecipes();
      return localRecipes; // Returns cached recipes or empty list if none
    }
  }

  Future<List<dynamic>> getMyRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      return await DatabaseHelper().getCachedRecipes();
    }

    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/my-recipes'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> recipes = jsonDecode(response.body);
        await DatabaseHelper().cacheRecipes(recipes);
        return recipes;
      } else {
        throw Exception('Failed to load my recipes');
      }
    } catch (e) {
      final localRecipes = await DatabaseHelper().getCachedRecipes();
      return localRecipes;
    }
  }

  Future<Map<String, dynamic>> getRecipe(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      final recipe = await DatabaseHelper().getRecipeById(id);
      if (recipe != null) return recipe;
      throw Exception('Recipe not found locally');
    }

    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/recipes/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load recipe');
      }
    } catch (e) {
      final recipe = await DatabaseHelper().getRecipeById(id);
      if (recipe != null) return recipe;
      throw Exception('Connection error: $e');
    }
  }

  Future<String?> createRecipe(Map<String, dynamic> data,
      {String? itemPhotoPath,
      String? recipePhotoPath,
      bool allowFallback = true}) async {
    itemPhotoPath = await _saveFilePermanently(itemPhotoPath);
    recipePhotoPath = await _saveFilePermanently(recipePhotoPath);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/recipes'));
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      data.forEach((key, value) {
        request.fields[key] = value.toString();
      });

      if (itemPhotoPath != null && itemPhotoPath.isNotEmpty) {
        request.files.add(
            await http.MultipartFile.fromPath('item_photo', itemPhotoPath));
      }
      if (recipePhotoPath != null && recipePhotoPath.isNotEmpty) {
        request.files.add(
            await http.MultipartFile.fromPath('recipe_photo', recipePhotoPath));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) return null;
      final resp = jsonDecode(response.body);
      return resp['message'] ?? 'Failed to create recipe';
    } catch (e) {
      if (!allowFallback) rethrow;

      final localId = DateTime.now().millisecondsSinceEpoch;
      int userId = 0;
      try {
        final user = await getUser();
        userId = user['id'];
      } catch (_) {}

      await DatabaseHelper().saveLocalRecipe({
        'id': localId,
        'user_id': userId,
        'name': data['name'],
        'brand_name': data['brand_name'],
        'section_name': data['section_name'],
        'ingredients': data['ingredients'],
        'process': data['process'],
        'visibility': data['visibility'],
        'item_photo': itemPhotoPath,
        'created_at': DateTime.now().toIso8601String(),
        'is_pending': 1,
      });

      await DatabaseHelper().addPendingSync({
        'action': 'CREATE_RECIPE',
        'data': jsonEncode(data),
        'item_photo_path': itemPhotoPath,
        'recipe_photo_path': recipePhotoPath,
        'target_id': localId,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<String?> updateRecipe(int id, Map<String, dynamic> data,
      {String? itemPhotoPath,
      String? recipePhotoPath,
      bool allowFallback = true}) async {
    itemPhotoPath = await _saveFilePermanently(itemPhotoPath);
    recipePhotoPath = await _saveFilePermanently(recipePhotoPath);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/recipes/$id'));
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      data.forEach((key, value) {
        request.fields[key] = value.toString();
      });

      if (itemPhotoPath != null && itemPhotoPath.isNotEmpty) {
        request.files.add(
            await http.MultipartFile.fromPath('item_photo', itemPhotoPath));
      }
      if (recipePhotoPath != null && recipePhotoPath.isNotEmpty) {
        request.files.add(
            await http.MultipartFile.fromPath('recipe_photo', recipePhotoPath));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) return null;
      final resp = jsonDecode(response.body);
      return resp['message'] ?? 'Failed to update recipe';
    } catch (e) {
      if (!allowFallback) rethrow;

      await DatabaseHelper().addPendingSync({
        'action': 'UPDATE_RECIPE',
        'target_id': id,
        'data': jsonEncode(data),
        'item_photo_path': itemPhotoPath,
        'recipe_photo_path': recipePhotoPath,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<String?> deleteRecipe(int id, {bool permanent = false}) async {
    if (!permanent) {
      await DatabaseHelper().softDeleteLocalRecipe(id);
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.delete(
        Uri.parse('$baseUrl/recipes/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        await DatabaseHelper().deleteLocalRecipe(id);
        return null;
      } else {
        return 'Failed to delete';
      }
    } catch (e) {
      await DatabaseHelper().addPendingSync({
        'action': 'DELETE_RECIPE',
        'target_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
      await DatabaseHelper().deleteLocalRecipe(id);
      return null;
    }
  }

  Future<void> restoreRecipe(int id) async {
    await DatabaseHelper().restoreLocalRecipe(id);
  }

  static bool _syncing = false;

  /// Sends queued offline changes. Only one run at a time, so the same
  /// change is never sent twice.
  Future<void> syncPendingActions() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _syncPendingActions();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncPendingActions() async {
    final pending = await DatabaseHelper().getPendingSyncs();
    if (pending.isEmpty) return;
    final touchesIngredients = pending.any((p) => p['action'].toString().contains('INGREDIENT'));

    for (var item in pending) {
      final action = item['action'];
      final data = jsonDecode(item['data'] ?? '{}');
      final targetId = item['target_id'] as int;

      try {
        String? error;
        if (action == 'CREATE_RECIPE') {
          error = await createRecipe(data,
              itemPhotoPath: item['item_photo_path'],
              recipePhotoPath: item['recipe_photo_path'],
              allowFallback: false);
        } else if (action == 'UPDATE_RECIPE') {
          error = await updateRecipe(targetId, data,
              itemPhotoPath: item['item_photo_path'],
              recipePhotoPath: item['recipe_photo_path'],
              allowFallback: false);
        } else if (action == 'DELETE_RECIPE') {
          error = await _syncDeleteRecipe(targetId);
        } else if (action == 'CREATE_INGREDIENT') {
          error = await createIngredient(data, allowFallback: false);
        } else if (action == 'UPDATE_INGREDIENT') {
          error = await updateIngredient(targetId, data, allowFallback: false);
        } else if (action == 'DELETE_INGREDIENT') {
          error = await deleteIngredient(targetId, allowFallback: false);
        } else if (action == 'CREATE_INGREDIENTS') {
          error = await _syncCreateIngredients(data['items'] as List);
        } else if (action == 'MERGE_INGREDIENT') {
          error = await _syncMergeIngredient(data['from_name'], data['into_name']);
        } else if (action == 'CREATE_SECTION') {
          error = await createSection(data['name'], allowFallback: false);
        } else if (action == 'UPDATE_SECTION') {
          error = await updateSection(targetId, data['name'], allowFallback: false);
        } else if (action == 'DELETE_SECTION') {
          error = await deleteSection(targetId, allowFallback: false);
        }

        if (error == null) {
          await DatabaseHelper().deletePendingSync(item['id']);
          if (action == 'CREATE_RECIPE' || action == 'CREATE_INGREDIENT' || action == 'CREATE_SECTION') {
            if (action == 'CREATE_RECIPE') await DatabaseHelper().deleteLocalRecipe(targetId);
            if (action == 'CREATE_INGREDIENT') await DatabaseHelper().deleteLocalIngredient(targetId);
            if (action == 'CREATE_SECTION') await DatabaseHelper().deleteLocalSection(targetId);
          }
        }
      } catch (e) {
        debugPrint('Sync Error: $e');
      }
    }
    if (touchesIngredients) await PriceBook.instance.load();
  }

  /// Many new ingredients in one request. The phone's temporary rows are
  /// replaced by the server's rows (real ids).
  Future<String?> _syncCreateIngredients(List items) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await _http.post(
      Uri.parse('$baseUrl/ingredients/bulk'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'items': [
          for (final i in items)
            {
              'name': i['name'],
              'category': i['category'] ?? 'Uncategorized',
              'unit': i['unit'] ?? 'kg',
              if (i['price'] != null) 'price': i['price'],
            }
        ]
      }),
    );
    if (response.statusCode != 201) return 'Failed to add ingredients';
    final saved = jsonDecode(response.body) as List;
    final db = DatabaseHelper();
    for (final i in items) {
      await db.deleteLocalIngredient(i['id'] as int);
    }
    await db.cacheIngredients(saved);
    return null;
  }

  /// One request: the server switches every recipe from one name to the other.
  Future<String?> _syncMergeIngredient(String from, String into) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await _http.post(
      Uri.parse('$baseUrl/ingredients/merge'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'from_name': from, 'into_name': into}),
    );
    // 422 = same name after all; nothing to do, drop it from the queue
    if (response.statusCode == 200 || response.statusCode == 422) return null;
    return 'Failed to merge ingredients';
  }

  Future<String?> _syncDeleteRecipe(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.delete(
        Uri.parse('$baseUrl/recipes/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) return null;
      return 'Error';
    } catch (e) {
      debugPrint('Sync Delete Error: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      return await DatabaseHelper().getCachedIngredients();
    }

    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/ingredients'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        List<dynamic> ingredients;
        if (json is Map && json.containsKey('data')) {
          ingredients = json['data'];
        } else {
          ingredients = json as List<dynamic>;
        }
        await DatabaseHelper().replaceIngredients(ingredients);
        return await DatabaseHelper().getCachedIngredients();
      } else {
        throw Exception('Failed to load ingredients');
      }
    } catch (e) {
      final local = await DatabaseHelper().getCachedIngredients();
      return local;
    }
  }

  Future<String?> createIngredient(Map<String, dynamic> data,
      {bool allowFallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/ingredients'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 201) {
        final resp = jsonDecode(response.body);
        await DatabaseHelper().saveLocalIngredient(resp);
        return null;
      } else {
        final resp = jsonDecode(response.body);
        return resp['message'] ?? 'Failed to create ingredient';
      }
    } catch (e) {
      if (!allowFallback) rethrow;

      final localId = DateTime.now().millisecondsSinceEpoch;
      final localData = Map<String, dynamic>.from(data);
      localData['id'] = localId; // Temporary ID
      await DatabaseHelper().saveLocalIngredient(localData);

      await DatabaseHelper().addPendingSync({
        'action': 'CREATE_INGREDIENT',
        'data': jsonEncode(data),
        'target_id': localId,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null; // Return null so the UI thinks it succeeded (offline mode)
    }
  }

  Future<String?> updateIngredient(int id, Map<String, dynamic> data,
      {bool allowFallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.put(
        Uri.parse('$baseUrl/ingredients/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        final resp = jsonDecode(response.body);
        await DatabaseHelper().saveLocalIngredient(resp);
        return null;
      } else {
        final resp = jsonDecode(response.body);
        return resp['message'] ?? 'Failed to update ingredient';
      }
    } catch (e) {
      if (!allowFallback) rethrow;

      await DatabaseHelper().updateLocalIngredient(id, data);
      await DatabaseHelper().addPendingSync({
        'action': 'UPDATE_INGREDIENT',
        'target_id': id,
        'data': jsonEncode(data),
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<String?> deleteIngredient(int id, {bool allowFallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.delete(
        Uri.parse('$baseUrl/ingredients/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        await DatabaseHelper().deleteLocalIngredient(id);
        return null;
      } else {
        return 'Failed to delete ingredient';
      }
    } catch (e) {
      if (!allowFallback) rethrow;

      await DatabaseHelper().deleteLocalIngredient(id);
      await DatabaseHelper().addPendingSync({
        'action': 'DELETE_INGREDIENT',
        'target_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<List<dynamic>> getSections() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      final cached = await DatabaseHelper().getCachedData('recipe_sections');
      if (cached != null) return cached as List<dynamic>;
      return [];
    }

    try {
      final response = await _http.get(
        Uri.parse('$baseUrl/recipe-sections'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final sections = jsonDecode(response.body);
        await DatabaseHelper().cacheData('recipe_sections', sections);
        return sections;
      } else {
        throw Exception('Failed to load sections');
      }
    } catch (e) {
      final cached = await DatabaseHelper().getCachedData('recipe_sections');
      if (cached != null) return cached as List<dynamic>;
      return [];
    }
  }

  Future<String?> createSection(String name, {bool allowFallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/recipe-sections'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 201) {
        final resp = jsonDecode(response.body);
        await DatabaseHelper().saveLocalSection({
          'server_id': resp['id'],
          'name': resp['name'],
          'created_at': resp['created_at'],
        });
        return null;
      }
      return 'Failed to create section';
    } catch (e) {
      if (!allowFallback) rethrow;

      final localId = DateTime.now().millisecondsSinceEpoch;
      await DatabaseHelper().saveLocalSection({
        'name': name,
        'created_at': DateTime.now().toIso8601String(),
        'sort_order': 99,
      });
      await DatabaseHelper().addPendingSync({
        'action': 'CREATE_SECTION',
        'data': jsonEncode({'name': name}),
        'target_id': localId,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<String?> deleteSection(int id, {bool allowFallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.delete(
        Uri.parse('$baseUrl/recipe-sections/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        await DatabaseHelper().deleteLocalSection(id);
        return null;
      }
      return 'Failed to delete section';
    } catch (e) {
      if (!allowFallback) rethrow;

      await DatabaseHelper().deleteLocalSection(id);
      await DatabaseHelper().addPendingSync({
        'action': 'DELETE_SECTION',
        'target_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<String?> updateSection(int id, String name,
      {bool allowFallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.put(
        Uri.parse('$baseUrl/recipe-sections/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 200) {
        await DatabaseHelper().updateLocalSection(id, name);
        return null;
      }
      return 'Failed to update section';
    } catch (e) {
      if (!allowFallback) rethrow;

      await DatabaseHelper().updateLocalSection(id, name);
      await DatabaseHelper().addPendingSync({
        'action': 'UPDATE_SECTION',
        'target_id': id,
        'data': jsonEncode({'name': name}),
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    }
  }

  Future<String?> updateProfile(Map<String, dynamic> data,
      {String? avatarPath}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/user/profile'));
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      data.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });
      if (avatarPath != null) {
        request.files
            .add(await http.MultipartFile.fromPath('avatar', avatarPath));
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        return null;
      } else {
        final resp = jsonDecode(response.body);
        return resp['message'] ?? 'Failed to update profile';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> shareRecipeAccess(int id, String usernames) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/recipes/$id/share'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'usernames': usernames}),
      );
      final resp = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return resp['message'];
      } else {
        return resp['message'] ?? 'Failed to share recipe';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> removeRecipeAccess(int recipeId, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.delete(
        Uri.parse('$baseUrl/recipes/$recipeId/share/$userId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final resp = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return resp['message'];
      } else {
        return resp['message'] ?? 'Failed to remove access';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Asks the server to delete the account in 30 days. Logs out on all
  /// phones. Returns the deletion date (yyyy-mm-dd) or throws on error.
  Future<String> requestAccountDeletion() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await _http.post(
      Uri.parse('$baseUrl/account/delete'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Could not delete the account (${response.statusCode})');
    }
    final date = (jsonDecode(response.body)['delete_on'] ?? '').toString();
    // the server already ended every session; clear this phone too
    await prefs.remove('token');
    await prefs.remove('deletion_scheduled_for');
    await DatabaseHelper().clearAllData();
    return date;
  }

  /// Cancels a pending account deletion ("Keep my account").
  Future<String?> keepAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await _http.post(
        Uri.parse('$baseUrl/account/keep'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        await prefs.remove('deletion_scheduled_for');
        return null;
      }
      return 'Could not keep the account (${response.statusCode})';
    } catch (e) {
      return 'No connection. Try again when you’re online.';
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      try {
        await _http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );
      } catch (e) {
        debugPrint('Logout Error: $e');
      }
    }
    await prefs.remove('token');
    await prefs.remove('deletion_scheduled_for');
    await DatabaseHelper().clearAllData();
  }

  Future<String?> _saveFilePermanently(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return path;

      // Check if already in documents
      final docsDir = await getApplicationDocumentsDirectory();
      if (path.contains(docsDir.path)) return path;

      final mediaDir = Directory(join(docsDir.path, 'media'));
      if (!await mediaDir.exists()) await mediaDir.create(recursive: true);

      final fileName = basename(path);
      final newPath = join(mediaDir.path, fileName);
      final newFile = await file.copy(newPath);
      return newFile.path;
    } catch (e) {
      debugPrint('Error saving file permanently: $e');
      return path;
    }
  }

  /// Sends a recipe photo (handwritten or printed) to `/recipes-analyze`
  /// and returns extracted `{name, brand_name, section_name, ingredients, process}`.
  Future<Map<String, dynamic>> analyzeRecipeImage(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      throw Exception('Please sign in to scan recipes from a photo.');
    }

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/recipes-analyze'),
    );
    req.headers['Accept'] = 'application/json';
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('image', imagePath));

    final streamed = await req.send().timeout(const Duration(seconds: 40));
    final body = await streamed.stream.bytesToString();
    final decoded = jsonDecode(body);

    if (streamed.statusCode == 200 && decoded is Map<String, dynamic>) {
      return decoded;
    }
    final msg = (decoded is Map && decoded['message'] != null)
        ? decoded['message'].toString()
        : 'Could not read recipe photo (HTTP ${streamed.statusCode}).';
    throw Exception(msg);
  }

  Future<String?> fetchAllDataForOffline() async {
    try {
      // 1. Fetch the main lists
      final recipesList = await getRecipes();
      await getIngredients();
      await getSections();
      await getUser();

      // 2. Fetch full details for each recipe to ensure ingredients/process are cached
      for (var r in recipesList) {
        if (r['id'] != null) {
          final fullRecipe = await getRecipe(r['id']);
          await DatabaseHelper().saveLocalRecipe(fullRecipe);
        }
      }
      
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
