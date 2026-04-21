import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
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
    setState(() => _isLoading = true);
    try {
      final user = await _apiService.getUser();
      final stats = await DatabaseHelper().getProfileStats();
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
    final name = _userData?['name'] ?? syncProvider.userName ?? "EXECUTIVE CHEF";
    final email = _userData?['email'] ?? syncProvider.userEmail ?? "VIRTUAL ATELIER";
    final avatarUrl = _userData?['profile']?['avatar'];

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D4037)))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverHeader(name, email, avatarUrl, syncProvider),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        _buildStatsRow(),
                        const SizedBox(height: 40),
                        _buildMenuSection('MANAGEMENT', [
                          _buildMenuItem(Icons.sync_lock_rounded, const Color(0xFF5D4037), 'ARCHIVAL & SYNC', 'Secure your anthology in the cloud', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupSyncScreen()))),
                          _buildMenuItem(Icons.auto_awesome_mosaic_rounded, const Color(0xFFFAB1A0), 'CUISINES & SECTIONS', 'Organize your culinary categories', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeSectionsScreen()))),
                          _buildMenuItem(Icons.auto_delete_rounded, const Color(0xFFFAB1A0), 'RECYCLE BIN', 'Restore archived masterpieces', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashScreen()))),
                        ]),
                        const SizedBox(height: 24),
                        _buildMenuSection('SYSTEM', [
                          _buildMenuItem(Icons.ios_share_rounded, const Color(0xFFB2BEC3), 'EXPORT RECORDS', 'Download secure database backup', () => _exportDatabase(context)),
                          _buildMenuItem(Icons.logout_rounded, const Color(0xFF5D4037), 'EXIT ATELIER', 'Safely sign out of your session', () => _handleLogout(context, syncProvider)),
                        ]),
                        const SizedBox(height: 160),
                        Text('ATELIER CUISINE • v2.0 • GOURMET EDITION', style: TextStyle(color: const Color(0xFF5D4037).withOpacity(0.1), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliverHeader(String name, String email, String? avatarUrl, SyncProvider syncProvider) {
    return SliverAppBar(
      expandedHeight: 340.0,
      pinned: true,
      elevation: 0,
      stretch: true,
      backgroundColor: const Color(0xFF5D4037),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF5D4037)),
            Positioned(
              right: -40,
              top: -40,
              child: Icon(Icons.blur_on_rounded, size: 400, color: Colors.white.withOpacity(0.03)),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFFFAB1A0), shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.white,
                        backgroundImage: avatarUrl != null
                            ? CachedNetworkImageProvider(ApiService.getImageUrl(avatarUrl))
                            : (syncProvider.userPhoto != null ? NetworkImage(syncProvider.userPhoto!) : null) as ImageProvider?,
                        child: (avatarUrl == null && syncProvider.userPhoto == null)
                            ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Color(0xFF5D4037)))
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () async {
                          if (_userData != null) {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(userData: _userData!)));
                            _loadData();
                          }
                        },
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(0xFF5D4037),
                          child: Icon(Icons.camera_enhance_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(email.toLowerCase(), style: const TextStyle(color: Color(0xFFFAB1A0), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard('MASTERPIECES', _stats['recipeCount'].toString(), Icons.history_edu_rounded),
        const SizedBox(width: 12),
        _buildStatCard('CURRENCY', '\$${_stats['pantryValue'].toStringAsFixed(0)}', Icons.payments_outlined),
        const SizedBox(width: 12),
        _buildStatCard('ARCHIVES', _stats['sectionCount'].toString(), Icons.shelves),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFFAB1A0), size: 24),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF5D4037))),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFB2BEC3), letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12),
          child: Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFFAB1A0), letterSpacing: 2)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF5D4037), letterSpacing: 0.5)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFB2BEC3))),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFE2E8F0)),
      onTap: onTap,
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
            const Text("DATA ARCHIVAL", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFF5D4037))),
            const SizedBox(height: 32),
            _buildExportOption(Icons.ios_share_rounded, 'SHARE ANTHOLOGY', 'Export as secure .db file', const Color(0xFF5D4037), () {
              Navigator.pop(ctx);
              _shareDatabase(context);
            }),
            const SizedBox(height: 16),
            _buildExportOption(Icons.save_as_rounded, 'LOCAL SNAPSHOT', 'Save records to device storage', const Color(0xFFFAB1A0), () {
              Navigator.pop(ctx);
              _saveDatabaseToDevice(context);
            }),
            const SizedBox(height: 16),
            _buildExportOption(Icons.unarchive_rounded, 'RESTORE ARCHIVE', 'Import existing .db records', const Color(0xFFB2BEC3), () {
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
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: Color(0xFF5D4037))),
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
      await Share.shareXFiles([XFile(dbPath)], text: 'Atelier Cuisine Anthology Export');
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
      final fileName = 'Atelier_Archive_${DateTime.now().millisecondsSinceEpoch}.db';
      await FilePicker.platform.saveFile(dialogTitle: 'Save Anthology', fileName: fileName, type: FileType.any, bytes: await dbFile.readAsBytes());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archive saved successfully!'), backgroundColor: Color(0xFF5D4037)));
    } catch (e) {
      debugPrint('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importDatabaseFromFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.single.path == null) return;
      final filePath = result.files.single.path!;
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("IMPORT ANTHOLOGY?", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
          content: const Text("This action will permanently replace your current records with the imported file.", style: TextStyle(fontSize: 13, color: Color(0xFF636E72))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL", style: TextStyle(color: Color(0xFFB2BEC3), fontWeight: FontWeight.w900))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("PROCEED", style: TextStyle(color: Color(0xFFFAB1A0), fontWeight: FontWeight.w900))),
          ],
        ),
      );

      if (confirm == true) {
        if (!mounted) return;
        setState(() => _isLoading = true);
        await DatabaseHelper().importDatabase(filePath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archive restored successfully!'), backgroundColor: Color(0xFF5D4037)));
          context.read<SyncProvider>().refreshAfterRestore();
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
        content: const Text('Are you sure you want to terminate your current session?', style: TextStyle(fontSize: 13, color: Color(0xFF636E72))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: Color(0xFFB2BEC3), fontWeight: FontWeight.w900))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LOGOUT', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.w900))),
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
