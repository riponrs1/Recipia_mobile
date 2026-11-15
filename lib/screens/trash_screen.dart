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
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Trash',
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _trashRecipes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.delete_outline_rounded,
                                  size: 64, color: _accentSoft),
                              SizedBox(height: 14),
                              Text('Trash is empty',
                                  style: TextStyle(
                                      color: _muted,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(2, 0, 2, 12),
                              child: Text(
                                  'Deleted recipes stay here for 30 days, then are removed for good.',
                                  style:
                                      TextStyle(color: _muted, fontSize: 13)),
                            ),
                            ..._trashRecipes.map(_trashCard),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trashCard(Map<String, dynamic> item) {
    final name = item['name'].toString();
    final date = item['deleted_at'] != null
        ? item['deleted_at'].toString().split('T')[0]
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: _accentSoft, borderRadius: BorderRadius.circular(13)),
            alignment: Alignment.center,
            child: item['item_photo'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.file(File(item['item_photo']),
                        width: 44, height: 44, fit: BoxFit.cover),
                  )
                : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: _accent, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _fg)),
                if (date.isNotEmpty)
                  Text('Deleted $date',
                      style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _restore(item['id']),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _accent)),
              child: const Text('Restore',
                  style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
          GestureDetector(
            onTap: () => _deletePermanently(item['id']),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.delete_forever_rounded,
                  color: Color(0xFFC0392B), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

const _bg = Color(0xFFFFFBF0);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF2D3436);
const _muted = Color(0xFF636E72);
const _line = Color(0xFFECE3D1);
const _accent = Color(0xFF1B4D3E);
const _accentSoft = Color(0xFFE6EFE9);
