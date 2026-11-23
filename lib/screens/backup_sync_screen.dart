import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sync_provider.dart';

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);

/// What is stored on this phone, and a button to download everything from
/// the account. The account itself is the backup: sign in on a new phone
/// and everything comes back.
class BackupSyncScreen extends StatelessWidget {
  const BackupSyncScreen({super.key});

  String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _when(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return 'Not downloaded yet';
    final now = DateTime.now();
    final t = '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Downloaded today at $t';
    }
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Downloaded ${d.day} ${m[d.month - 1]} at $t';
  }

  Widget _count(String n, String label) => Expanded(
        child: Column(children: [
          Text(n,
              style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _fg)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final sync = Provider.of<SyncProvider>(context);
    final s = sync.stats;
    final ready = sync.lastDownload != null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Backup & sync',
            style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.w700,
                fontSize: 19,
                color: _fg)),
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _fg,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _accentSoft, borderRadius: BorderRadius.circular(16)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_done_outlined, color: _accent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                    'Your Recipia account is your backup. Sign in on a new phone and your recipes, ingredients and photos come back.',
                    style: TextStyle(fontSize: 14, height: 1.45, color: _accent)),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('ON THIS PHONE',
                style: TextStyle(
                    fontSize: 12, letterSpacing: .8, fontWeight: FontWeight.w700, color: _muted)),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _count('${s['recipeCount'] ?? '–'}', 'recipes'),
                _count('${s['ingredientCount'] ?? '–'}', 'ingredients'),
                _count('${sync.localPhotoCount}', 'photos'),
              ]),
              const SizedBox(height: 16),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 14),
              Row(children: [
                Icon(ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 18, color: ready ? _accent : _muted),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${_when(sync.lastDownload)} · ${_size(sync.localDatabaseSize)}',
                        style: const TextStyle(fontSize: 13.5, color: _muted))),
              ]),
              const SizedBox(height: 16),
              if (sync.isDownloadingAll)
                const Column(children: [
                  LinearProgressIndicator(color: _accent, backgroundColor: _accentSoft),
                  SizedBox(height: 10),
                  Text('Downloading recipes, ingredients and photos…',
                      style: TextStyle(fontSize: 13, color: _muted)),
                ])
              else
                FilledButton.icon(
                  onPressed: () async {
                    final error = await sync.downloadAllFromServer();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: error == null ? _accent : const Color(0xFFC0392B),
                      content: Text(error == null
                          ? 'Ready to use offline'
                          : 'Couldn’t download. Check your internet and try again.'),
                    ));
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(ready ? 'Update offline copy' : 'Download everything for offline'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                  'Recipes, ingredients, prices and photos, so the app works with no internet.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: _muted)),
            ]),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
                'Everything you change is saved on this phone first and sent to your account when you’re online.',
                style: TextStyle(fontSize: 13, height: 1.45, color: _muted)),
          ),
        ],
      ),
    );
  }
}
