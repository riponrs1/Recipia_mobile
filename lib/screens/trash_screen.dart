import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sync_provider.dart';
import '../api_service.dart';
import '../database_helper.dart';

/// Recipes stay in Trash for this many days, then are deleted for good.
const trashDays = 30;

/// Deletes recipes that have been in Trash longer than [trashDays].
/// Called when the app starts; anything that fails is retried next time.
Future<int> purgeOldTrash() async {
  final api = ApiService();
  var n = 0;
  for (final r in await DatabaseHelper().getTrashRecipes()) {
    final at = DateTime.tryParse(r['deleted_at']?.toString() ?? '');
    if (at == null || DateTime.now().difference(at).inDays < trashDays) continue;
    if (await api.deleteRecipe(r['id'] as int, permanent: true) == null) n++;
  }
  return n;
}

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

  /// One recipe, or everything when [item] is null. Can't be undone, so it asks.
  Future<void> _deleteForever(Map<String, dynamic>? item) async {
    final all = item == null;
    final n = all ? _trashRecipes.length : 1;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(all ? 'Empty trash?' : 'Delete “${item['name']}” forever?',
                      style: const TextStyle(
                          fontFamily: 'SpaceGrotesk', fontSize: 18, fontWeight: FontWeight.w700, color: _fg)),
                ),
                InkWell(
                  onTap: () => Navigator.pop(ctx, false),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _line),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16, color: _muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFBEFD9), borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline_rounded, size: 19, color: Color(0xFFA8650A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: all
                                ? 'All $n recipe${n == 1 ? '' : 's'} in Trash will be deleted'
                                : 'This recipe will be deleted'),
                        const TextSpan(text: ' from this phone and your account. '),
                        const TextSpan(
                            text: 'This can’t be undone.',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      style: const TextStyle(fontSize: 14, height: 1.45, color: _fg)),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(all ? 'Delete $n forever' : 'Delete forever',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _fg,
                  backgroundColor: _surface,
                  side: const BorderSide(color: _line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    final ids = all ? _trashRecipes.map((r) => r['id'] as int).toList() : [item['id'] as int];
    for (final id in ids) {
      await _apiService.deleteRecipe(id, permanent: true);
    }
    if (!mounted) return;
    Provider.of<SyncProvider>(context, listen: false).triggerAutoBackupIfEnabled();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(n > 1 ? '$n recipes deleted forever' : 'Deleted forever'),
    ));
    _loadTrash();
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
                              padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
                              child: Text(
                                  'Deleted recipes stay here for $trashDays days, then are removed for good.',
                                  style:
                                      TextStyle(color: _muted, fontSize: 13)),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 0, 0, 10),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                      '${_trashRecipes.length} recipe${_trashRecipes.length == 1 ? '' : 's'}',
                                      style: const TextStyle(fontSize: 13, color: _muted)),
                                ),
                                OutlinedButton(
                                  onPressed: () => _deleteForever(null),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _red,
                                    backgroundColor: _surface,
                                    side: const BorderSide(color: _line),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Empty trash',
                                      style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ]),
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
    final at = DateTime.tryParse(item['deleted_at']?.toString() ?? '');
    final ago = at == null ? 0 : DateTime.now().difference(at).inDays;
    final left = (trashDays - ago).clamp(0, trashDays);
    final when = at == null
        ? ''
        : (ago == 0 ? 'Deleted today' : 'Deleted $ago day${ago == 1 ? '' : 's'} ago');
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
                if (when.isNotEmpty)
                  Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$when · '),
                        TextSpan(
                            text: 'deletes in $left day${left == 1 ? '' : 's'}',
                            style: left <= 3
                                ? const TextStyle(color: _red, fontWeight: FontWeight.w600)
                                : null),
                      ]),
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
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Delete $name forever',
            child: GestureDetector(
              onTap: () => _deleteForever(item),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: const Color(0xFFF4EFE8),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _line)),
                child: const Icon(Icons.delete_outline_rounded, color: _red, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);
const _red = Color(0xFFC0392B);
