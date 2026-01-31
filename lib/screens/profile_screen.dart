import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../sync_provider.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import '../widgets/app_drawer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ApiService();
  Map<String, dynamic>? _userData;
  bool _isLoading = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Check for cloud backup on start (WhatsApp style)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);
      if (await syncProvider.detectMissingLocalData()) {
        if (mounted) _showRestoreConfirmDialog(context, syncProvider);
      }
    });
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () => _handleLogout(context, syncProvider),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
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
                          radius: 60,
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
                                      fontSize: 40,
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
                          radius: 18,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.edit,
                                color: Colors.white, size: 18),
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
                  const SizedBox(height: 24),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 24,
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

                  const SizedBox(height: 48),

                  // Cloud Backup Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.cloud_upload_outlined,
                                  color: Colors.blue.shade700, size: 28),
                            ),
                            const SizedBox(width: 16),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Cloud Backup",
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text("Google Drive",
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        if (!syncProvider.isGoogleSignedIn &&
                            syncProvider.userEmail == null)
                          Column(
                            children: [
                              const Text(
                                "Connect your Google Account to backup your recipes and restore them on any device.",
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: Colors.grey, height: 1.5),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: () => syncProvider.signIn(),
                                  icon: Image.network(
                                    'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                                    height: 20,
                                  ),
                                  label: const Text("Connect Google Drive",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    side:
                                        BorderSide(color: Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                      syncProvider.isGoogleSignedIn
                                          ? Icons.check_circle
                                          : Icons.cloud_off,
                                      color: syncProvider.isGoogleSignedIn
                                          ? Colors.green
                                          : Colors.grey,
                                      size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            syncProvider.isGoogleSignedIn
                                                ? "Connected as ${syncProvider.userEmail}"
                                                : "${syncProvider.userEmail}",
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!syncProvider.isGoogleSignedIn) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text('Offline',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey)),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (syncProvider.cloudMetadata != null) ...[
                                _buildDetailRow(
                                    Icons.access_time,
                                    "Last Backup",
                                    _formatDate(syncProvider
                                        .cloudMetadata!['modifiedTime'])),
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                    Icons.storage,
                                    "Backup Size",
                                    _formatSize(
                                        syncProvider.cloudMetadata!['size'])),
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                    Icons.file_present_outlined,
                                    "Local Data Size",
                                    _formatSize(
                                        syncProvider.localDatabaseSize)),
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                    Icons.photo_library_outlined,
                                    "Local Photos",
                                    syncProvider.localPhotoCount.toString()),
                                const Divider(height: 32),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text("Auto Backup",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        Text("Backup automatically",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey)),
                                      ],
                                    ),
                                    Switch.adaptive(
                                      value: syncProvider.isAutoBackupEnabled,
                                      onChanged: (v) =>
                                          syncProvider.toggleAutoBackup(v),
                                      activeColor: const Color(0xFFE74C3C),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          size: 16,
                                          color: Colors.orange.shade700),
                                      const SizedBox(width: 8),
                                      Text("No cloud backup found",
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              if (syncProvider.status == SyncStatus.syncing)
                                const Column(
                                  children: [
                                    LinearProgressIndicator(),
                                    SizedBox(height: 8),
                                    Text("Syncing...",
                                        style: TextStyle(
                                            color: Colors.grey, fontSize: 12)),
                                  ],
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _isSyncing
                                            ? null
                                            : () async {
                                                setState(
                                                    () => _isSyncing = true);
                                                final success =
                                                    await syncProvider
                                                        .backupData();
                                                setState(
                                                    () => _isSyncing = false);
                                                if (success &&
                                                    context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              'Backup successful!')));
                                                }
                                              },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFE74C3C),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                        ),
                                        child: const Text("Backup Now",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () async {
                                          _showRestoreConfirmDialog(
                                              context, syncProvider);
                                        },
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                        ),
                                        child: const Text("Restore Data",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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

  String _formatSize(dynamic size) {
    if (size == null) return "0 B";
    final bytes = int.tryParse(size.toString()) ?? 0;
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  String _formatDate(String? iso) {
    if (iso == null) return "Never";
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return "Today at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
      }
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return iso;
    }
  }

  Future<void> _showRestoreConfirmDialog(
      BuildContext context, SyncProvider syncProvider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Backup?'),
        content: const Text(
            'This will overwrite current local data with the version from Google Drive. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSyncing = true);
      final success = await syncProvider.restoreData();
      setState(() => _isSyncing = false);

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Restoration complete! Please restart or refresh to see changes.')));
        // Optional: Refresh data
        _loadData();
      }
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blue.shade300),
        const SizedBox(width: 8),
        Text("$label: ",
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5568))),
      ],
    );
  }
}
