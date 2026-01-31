import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../sync_provider.dart';
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await _apiService.getUser();
      if (mounted) {
        setState(() {
          _userData = user;
        });
      }
    } catch (e) {
      // Ignore errors, we'll use local/sync data
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = Provider.of<SyncProvider>(context);

    // Determine display name and email
    final name = _userData?['name'] ?? syncProvider.userName ?? "Chef";
    final email =
        _userData?['email'] ?? syncProvider.userEmail ?? "Offline Mode";
    final avatarUrl = _userData?['profile']?['avatar'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Avatar Section
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.white,
                          backgroundImage: avatarUrl != null
                              ? CachedNetworkImageProvider(
                                  ApiService.getImageUrl(avatarUrl))
                              : (syncProvider.userPhoto != null
                                  ? NetworkImage(syncProvider.userPhoto!)
                                  : null) as ImageProvider?,
                          child: (avatarUrl == null &&
                                  syncProvider.userPhoto == null)
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                  style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE74C3C)),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: const Color(0xFFE74C3C),
                          radius: 16,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.edit,
                                color: Colors.white, size: 16),
                            onPressed: () async {
                              if (_userData != null) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => EditProfileScreen(
                                          userData: _userData!)),
                                );
                                _loadData();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Menu Items Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildMenuTile(
                          icon: Icons.sync_rounded,
                          color: Colors.blue,
                          title: "Backup & Sync",
                          subtitle: "Google Drive cloud storage",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const BackupSyncScreen())),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.category_outlined,
                          color: Colors.orange,
                          title: "Recipe Sections",
                          subtitle: "Manage your food categories",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const RecipeSectionsScreen())),
                        ),
                        const Divider(height: 1),
                        _buildMenuTile(
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red,
                          title: "Recycle Bin",
                          subtitle: "Restore deleted recipes",
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const TrashScreen())),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Logout Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _buildMenuTile(
                      icon: Icons.logout_rounded,
                      color: Colors.grey.shade700,
                      title: "Logout",
                      subtitle: "Sign out of your account",
                      onTap: () => _handleLogout(context, syncProvider),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }

  Future<void> _handleLogout(
      BuildContext context, SyncProvider syncProvider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);

      await _apiService.logout();
      await syncProvider.signOut();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
