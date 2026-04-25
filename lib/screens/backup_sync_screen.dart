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
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        title: const Text('BACKUP & SYNC',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 13, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B4D3E),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          children: [
            // --- NEW: Offline Readiness Section ---
            Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 15,
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
                          color: const Color(0xFF1B4D3E).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.offline_pin_rounded,
                            color: Color(0xFF1B4D3E), size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Offline Access",
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))),
                            Text("Use the app without internet",
                                style:
                                    TextStyle(fontSize: 10, color: Color(0xFFB2BEC3), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 48, color: Color(0xFFFDFBF7)),
                  const Text(
                    "Download all recipes, ingredients, and categories to your local database so you can work completely offline without an internet connection.",
                    style: TextStyle(color: Color(0xFF636E72), fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  if (syncProvider.isDownloadingAll)
                    const Column(
                      children: [
                        LinearProgressIndicator(color: Color(0xFFE1B12C)),
                        SizedBox(height: 12),
                        Text("UPDATING YOUR DATA...",
                            style: TextStyle(color: Color(0xFFE1B12C), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final error = await syncProvider.downloadAllFromServer();
                          if (!mounted) return;
                          
                          if (error == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Offline data ready!'),
                              backgroundColor: Color(0xFF1B4D3E),
                            ));
                          }
                        },
                        icon: const Icon(Icons.download_for_offline_rounded, size: 20),
                        label: const Text("DOWNLOAD DATA",
                            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE1B12C),
                          foregroundColor: const Color(0xFF1B4D3E),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // --- Cloud Backup Section ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 15,
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
                          color: const Color(0xFF1B4D3E).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.cloud_sync,
                            color: Color(0xFF1B4D3E), size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Cloud Backups",
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))),
                            Text("Google Drive Backup",
                                style:
                                    TextStyle(fontSize: 10, color: Color(0xFFB2BEC3), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 48, color: Color(0xFFFDFBF7)),
                  if (!syncProvider.isGoogleSignedIn &&
                      syncProvider.userEmail == null)
                    Column(
                      children: [
                        const Text(
                          "Connect your Google Account to backup your recipes and restore them on any device.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF636E72), height: 1.6, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () => syncProvider.signIn(),
                            icon: Image.network(
                              'https://www.gstatic.com/images/branding/product/1x/googleg_48dp.png',
                              height: 20,
                            ),
                            label: const Text("CONNECT DRIVE",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                    color: Color(0xFF1B4D3E))),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFDFBF7),
                              foregroundColor: const Color(0xFF1B4D3E),
                              elevation: 0,
                              side: BorderSide(color: const Color(0xFF1B4D3E).withOpacity(0.1)),
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
                            color: const Color(0xFFFDFBF7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                  syncProvider.isGoogleSignedIn
                                      ? Icons.verified_user_rounded
                                      : Icons.cloud_off_rounded,
                                  color: syncProvider.isGoogleSignedIn
                                      ? const Color(0xFFE1B12C)
                                      : const Color(0xFFB2BEC3),
                                  size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  syncProvider.isGoogleSignedIn
                                      ? "ACCOUNT: ${syncProvider.userEmail}"
                                      : "OFFLINE: ${syncProvider.userEmail}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 0.5,
                                      color: Color(0xFF1B4D3E)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (syncProvider.cloudMetadata != null) ...[
                          _buildDetailRow(
                              Icons.history_rounded,
                              "Last Backup",
                              _formatDate(
                                  syncProvider.cloudMetadata!['modifiedTime'])),
                          const SizedBox(height: 12),
                          _buildDetailRow(Icons.layers_outlined, "Storage Data",
                              _formatSize(syncProvider.cloudMetadata!['size'])),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                              Icons.storage_rounded,
                              "Local Cache",
                              _formatSize(syncProvider.localDatabaseSize)),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                              Icons.collections_rounded,
                              "Media Assets",
                              "${syncProvider.localPhotoCount} photos"),
                          const Divider(height: 48, color: Color(0xFFFDFBF7)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Auto Backup",
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: Color(0xFF1B4D3E))),
                                    Text("Sync automatically when you are online",
                                        style: TextStyle(
                                            fontSize: 10, color: Color(0xFFB2BEC3), fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: syncProvider.isAutoBackupEnabled,
                                onChanged: (v) =>
                                    syncProvider.toggleAutoBackup(v),
                                activeColor: const Color(0xFFE1B12C),
                              ),
                            ],
                          ),
                        ] else ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE1B12C).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    color: Color(0xFFE1B12C)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text("No backups found in the cloud.",
                                      style: TextStyle(
                                          color: Color(0xFFE1B12C),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                          letterSpacing: 0.5)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),
                        if (syncProvider.status == SyncStatus.syncing)
                          const Column(
                            children: [
                              LinearProgressIndicator(color: Color(0xFFE1B12C)),
                              SizedBox(height: 12),
                              Text("COMMUNICATING WITH GOOGLE DRIVE...",
                                  style: TextStyle(
                                      color: Color(0xFFE1B12C), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
                                                  Text('Archive successful!'),
                                              backgroundColor: Color(0xFF1B4D3E),
                                            ));
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B4D3E),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                    elevation: 0,
                                  ),
                                  child: const Text("BACKUP NOW",
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _showRestoreConfirmDialog(
                                      context, syncProvider),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Color(0xFFE1B12C), width: 1.5),
                                    foregroundColor: const Color(0xFFE1B12C),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                  ),
                                  child: const Text("RESTORE",
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _isSyncing
                                  ? null
                                  : () async {
                                      setState(() => _isSyncing = true);
                                      final success = await syncProvider
                                          .forceFullCloudBackup();
                                      setState(() => _isSyncing = false);
                                      if (success && mounted) {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Icon(
                                                Icons.verified_user_rounded,
                                                color: Color(0xFFE1B12C),
                                                size: 48),
                                            content: const Text(
                                              "Data Transfer Complete.\n\nYour entire collection is now safely backed up. You can now move to another phone safely.",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 13, height: 1.6),
                                            ),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E))))
                                            ],
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.security_rounded, size: 16),
                              label: const Text("FULL DATA SYNC",
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFB2BEC3),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 140),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('RESTORE DATA?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
        content: const Text(
            'This will permanently overwrite your local recipes with the backup from Google Drive.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF636E72))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL', style: TextStyle(color: Color(0xFFB2BEC3), fontWeight: FontWeight.w900))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('PROCEED', style: TextStyle(color: Color(0xFFE1B12C), fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isSyncing = true);
      final success = await syncProvider.restoreData();
      if (mounted) setState(() => _isSyncing = false);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Restoration successful!'),
            backgroundColor: Color(0xFF1B4D3E)));
      }
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFE1B12C)),
        const SizedBox(width: 12),
        Text("$label: ",
            style: const TextStyle(fontSize: 12, color: Color(0xFFB2BEC3), fontWeight: FontWeight.w600)),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1B4D3E))),
      ],
    );
  }
}
