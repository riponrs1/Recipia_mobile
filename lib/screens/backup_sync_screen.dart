import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sync_provider.dart';

class BackupSyncScreen extends StatefulWidget {
  const BackupSyncScreen({super.key});

  @override
  State<BackupSyncScreen> createState() => _BackupSyncScreenState();
}

class _BackupSyncScreenState extends State<BackupSyncScreen> {
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    final syncProvider = Provider.of<SyncProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Backup & Sync',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
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
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.cloud_sync,
                            color: Colors.blue.shade700, size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Cloud Backup",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("Google Drive Storage",
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 48),
                  if (!syncProvider.isGoogleSignedIn &&
                      syncProvider.userEmail == null)
                    Column(
                      children: [
                        const Text(
                          "Connect your Google Account to backup your recipes and restore them on any device.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
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
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                  syncProvider.isGoogleSignedIn
                                      ? Icons.check_circle
                                      : Icons.cloud_off,
                                  color: syncProvider.isGoogleSignedIn
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  syncProvider.isGoogleSignedIn
                                      ? "Account: ${syncProvider.userEmail}"
                                      : "${syncProvider.userEmail} (Offline)",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (syncProvider.cloudMetadata != null) ...[
                          _buildDetailRow(
                              Icons.access_time,
                              "Last Backup",
                              _formatDate(
                                  syncProvider.cloudMetadata!['modifiedTime'])),
                          const SizedBox(height: 12),
                          _buildDetailRow(Icons.storage, "Backup Size",
                              _formatSize(syncProvider.cloudMetadata!['size'])),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                              Icons.file_present_outlined,
                              "Local Database",
                              _formatSize(syncProvider.localDatabaseSize)),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                              Icons.photo_library_outlined,
                              "Media Count",
                              "${syncProvider.localPhotoCount} photos"),
                          const Divider(height: 48),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Auto Backup",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  Text("Sync automatically when online",
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey)),
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
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text("No cloud backup found yet.",
                                      style: TextStyle(
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),
                        if (syncProvider.status == SyncStatus.syncing)
                          const Column(
                            children: [
                              LinearProgressIndicator(color: Color(0xFFE74C3C)),
                              SizedBox(height: 12),
                              Text("Syncing with Google Drive...",
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 13)),
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
                                          setState(() => _isSyncing = true);
                                          final success =
                                              await syncProvider.backupData();
                                          setState(() => _isSyncing = false);
                                          if (success && mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                              content:
                                                  Text('Backup successful!'),
                                              backgroundColor: Colors.green,
                                            ));
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE74C3C),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                    elevation: 2,
                                  ),
                                  child: const Text("Backup Now",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _showRestoreConfirmDialog(
                                      context, syncProvider),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Color(0xFFE74C3C)),
                                    foregroundColor: const Color(0xFFE74C3C),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                  ),
                                  child: const Text("Restore",
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
            'This will overwrite current local data with the version from Google Drive. This cannot be undone.'),
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
            content: Text('Restoration successful!'),
            backgroundColor: Colors.green));
      }
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blue.shade400),
        const SizedBox(width: 12),
        Text("$label: ",
            style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748))),
      ],
    );
  }
}
