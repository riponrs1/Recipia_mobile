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
      final syncProvider = Provider.of<SyncProvider>(context, listen: false);
      syncProvider.triggerAutoBackupIfEnabled();

      _loadTrash();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trashRecipes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Your Recycle Bin is empty',
                          style: TextStyle(color: Colors.grey, fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trashRecipes.length,
                  itemBuilder: (ctx, index) {
                    final item = _trashRecipes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item['item_photo'] != null
                              ? Image.file(File(item['item_photo']),
                                  width: 50, height: 50, fit: BoxFit.cover)
                              : Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image)),
                        ),
                        title: Text(item['name'],
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'Deleted: ${item['deleted_at'].toString().split('T')[0]}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore,
                                  color: Colors.green),
                              onPressed: () => _restore(item['id']),
                              tooltip: 'Restore',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever,
                                  color: Colors.red),
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
