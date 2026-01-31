import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_service.dart';
import 'database_helper.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncProvider with ChangeNotifier {
  final GoogleDriveService _driveService = GoogleDriveService();

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isGoogleSignedIn = false;
  bool get isGoogleSignedIn => _isGoogleSignedIn;

  String? _cachedEmail;
  String? _cachedName;
  String? _cachedPhoto;

  String? get userEmail => _driveService.currentUser?.email ?? _cachedEmail;
  String? get userName => _driveService.currentUser?.displayName ?? _cachedName;
  String? get userPhoto => _driveService.currentUser?.photoUrl ?? _cachedPhoto;

  bool _isAutoBackupEnabled = false;
  bool get isAutoBackupEnabled => _isAutoBackupEnabled;

  Map<String, dynamic>? _cloudMetadata;
  Map<String, dynamic>? get cloudMetadata => _cloudMetadata;

  int _localDatabaseSize = 0;
  int get localDatabaseSize => _localDatabaseSize;

  int _localPhotoCount = 0;
  int get localPhotoCount => _localPhotoCount;

  SyncProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _isAutoBackupEnabled = prefs.getBool('auto_backup_enabled') ?? false;

    // Load cached identity
    _cachedEmail = prefs.getString('user_email');
    _cachedName = prefs.getString('user_name');
    _cachedPhoto = prefs.getString('user_photo');

    _localDatabaseSize = await _driveService.getLocalDatabaseSize();
    _localPhotoCount = await _driveService.getLocalPhotoCount();
    _isGoogleSignedIn = await _driveService.signInSilently();

    if (_isGoogleSignedIn) {
      await _persistIdentity();
      await fetchCloudMetadata();
      if (_isAutoBackupEnabled) {
        backupData(); // Silent background backup
      }
    }
    notifyListeners();
  }

  Future<void> _persistIdentity() async {
    final user = _driveService.currentUser;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      _cachedEmail = user.email;
      _cachedName = user.displayName;
      _cachedPhoto = user.photoUrl;

      await prefs.setString('user_email', _cachedEmail!);
      if (_cachedName != null) {
        await prefs.setString('user_name', _cachedName!);
      }
      if (_cachedPhoto != null) {
        await prefs.setString('user_photo', _cachedPhoto!);
      }
    }
  }

  Future<void> toggleAutoBackup(bool value) async {
    _isAutoBackupEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_backup_enabled', value);
    notifyListeners();
    if (value && _isGoogleSignedIn) {
      backupData();
    }
  }

  Future<bool> detectMissingLocalData() async {
    if (!_isGoogleSignedIn || _cloudMetadata == null) return false;
    final size = await _driveService.getLocalDatabaseSize();
    return size < 50000; // Less than 50KB likely means empty/new install
  }

  Future<void> triggerAutoBackupIfEnabled() async {
    if (_isAutoBackupEnabled && _isGoogleSignedIn) {
      backupData(); // Run in background
    }
  }

  Future<void> signIn() async {
    _status = SyncStatus.syncing;
    notifyListeners();

    final success = await _driveService.signIn();
    if (success) {
      _isGoogleSignedIn = true;
      await _persistIdentity();
      await fetchCloudMetadata();
      _status = SyncStatus.idle;
    } else {
      _isGoogleSignedIn = false;
      _status = SyncStatus.error;
      _errorMessage = 'Failed to sign in to Google';
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _driveService.signOut();
    _isGoogleSignedIn = false;
    _cloudMetadata = null;

    // Clear cached identity
    _cachedEmail = null;
    _cachedName = null;
    _cachedPhoto = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('user_photo');

    notifyListeners();
  }

  Future<void> fetchCloudMetadata() async {
    try {
      _cloudMetadata = await _driveService.getBackupMetadata();
      _localDatabaseSize = await _driveService.getLocalDatabaseSize();
      _localPhotoCount = await _driveService.getLocalPhotoCount();
    } catch (e) {
      print('Cloud metadata fetch error (Drive API might be disabled): $e');
    }
    notifyListeners();
  }

  Future<bool> backupData() async {
    if (!_isGoogleSignedIn) return false;

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      // 1. Close current DB connection to flush WAL/checkpoint
      await DatabaseHelper().closeDatabase();

      await _driveService.backupDatabase();
      await fetchCloudMetadata();
      _status = SyncStatus.success;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'last_backup_time', DateTime.now().toIso8601String());

      notifyListeners();
      return true;
    } catch (e) {
      _status = SyncStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> restoreData() async {
    if (!_isGoogleSignedIn) return false;

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      // 1. Close current DB connection to allow file overwrite
      await DatabaseHelper().closeDatabase();

      final success = await _driveService.restoreDatabase();
      if (success) {
        // 2. Re-fetch local stats (this will also reopen the DB when needed)
        _localDatabaseSize = await _driveService.getLocalDatabaseSize();
        _localPhotoCount = await _driveService.getLocalPhotoCount();
        _status = SyncStatus.success;
        notifyListeners();
        return true;
      } else {
        _status = SyncStatus.error;
        _errorMessage = 'No backup found on Google Drive';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = SyncStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<String?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_backup_time');
  }

  Future<void> restoreRecipe(int id) async {
    await DatabaseHelper().restoreLocalRecipe(id);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getTrashRecipes() async {
    return await DatabaseHelper().getTrashRecipes();
  }
}
