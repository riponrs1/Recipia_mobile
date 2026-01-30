import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveAppdataScope,
      drive.DriveApi.driveFileScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser != null;
    } catch (e) {
      print('Google Sign-In Error: $e');
      return false;
    }
  }

  Future<bool> signInSilently() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      return _currentUser != null;
    } catch (e) {
      print('Google Silent Sign-In Error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  Future<int> backupDatabase() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return 0;

    final dbPath = p.join(await getDatabasesPath(), 'recipes.db');
    final file = File(dbPath);
    if (!await file.exists()) return 0;

    // Search for existing backup file in appDataFolder
    const query = "name = 'recipia_backup.db' and 'appDataFolder' in parents";
    final fileList =
        await driveApi.files.list(q: query, spaces: 'appDataFolder');

    final media = drive.Media(file.openRead(), await file.length());
    drive.File driveFile = drive.File();
    driveFile.name = 'recipia_backup.db';

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      // Update existing
      final existingFileId = fileList.files!.first.id!;
      await driveApi.files
          .update(driveFile, existingFileId, uploadMedia: media);
    } else {
      // Create new
      driveFile.parents = ['appDataFolder'];
      await driveApi.files.create(driveFile, uploadMedia: media);
    }

    return await file.length();
  }

  Future<bool> restoreDatabase() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    const query = "name = 'recipia_backup.db' and 'appDataFolder' in parents";
    final fileList =
        await driveApi.files.list(q: query, spaces: 'appDataFolder');

    if (fileList.files == null || fileList.files!.isEmpty) return false;

    final driveFileId = fileList.files!.first.id!;
    final response = await driveApi.files.get(driveFileId,
        downloadOptions: drive.DownloadOptions.metadata) as drive.File;

    final media = await driveApi.files.get(driveFileId,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

    final dbPath = p.join(await getDatabasesPath(), 'recipes.db');
    final file = File(dbPath);

    final List<int> dataStore = [];
    await for (final data in media.stream) {
      dataStore.addAll(data);
    }
    await file.writeAsBytes(dataStore);

    return true;
  }

  Future<Map<String, dynamic>?> getBackupMetadata() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    const query = "name = 'recipia_backup.db' and 'appDataFolder' in parents";
    final fileList = await driveApi.files.list(
        q: query,
        spaces: 'appDataFolder',
        $fields: 'files(id, name, size, modifiedTime)');

    if (fileList.files == null || fileList.files!.isEmpty) return null;

    final f = fileList.files!.first;
    return {
      'id': f.id,
      'name': f.name,
      'size': f.size,
      'modifiedTime': f.modifiedTime?.toIso8601String(),
    };
  }
}
