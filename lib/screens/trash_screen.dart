import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sync_provider.dart';
import '../api_service.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _trashRecipes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);
    final data = await syncProvider.getTrashRecipes();
    setState(() {
      _trashRecipes = data;
      _isLoading = false;
    });
  }

  Future<void> _restore(int id) async {
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);
    await syncProvider.restoreRecipe(id);

    // Sync change to cloud
    syncProvider.triggerAutoBackupIfEnabled();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recipe restored!')),
    );
    _loadTrash();
  }

  Future<void> _deletePermanently(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Permanently?'),
        content: const Text(
            'This will remove the recipe forever from your phone and cloud.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _apiService.deleteRecipe(id, permanent: true);

      // Sync change to cloud
      if (!mounted) return;
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);
      syncProvider.triggerAutoBackupIfEnabled();

      _loadTrash();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        title: const Text('RECYCLE BIN',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 2, color: Colors.white)),
        backgroundColor: const Color(0xFF1B4D3E),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B4D3E)))
          : _trashRecipes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_delete_rounded, size: 80, color: const Color(0xFF1B4D3E).withOpacity(0.1)),
                      const SizedBox(height: 24),
                      const Text('NOTHING IN STORAGE',
                          style: TextStyle(color: Color(0xFFE1B12C), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      Text('Your collection is clean.',
                          style: TextStyle(color: Colors.brown.shade200, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 160),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _trashRecipes.length,
                  itemBuilder: (ctx, index) {
                    final item = _trashRecipes[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: item['item_photo'] != null
                              ? Image.file(File(item['item_photo']),
                                  width: 56, height: 56, fit: BoxFit.cover)
                              : Container(
                                  width: 56,
                                  height: 56,
                                  color: const Color(0xFFFDFBF7),
                                  child: const Icon(Icons.image_not_supported_rounded, color: Color(0xFFE2E8F0))),
                        ),
                        title: Text(item['name'].toString().toUpperCase(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B4D3E), fontSize: 13, letterSpacing: 0.5)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              'ARCHIVED: ${item['deleted_at'].toString().split('T')[0]}',
                              style: const TextStyle(color: Color(0xFFE1B12C), fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.history_rounded,
                                  color: Color(0xFFB2BEC3), size: 22),
                              onPressed: () => _restore(item['id']),
                              tooltip: 'Restore',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever_rounded,
                                  color: Color(0xFFE1B12C), size: 22),
                              onPressed: () => _deletePermanently(item['id']),
                              tooltip: 'Delete Permanently',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
