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

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'recipia_offline.db');

    return await openDatabase(
      path,
      version: 3,
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
          // Add a column to recipes to track pending status
          try {
            await db.execute(
                'ALTER TABLE recipes ADD COLUMN is_pending INTEGER DEFAULT 0');
          } catch (e) {
            // Column might already exist in some cases
          }
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
      CREATE TABLE pending_sync(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,
        target_id INTEGER,
        data TEXT,
        item_photo_path TEXT,
        recipe_photo_path TEXT,
        created_at TEXT
      )
    ''');
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
    // Show pending items at the top
    return await db.query('recipes',
        orderBy: 'is_pending DESC, created_at DESC');
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
}
