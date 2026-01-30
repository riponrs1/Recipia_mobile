import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../sync_provider.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ApiService();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await _apiService.getUser();
      // Fetch recipe count
      final recipes = await _apiService.getMyRecipes();

      if (mounted) {
        setState(() {
          _userData = user;
          // Store count separately or inject into map
          _userData!['recipes_count'] = recipes.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = Provider.of<SyncProvider>(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Default data for offline or failed state
    final name = _userData?['name'] ?? syncProvider.userName ?? "Guest User";
    final profile = _userData?['profile'];
    final recipesCount = _userData?['recipes_count'] ?? 0;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cover Photo & Header Stack
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Cover Photo
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Actions (Edit/Logout)
                Positioned(
                  top: 40,
                  right: 16,
                  child: Row(
                    children: [
                      if (_userData != null)
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          onPressed: () async {
                            final refresh = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      EditProfileScreen(userData: _userData!)),
                            );
                            if (refresh == true) _loadData();
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Logout?'),
                              content: const Text(
                                  'Are you sure you want to logout?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Logout',
                                        style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            setState(() => _isLoading = true);
                            await _apiService.logout();
                            await syncProvider.signOut();
                            if (context.mounted) {
                              Navigator.of(context, rootNavigator: true)
                                  .pushNamedAndRemoveUntil(
                                      '/login', (route) => false);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
                // Avatar
                Positioned(
                  bottom: -60,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      backgroundImage:
                          profile != null && profile['avatar'] != null
                              ? CachedNetworkImageProvider(
                                  ApiService.getImageUrl(profile['avatar']))
                              : (syncProvider.userPhoto != null
                                  ? NetworkImage(syncProvider.userPhoto!)
                                  : null) as ImageProvider?,
                      child: (profile == null || profile['avatar'] == null) &&
                              syncProvider.userPhoto == null
                          ? Text(name[0].toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC0392B)))
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 70),

            // Name & Bio
            Text(
              name,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748)),
            ),
            if (profile != null && profile['username'] != null)
              Text(
                '@${profile['username']}',
                style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFE74C3C),
                    fontWeight: FontWeight.w500),
              )
            else if (syncProvider.userEmail != null)
              Text(
                syncProvider.userEmail!,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w400),
              ),

            const SizedBox(height: 24),

            // Backup & Sync Section (New)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildInfoCard(
                title: "Backup & Sync",
                icon: Icons.cloud_sync,
                children: [
                  if (!syncProvider.isGoogleSignedIn)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => syncProvider.signIn(),
                        icon: const Icon(Icons.login),
                        label: const Text("Connect Google Drive"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE74C3C),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Cloud Backup",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          syncProvider.cloudMetadata != null
                              ? "Found"
                              : "Not found",
                          style: TextStyle(
                            color: syncProvider.cloudMetadata != null
                                ? Colors.green
                                : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (syncProvider.cloudMetadata != null)
                      Text(
                        "Last cloud sync: ${syncProvider.cloudMetadata!['modifiedTime'] ?? 'Unknown'}",
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: syncProvider.status == SyncStatus.syncing
                                ? null
                                : () async {
                                    final success =
                                        await syncProvider.backupData();
                                    if (success && mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text("Backup successful!")),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.upload),
                            label: const Text("Backup"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: syncProvider.status == SyncStatus.syncing
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("Restore Data?"),
                                        content: const Text(
                                            "This will overwrite your local recipes with the cloud backup. Proceed?"),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text("Cancel")),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text("Restore",
                                                  style: TextStyle(
                                                      color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final success =
                                          await syncProvider.restoreData();
                                      if (success && mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  "Restoration complete!")),
                                        );
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.download),
                            label: const Text("Restore"),
                          ),
                        ),
                      ],
                    ),
                    if (syncProvider.status == SyncStatus.syncing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info Sections
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (_userData != null)
                    _buildInfoCard(
                      title: "Personal Information",
                      icon: Icons.person,
                      children: [
                        _buildInfoRow(
                            Icons.email, "Email", _userData!['email']),
                        _buildInfoRow(Icons.location_on, "Location",
                            profile?['location'] ?? 'Not specified'),
                        _buildInfoRow(Icons.language, "Website",
                            profile?['website'] ?? 'Not specified'),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFFE74C3C), Color(0xFFC0392B)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFFE74C3C)),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF4A5568), fontWeight: FontWeight.w500)),
            ],
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                  color: Color(0xFF2D3748), fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
