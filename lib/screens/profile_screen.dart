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
    final name = _userData?['name'] ?? syncProvider.userName ?? "Executive Chef";
    final email = _userData?['email'] ?? syncProvider.userEmail ?? "Culinary Workspace";
    final avatarUrl = _userData?['profile']?['avatar'];

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
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
                        const SizedBox(height: 32),
                        _buildMenuSection('KITCHEN MANAGEMENT', [
                          _buildMenuItem(Icons.sync_rounded, Colors.blue, 'Backup & Sync', 'Cloud storage with Google Drive', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupSyncScreen()))),
                          _buildMenuItem(Icons.category_outlined, Colors.orange, 'Cuisines & Sections', 'Personalize your kitchen categories', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeSectionsScreen()))),
                          _buildMenuItem(Icons.delete_outline_rounded, Colors.red, 'Culinary Archive', 'Restore deleted masterpieces', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashScreen()))),
                        ]),
                        const SizedBox(height: 24),
                        _buildMenuSection('SYSTEM', [
                          _buildMenuItem(Icons.import_export_rounded, Colors.teal, 'Export Records', 'Secure your local .db file', () => _exportDatabase(context)),
                          _buildMenuItem(Icons.logout_rounded, Colors.grey.shade700, 'Logout', 'Safely sign out of Atelier', () => _handleLogout(context, syncProvider)),
                        ]),
                        const SizedBox(height: 40),
                        Text('RECIPIA v2.0 • GOURMET ELEGANCE', style: TextStyle(color: Colors.brown.shade100, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
      expandedHeight: 320.0,
      pinned: true,
      elevation: 0,
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
              right: -50,
              top: -50,
              child: Icon(Icons.restaurant_rounded, size: 280, color: Colors.white.withOpacity(0.04)),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFFFAB1A0), shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 54,
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
                          backgroundColor: Color(0xFFFAB1A0),
                          child: Icon(Icons.edit_rounded, color: Color(0xFF5D4037), size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                Text(email, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w500)),
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
        _buildStatCard('MASTERPIECES', _stats['recipeCount'].toString(), Icons.menu_book_rounded),
        const SizedBox(width: 12),
        _buildStatCard('PANTRY VALUE', '\$${_stats['pantryValue'].toStringAsFixed(0)}', Icons.inventory_2_rounded),
        const SizedBox(width: 12),
        _buildStatCard('SECTIONS', _stats['sectionCount'].toString(), Icons.grid_view_rounded),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFFAB1A0), size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF5D4037))),
            Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1)),
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
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF2D3436))),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }

  Future<void> _exportDatabase(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Archive Records", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 24),
            _buildExportOption(Icons.share_rounded, 'SHARE ARCHIVE', 'Export to cloud or other apps', Colors.blue, () {
              Navigator.pop(ctx);
              _shareDatabase(context);
            }),
            const SizedBox(height: 12),
            _buildExportOption(Icons.save_alt_rounded, 'SAVE TO DISK', 'Secure a copy on this device', Colors.teal, () {
              Navigator.pop(ctx);
              _saveDatabaseToDevice(context);
            }),
            const SizedBox(height: 12),
            _buildExportOption(Icons.upload_file_rounded, 'RESTORE ARCHIVE', 'Import an existing .db file', Colors.orange, () {
              Navigator.pop(ctx);
              _importDatabaseFromFile(context);
            }),
            const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
      await Share.shareXFiles([XFile(dbPath)], text: 'Recipia Culinary Archive Export');
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
      final fileName = 'Recipia_Atelier_${DateTime.now().millisecondsSinceEpoch}.db';
      await FilePicker.platform.saveFile(dialogTitle: 'Save Archive', fileName: fileName, type: FileType.any, bytes: await dbFile.readAsBytes());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archive saved successfully!'), backgroundColor: Colors.green));
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
          title: const Text("Restore Archive?"),
          content: const Text("This will PERMANENTLY REPLACE your current kitchen records. This action cannot be undone."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("RESTORE", style: TextStyle(color: Colors.red))),
          ],
        ),
      );

      if (confirm == true) {
        setState(() => _isLoading = true);
        await DatabaseHelper().importDatabase(filePath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archive restored successfully!'), backgroundColor: Colors.green));
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
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout', style: TextStyle(color: Colors.red))),
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
