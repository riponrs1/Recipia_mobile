import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'api_service.dart';
import 'database_helper.dart';

enum SyncStatus { idle, syncing, success, error }

/// Keeps the phone's copy in step with the Recipia account.
/// The account on the server is the backup; there is no Google Drive.
class SyncProvider with ChangeNotifier {
  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  bool _isDownloadingAll = false;
  bool get isDownloadingAll => _isDownloadingAll;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // name/email/photo remembered from the last sign-in, shown while offline
  String? _cachedEmail;
  String? _cachedName;
  String? _cachedPhoto;
  String? get userEmail => _cachedEmail;
  String? get userName => _cachedName;
  String? get userPhoto => _cachedPhoto;

  int _localDatabaseSize = 0;
  int get localDatabaseSize => _localDatabaseSize;

  int _localPhotoCount = 0;
  int get localPhotoCount => _localPhotoCount;

  Map<String, dynamic> _stats = const {};
  Map<String, dynamic> get stats => _stats;

  String? _lastDownload;
  String? get lastDownload => _lastDownload;

  SyncProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedEmail = prefs.getString('user_email');
    _cachedName = prefs.getString('user_name');
    _cachedPhoto = prefs.getString('user_photo');
    _lastDownload = prefs.getString('last_offline_download');
    await refreshAfterRestore();
  }

  /// True on a phone that is signed in but has no recipes yet (new install).
  Future<bool> detectMissingLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString('token') ?? '').isEmpty) return false;
    final s = await DatabaseHelper().getProfileStats();
    return ((s['recipeCount'] as num?) ?? 0) == 0;
  }

  /// Kept for callers from the Drive days; changes go to the account by themselves.
  Future<void> triggerAutoBackupIfEnabled() async {}

  Future<void> signOut() async {
    _cachedEmail = null;
    _cachedName = null;
    _cachedPhoto = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('user_photo');
    await prefs.remove('last_offline_download');
    _lastDownload = null;
    notifyListeners();
  }

  Future<void> restoreRecipe(int id) async {
    await DatabaseHelper().restoreLocalRecipe(id);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getTrashRecipes() async {
    return await DatabaseHelper().getTrashRecipes();
  }

  /// Re-count what is stored on this phone.
  Future<void> refreshAfterRestore() async {
    _localDatabaseSize = await _localSize();
    _localPhotoCount = await _photoCount();
    try {
      _stats = await DatabaseHelper().getProfileStats();
    } catch (_) {}
    notifyListeners();
  }

  /// Download every recipe, ingredient and photo from the account.
  Future<String?> downloadAllFromServer() async {
    _isDownloadingAll = true;
    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      final error = await ApiService().fetchAllDataForOffline();
      if (error == null) {
        _status = SyncStatus.success;
        _lastDownload = DateTime.now().toIso8601String();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_offline_download', _lastDownload!);
      } else {
        _status = SyncStatus.error;
        _errorMessage = error;
      }
      return error;
    } finally {
      _isDownloadingAll = false;
      await refreshAfterRestore();
    }
  }

  Future<Directory> _mediaDir() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'media'));

  Future<int> _localSize() async {
    try {
      var total = 0;
      final db = File(p.join(await getDatabasesPath(), 'recipia_offline.db'));
      if (await db.exists()) total += await db.length();
      final media = await _mediaDir();
      if (await media.exists()) {
        await for (final e in media.list(recursive: true)) {
          if (e is File) total += await e.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _photoCount() async {
    try {
      final media = await _mediaDir();
      if (!await media.exists()) return 0;
      var n = 0;
      await for (final e in media.list(recursive: true)) {
        if (e is File) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}
