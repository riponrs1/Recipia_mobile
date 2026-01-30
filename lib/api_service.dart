import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

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
    if (path.startsWith('http')) return path;
    // Local file path check
    if (path.startsWith('/') ||
        path.startsWith('file://') ||
        path.contains('com.ripon.recipia') ||
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
      final response = await http.post(
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
        return null;
      } else {
        final data = jsonDecode(response.body);
        return data['message'] ?? 'Login failed';
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/password/email'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['message'];
      } else {
        final data = jsonDecode(response.body);
        return data['message'] ?? 'Failed to send reset link';
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  Future<String?> register(String name, String email, String password,
      String passwordConfirmation) async {
    try {
      final response = await http.post(
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
      final response = await http.get(
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
      throw Exception('Connection error: $e');
    }
  }

  Future<Map<String, dynamic>> getHomeStats() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.get(
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
      throw Exception('Connection error: $e');
    }
  }

  Future<List<dynamic>> getRecipes() async {
    syncPendingActions();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/recipes'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final recipes = jsonDecode(response.body);
        await DatabaseHelper().cacheRecipes(recipes);
        return recipes;
      } else {
        throw Exception('Failed to load recipes');
      }
    } catch (e) {
      final localRecipes = await DatabaseHelper().getCachedRecipes();
      if (localRecipes.isNotEmpty) return localRecipes;
      throw Exception('Connection error: $e');
    }
  }

  Future<List<dynamic>> getMyRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.get(
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
      if (localRecipes.isNotEmpty) return localRecipes;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getRecipe(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/recipes/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load recipe');
      }
    } catch (e) {
      final localRecipes = await DatabaseHelper().getCachedRecipes();
      final recipe =
          localRecipes.firstWhere((r) => r['id'] == id, orElse: () => {});
      if (recipe.isNotEmpty) return recipe;
      throw Exception('Connection error: $e');
    }
  }

  Future<String?> createRecipe(Map<String, dynamic> data,
      {String? itemPhotoPath,
      String? recipePhotoPath,
      bool allowFallback = true}) async {
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
      final user = await getUser();

      await DatabaseHelper().saveLocalRecipe({
        'id': localId,
        'user_id': user['id'],
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

  Future<String?> deleteRecipe(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.delete(
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

  Future<void> syncPendingActions() async {
    final pending = await DatabaseHelper().getPendingSyncs();
    if (pending.isEmpty) return;

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
        }

        if (error == null) {
          await DatabaseHelper().deletePendingSync(item['id']);
          if (action == 'CREATE_RECIPE') {
            await DatabaseHelper().deleteLocalRecipe(targetId);
          }
        }
      } catch (e) {}
    }
  }

  Future<String?> _syncDeleteRecipe(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/recipes/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) return null;
      return 'Error';
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.get(
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
        await DatabaseHelper().cacheIngredients(ingredients);
        return ingredients;
      } else {
        throw Exception('Failed to load ingredients');
      }
    } catch (e) {
      final local = await DatabaseHelper().getCachedIngredients();
      if (local.isNotEmpty) return local;
      throw Exception('Connection error: $e');
    }
  }

  Future<String?> createIngredient(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/ingredients'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 201) {
        return null;
      } else {
        final resp = jsonDecode(response.body);
        return resp['message'] ?? 'Failed to create ingredient';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> updateIngredient(int id, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/ingredients/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        return null;
      } else {
        final resp = jsonDecode(response.body);
        return resp['message'] ?? 'Failed to update ingredient';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> deleteIngredient(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/ingredients/$id'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return null;
      } else {
        return 'Failed to delete ingredient';
      }
    } catch (e) {
      return 'Error: $e';
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
      final response = await http.post(
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
      final response = await http.delete(
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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );
      } catch (e) {}
    }
    await prefs.remove('token');
  }
}
