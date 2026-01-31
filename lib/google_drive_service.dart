import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveAppdataScope,
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
    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) return null;
      return drive.DriveApi(client);
    } catch (e) {
      print('Error getting Drive API client: $e');
      return null;
    }
  }

  Future<int> backupDatabase() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return 0;

    final dbPath = p.join(await getDatabasesPath(), 'recipia_offline.db');
    final dbFile = File(dbPath);

    final docsDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(docsDir.path, 'media'));

    // Create a temporary zip file
    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(tempDir.path, 'recipia_backup.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    // Add Database
    if (await dbFile.exists()) {
      encoder.addFile(dbFile, 'recipia_offline.db');
    }

    // Add Media (Photos)
    int photoCount = 0;
    if (await mediaDir.exists()) {
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: docsDir.path);
          // relativePath will be "media/filename.jpg"
          encoder.addFile(entity, relativePath);
          photoCount++;
        }
      }
    }
    print('Backing up $photoCount photos and database...');

    encoder.close();

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) return 0;

    final media = drive.Media(zipFile.openRead(), await zipFile.length());
    drive.File driveFile = drive.File();
    driveFile.name = 'recipia_backup.zip';

    // Search for any existing backup files to clean up
    const query =
        "(name = 'recipia_backup.db' or name = 'recipia_backup.zip') and 'appDataFolder' in parents";
    final fileList =
        await driveApi.files.list(q: query, spaces: 'appDataFolder');

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      // Keep only the first one to update, delete others if pollution exists
      final existingFileId = fileList.files!.first.id!;
      await driveApi.files
          .update(driveFile, existingFileId, uploadMedia: media);

      // Delete redundant files if more than one exists
      if (fileList.files!.length > 1) {
        for (var i = 1; i < fileList.files!.length; i++) {
          try {
            await driveApi.files.delete(fileList.files![i].id!);
          } catch (e) {}
        }
      }
    } else {
      driveFile.parents = ['appDataFolder'];
      await driveApi.files.create(driveFile, uploadMedia: media);
    }

    final len = await zipFile.length();
    // Clean up temp zip
    await zipFile.delete();
    return len;
  }

  Future<bool> restoreDatabase() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    const query =
        "(name = 'recipia_backup.zip' or name = 'recipia_backup.db') and 'appDataFolder' in parents";
    final fileList = await driveApi.files.list(
      q: query,
      spaces: 'appDataFolder',
      orderBy: 'modifiedTime desc', // Get latest first
    );

    if (fileList.files == null || fileList.files!.isEmpty) return false;

    // Pick the most recent one
    final driveFile = fileList.files!.first;
    final driveFileId = driveFile.id!;
    final driveFileName = driveFile.name!;

    final media = await driveApi.files.get(driveFileId,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

    final tempDir = await getTemporaryDirectory();
    final downloadPath = p.join(tempDir.path, driveFileName);
    final downloadFile = File(downloadPath);

    final List<int> bytes = [];
    await for (final data in media.stream) {
      bytes.addAll(data);
    }

    if (bytes.isEmpty) return false;
    await downloadFile.writeAsBytes(bytes);

    if (driveFileName.endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPathDir = await getDatabasesPath();

      // Clear existing media folder for a clean restore
      final mediaDir = Directory(p.join(docsDir.path, 'media'));
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }

      bool dbFound = false;
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          if (filename == 'recipia_offline.db' ||
              filename.endsWith('/recipia_offline.db')) {
            await File(p.join(dbPathDir, 'recipia_offline.db'))
                .writeAsBytes(data);
            dbFound = true;
          } else if (filename.startsWith('media/')) {
            // Extract media files
            final outPath = p.join(docsDir.path, filename);
            final outFile = File(outPath);
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(data);
          }
        }
      }
      if (!dbFound) return false;
    } else {
      // Legacy .db support
      final dbPath = p.join(await getDatabasesPath(), 'recipia_offline.db');
      await File(dbPath).writeAsBytes(bytes);
    }

    await downloadFile.delete();
    return true;
  }

  Future<Map<String, dynamic>?> getBackupMetadata() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    const query =
        "(name = 'recipia_backup.zip' or name = 'recipia_backup.db') and 'appDataFolder' in parents";
    final fileList = await driveApi.files.list(
        q: query,
        spaces: 'appDataFolder',
        orderBy: 'modifiedTime desc',
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

  Future<int> getLocalDatabaseSize() async {
    try {
      int totalSize = 0;

      // Database size
      final dbPath = p.join(await getDatabasesPath(), 'recipia_offline.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        totalSize += await dbFile.length();
      }

      // Media folder size
      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(docsDir.path, 'media'));
      if (await mediaDir.exists()) {
        await for (final entity in mediaDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getLocalPhotoCount() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(docsDir.path, 'media'));
      if (!await mediaDir.exists()) return 0;

      int count = 0;
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) count++;
      }
      return count;
    } catch (e) {
      return 0;
    }
  }
}
