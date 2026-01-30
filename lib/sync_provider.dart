import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_service.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncProvider with ChangeNotifier {
  final GoogleDriveService _driveService = GoogleDriveService();

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isGoogleSignedIn = false;
  bool get isGoogleSignedIn => _isGoogleSignedIn;

  String? get userEmail => _driveService.currentUser?.email;
  String? get userName => _driveService.currentUser?.displayName;
  String? get userPhoto => _driveService.currentUser?.photoUrl;

  Map<String, dynamic>? _cloudMetadata;
  Map<String, dynamic>? get cloudMetadata => _cloudMetadata;

  SyncProvider() {
    _init();
  }

  Future<void> _init() async {
    _isGoogleSignedIn = await _driveService.signInSilently();
    if (_isGoogleSignedIn) {
      await fetchCloudMetadata();
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    _status = SyncStatus.syncing;
    notifyListeners();

    final success = await _driveService.signIn();
    if (success) {
      _isGoogleSignedIn = true;
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
    notifyListeners();
  }

  Future<void> fetchCloudMetadata() async {
    _cloudMetadata = await _driveService.getBackupMetadata();
    notifyListeners();
  }

  Future<bool> backupData() async {
    if (!_isGoogleSignedIn) return false;

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
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
      final success = await _driveService.restoreDatabase();
      if (success) {
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
}
