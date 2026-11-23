import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../sync_provider.dart';
import '../database_helper.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'backup_sync_screen.dart';
import 'recipe_sections_screen.dart';
import 'trash_screen.dart';
import 'settings_screen.dart';
import '../tab_events.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ApiService();
  Map<String, dynamic>? _userData;
  Map<String, dynamic> _stats = {
    'recipeCount': 0,
    'pantryValue': 0.0,
    'sectionCount': 0,
  };
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // show the profile saved on this phone first, then refresh from the server
    final cached = await DatabaseHelper().getCachedData('user_profile');
    if (cached is Map && mounted) {
      final user = Map<String, dynamic>.from(cached);
      final stats = await DatabaseHelper()
          .getProfileStats(currentUserId: user['id'] as int?);
      if (mounted) {
        setState(() {
          _userData = user;
          _stats = stats;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }
    try {
      final user = await _apiService.getUser();
      final stats = await DatabaseHelper().getProfileStats(currentUserId: user['id'] as int?);
      if (mounted) {
        setState(() {
          _userData = user;
          _stats = stats;
        });
      }
    } catch (e) {
      debugPrint('Data load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = Provider.of<SyncProvider>(context);
    final name = _userData?['name'] ?? syncProvider.userName ?? "Chef";
    final email =
        _userData?['email'] ?? syncProvider.userEmail ?? "my kitchen";
    final avatarUrl = _userData?['profile']?['avatar'];

    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : SafeArea(
              bottom: false,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                children: [
                  const Text('Profile',
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: _fg)),
                  const SizedBox(height: 18),
                  _header(name, email, avatarUrl, syncProvider),
                  const SizedBox(height: 22),
                  _statsRow(),
                  const SizedBox(height: 20),
                  _menu([
                    _menuItem(Icons.edit_outlined, 'Edit profile', () async {
                      if (_userData != null) {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    EditProfileScreen(userData: _userData!)));
                        _loadData();
                      }
                    }),
                    _menuItem(Icons.dashboard_customize_outlined,
                        'Manage sections', () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const RecipeSectionsScreen()))),
                    _menuItem(Icons.cloud_sync_outlined, 'Backup & sync',
                        () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const BackupSyncScreen()))),
                    _menuItem(Icons.delete_outline_rounded, 'Trash',
                        () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const TrashScreen()))),
                    _menuItem(Icons.settings_outlined, 'Settings',
                        () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      if (mounted) setState(() {});
                    }),
                    _menuItem(Icons.ios_share_rounded, 'Export data',
                        () => _exportDatabase(context)),
                    _menuItem(Icons.logout_rounded, 'Log out',
                        () => _handleLogout(context, syncProvider),
                        destructive: true),
                  ]),
                  const SizedBox(height: 24),
                  Center(
                    child: Text('Recipia · v2.0',
                        style: TextStyle(
                            color: _muted.withOpacity(0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(String name, String email, String? avatarUrl,
      SyncProvider syncProvider) {
    final photoUrl = avatarUrl != null
        ? ApiService.getImageUrl(avatarUrl)
        : syncProvider.userPhoto;
    // The initial is always drawn; the photo sits on top and simply
    // disappears if it cannot load (offline, deleted file).
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 92,
            height: 92,
            color: _accent,
            alignment: Alignment.center,
            child: Stack(fit: StackFit.expand, children: [
              Center(
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontFamily: 'SpaceGrotesk',
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              if (photoUrl != null)
                CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  placeholder: (_, __) => const SizedBox.shrink(),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Text(name,
            style: const TextStyle(fontFamily: 'SpaceGrotesk',
                fontSize: 22, fontWeight: FontWeight.w800, color: _fg)),
        const SizedBox(height: 2),
        Text(email, style: const TextStyle(fontSize: 14, color: _muted)),
        const SizedBox(height: 10),
        _jobTitleChip(),
      ],
    );
  }

  /// The job title from the profile; empty → a small button to add one.
  Widget _jobTitleChip() {
    final title = (_userData?['profile']?['job_title'] ?? '').toString().trim();
    if (title.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: _accentSoft, borderRadius: BorderRadius.circular(999)),
        child: Text(title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _accent)),
      );
    }
    return GestureDetector(
      onTap: _openEditProfile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _accent.withOpacity(0.4))),
        child: const Text('+ Add job title',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _accent)),
      ),
    );
  }

  Future<void> _openEditProfile() async {
    if (_userData == null) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => EditProfileScreen(userData: _userData!)));
    _loadData();
  }

  Widget _statsRow() {
    return Row(
      children: [
        _statCard(_stats['recipeCount'].toString(), 'recipes',
            () => tabRequest.value = 0),
        const SizedBox(width: 10),
        _statCard(_stats['sectionCount'].toString(), 'sections', () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RecipeSectionsScreen()));
          _loadData();
        }),
        const SizedBox(width: 10),
        _statCard('${_stats['ingredientCount'] ?? 0}', 'ingredients',
            () => tabRequest.value = 1),
      ],
    );
  }

  Widget _statCard(String value, String label, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        button: true,
        label: '$value $label',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(fontFamily: 'SpaceGrotesk',
                    fontSize: 20, fontWeight: FontWeight.w700, color: _fg)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      ),
          ),
        ),
      ),
    );
  }

  Widget _menu(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap,
      {bool destructive = false, String? trailing}) {
    final c = destructive ? const Color(0xFFC0392B) : _fg;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line))),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _surface2, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon,
                  size: 19, color: destructive ? c : _accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: c)),
            ),
            if (trailing != null)
              Text(trailing,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _muted)),
            if (!destructive)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: _muted),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportDatabase(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text("DATA BACKUP", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFFC84B31))),
            const SizedBox(height: 32),
            _buildExportOption(Icons.ios_share_rounded, 'SHARE COLLECTION', 'Export as a .db file', const Color(0xFFC84B31), () {
              Navigator.pop(ctx);
              _shareDatabase(context);
            }),
            const SizedBox(height: 16),
            _buildExportOption(Icons.save_as_rounded, 'SAVE TO PHONE', 'Save recipes to your device', const Color(0xFFE1B12C), () {
              Navigator.pop(ctx);
              _saveDatabaseToDevice(context);
            }),
            const SizedBox(height: 16),
            _buildExportOption(Icons.unarchive_rounded, 'RESTORE BACKUP', 'Import your saved .db file', const Color(0xFFB2BEC3), () {
              Navigator.pop(ctx);
              _importDatabaseFromFile(context);
            }),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(IconData icon, String label, String sub, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFBF7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: Color(0xFFC84B31))),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: Color(0xFFB2BEC3), fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDatabase(BuildContext context) async {
    try {
      setState(() => _isLoading = true);
      await DatabaseHelper().closeDatabase();
      final dbDir = await getDatabasesPath();
      final dbPath = p.join(dbDir, 'recipia_offline.db');
      await Share.shareXFiles([XFile(dbPath)], text: 'Recipia Recipe Collection Export');
    } catch (e) {
      debugPrint('Share failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDatabaseToDevice(BuildContext context) async {
    try {
      setState(() => _isLoading = true);
      await DatabaseHelper().closeDatabase();
      final dbDir = await getDatabasesPath();
      final dbPath = p.join(dbDir, 'recipia_offline.db');
      final dbFile = File(dbPath);
      final fileName = 'Recipia_Backup_${DateTime.now().millisecondsSinceEpoch}.db';
      await FilePicker.saveFile(dialogTitle: 'Save Recipes', fileName: fileName, bytes: await dbFile.readAsBytes());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup saved successfully!'), backgroundColor: Color(0xFFC84B31)));
    } catch (e) {
      debugPrint('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importDatabaseFromFile(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty || files.first.path == null) return;
      final filePath = files.first.path!;
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("IMPORT RECIPES?", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
          content: const Text("This will permanently replace your current recipes with the imported file.", style: TextStyle(fontSize: 13, color: Color(0xFF6D625B))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL", style: TextStyle(color: Color(0xFFB2BEC3), fontWeight: FontWeight.w900))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("PROCEED", style: TextStyle(color: Color(0xFFE1B12C), fontWeight: FontWeight.w900))),
          ],
        ),
      );

      if (confirm == true) {
        if (!mounted) return;
        setState(() => _isLoading = true);
        await DatabaseHelper().importDatabase(filePath);
        if (mounted) {
          // Refresh local providers
          final syncProvider = Provider.of<SyncProvider>(context, listen: false);
          await syncProvider.refreshAfterRestore();
          
          setState(() {}); 
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recipes restored successfully!'), backgroundColor: Color(0xFFC84B31)));
        }
      }
    } catch (e) {
      debugPrint('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout(BuildContext context, SyncProvider syncProvider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('LOGOUT?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
        content: const Text('Are you sure you want to terminate your current session?', style: TextStyle(fontSize: 13, color: Color(0xFF6D625B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: Color(0xFFB2BEC3), fontWeight: FontWeight.w900))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LOGOUT', style: TextStyle(color: Color(0xFFC84B31), fontWeight: FontWeight.w900))),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      await _apiService.logout();
      await syncProvider.signOut();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    }
  }
}
