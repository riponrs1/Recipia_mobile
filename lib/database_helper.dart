import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'recipia_offline.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'CREATE TABLE IF NOT EXISTS ingredients(id INTEGER PRIMARY KEY, name TEXT, brand TEXT, category TEXT, price REAL, unit TEXT, calories REAL)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS app_cache(key TEXT PRIMARY KEY, value TEXT)');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_sync(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              action TEXT,
              target_id INTEGER,
              data TEXT,
              item_photo_path TEXT,
              recipe_photo_path TEXT,
              created_at TEXT
            )
          ''');
          try {
            await db.execute(
                'ALTER TABLE recipes ADD COLUMN is_pending INTEGER DEFAULT 0');
          } catch (e) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE recipes ADD COLUMN deleted_at TEXT');
          } catch (e) {}
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS recipe_sections(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE,
              is_system INTEGER DEFAULT 0,
              icon TEXT,
              created_at TEXT
            )
          ''');
          _seedDefaultSections(db);
        }
        if (oldVersion < 6) {
          try {
            await db.execute(
                'ALTER TABLE recipe_sections ADD COLUMN server_id INTEGER');
            // Optionally unlock existing defaults if requested
            await db.update('recipe_sections', {'is_system': 0},
                where: 'is_system = 1 AND server_id IS NULL');
          } catch (e) {}
        }
        if (oldVersion < 7) {
          try {
            await db.execute(
                'ALTER TABLE recipe_sections ADD COLUMN sort_order INTEGER DEFAULT 0');
          } catch (e) {}
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE recipes(
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        name TEXT,
        brand_name TEXT,
        section_name TEXT,
        ingredients TEXT,
        process TEXT,
        visibility TEXT,
        item_photo TEXT,
        created_at TEXT,
        deleted_at TEXT,
        is_pending INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE ingredients(
        id INTEGER PRIMARY KEY,
        name TEXT,
        brand TEXT,
        category TEXT,
        price REAL,
        unit TEXT,
        calories REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_cache(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE recipe_sections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT UNIQUE,
        is_system INTEGER DEFAULT 0,
        icon TEXT,
        sort_order INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');
    await _seedDefaultSections(db);
  }

  Future<void> _seedDefaultSections(Database db) async {
    final sections = [
      'Hot Kitchen',
      'Bakery',
      'Pastry',
      'Sweet',
      'Sauce',
      'Cold/Salad',
      'Pizza',
      'Breakfast',
      'Appetizers',
      'Main Course',
      'Desserts',
      'Beverages',
      'Seafood',
      'Soup',
      'Sides',
      'Vegetarian',
      'Vegan'
    ];
    for (var name in sections) {
      await db.insert(
          'recipe_sections',
          {
            'name': name,
            'is_system': 0, // Defaults are editable until locked by server
            'icon': 'category',
            'sort_order': sections.indexOf(name),
            'created_at': DateTime.now().toIso8601String()
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> cacheRecipes(List<dynamic> recipes) async {
    final db = await database;
    final batch = db.batch();

    for (var recipe in recipes) {
      batch.insert(
        'recipes',
        {
          'id': recipe['id'],
          'user_id': recipe['user_id'],
          'name': recipe['name'],
          'brand_name': recipe['brand_name'],
          'section_name': recipe['section_name'],
          'ingredients': (recipe['ingredients'] is String)
              ? recipe['ingredients']
              : jsonEncode(recipe['ingredients']),
          'process': recipe['process'] ?? '',
          'visibility': recipe['visibility'] ?? 'private',
          'item_photo': recipe['item_photo'],
          'created_at': recipe['created_at'],
          'is_pending': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> saveLocalRecipe(Map<String, dynamic> recipe) async {
    final db = await database;
    await db.insert('recipes', recipe,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getCachedRecipes() async {
    final db = await database;
    // Show non-deleted items, pending at the top
    return await db.query('recipes',
        where: 'deleted_at IS NULL',
        orderBy: 'is_pending DESC, created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getTrashRecipes() async {
    final db = await database;
    return await db.query('recipes',
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
  }

  Future<void> softDeleteLocalRecipe(int id) async {
    final db = await database;
    await db.update('recipes', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restoreLocalRecipe(int id) async {
    final db = await database;
    await db.update('recipes', {'deleted_at': null},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addPendingSync(Map<String, dynamic> syncData) async {
    final db = await database;
    return await db.insert('pending_sync', syncData);
  }

  Future<List<Map<String, dynamic>>> getPendingSyncs() async {
    final db = await database;
    return await db.query('pending_sync', orderBy: 'created_at ASC');
  }

  Future<void> deletePendingSync(int id) async {
    final db = await database;
    await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteLocalRecipe(int id) async {
    final db = await database;
    await db.delete('recipes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cacheIngredients(List<dynamic> ingredients) async {
    final db = await database;
    final batch = db.batch();

    for (var ingredient in ingredients) {
      batch.insert(
        'ingredients',
        {
          'id': ingredient['id'],
          'name': ingredient['name'],
          'brand': ingredient['brand'],
          'category': ingredient['category'] ?? 'Uncategorized',
          'price': _toDouble(ingredient['price']),
          'unit': ingredient['unit'],
          'calories': _toDouble(ingredient['calories']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<List<Map<String, dynamic>>> getCachedIngredients() async {
    final db = await database;
    return await db.query('ingredients', orderBy: 'name ASC');
  }

  Future<void> cacheData(String key, dynamic data) async {
    final db = await database;
    await db.insert(
      'app_cache',
      {'key': key, 'value': jsonEncode(data)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getCachedData(String key) async {
    final db = await database;
    final maps =
        await db.query('app_cache', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) {
      try {
        return jsonDecode(maps.first['value'] as String);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Recipe Section Local CRUD
  Future<List<Map<String, dynamic>>> getLocalSections() async {
    final db = await database;
    return await db.query('recipe_sections',
        orderBy: 'sort_order ASC, is_system DESC, name ASC');
  }

  Future<void> updateSectionOrder(int id, int newOrder) async {
    final db = await database;
    await db.update('recipe_sections', {'sort_order': newOrder},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> saveLocalSection(Map<String, dynamic> section) async {
    final db = await database;
    return await db.insert('recipe_sections', section,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateLocalSection(int id, String name) async {
    final db = await database;
    return await db.update('recipe_sections', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteLocalSection(int id) async {
    final db = await database;
    return await db.delete('recipe_sections',
        where: 'id = ? AND is_system = 0', whereArgs: [id]);
  }

  Future<List<String>> getUniqueBrands() async {
    final db = await database;
    final res = await db.rawQuery(
        'SELECT DISTINCT brand_name FROM recipes WHERE brand_name IS NOT NULL AND brand_name != "" ORDER BY brand_name ASC');
    return res.map((r) => r['brand_name'] as String).toList();
  }
}
