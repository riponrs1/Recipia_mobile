import 'package:flutter/material.dart';
import '../api_service.dart';
import '../database_helper.dart';

class RecipeSectionsScreen extends StatefulWidget {
  const RecipeSectionsScreen({super.key});

  @override
  State<RecipeSectionsScreen> createState() => _RecipeSectionsScreenState();
}

class _RecipeSectionsScreenState extends State<RecipeSectionsScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _sections = [];
  Map<String, int> _counts = {};
  final _newCtl = TextEditingController();
  final _renameCtl = TextEditingController();
  int? _renamingId;

  @override
  void dispose() {
    _newCtl.dispose();
    _renameCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    // Only show the spinner on first load; later reloads update in place.
    if (_sections.isEmpty) setState(() => _isLoading = true);
    try {
      final localSections = await DatabaseHelper().getLocalSections();
      final counts = await DatabaseHelper().getSectionRecipeCounts();
      if (!mounted) return;
      setState(() {
        _sections = List.of(localSections);
        _counts = counts;
        _isLoading = false;
      });

      // Background sync from API if online
      try {
        final apiSections = await _apiService.getSections();
        if (apiSections.isNotEmpty) {
          for (var s in apiSections) {
            await DatabaseHelper().saveLocalSection({
              'server_id': s['id'],
              'name': s['name'],
              'is_system': s['user_id'] == null ? 1 : 0,
              'icon': s['icon'] ?? 'category',
              'created_at': s['created_at'] ?? DateTime.now().toIso8601String(),
            });
          }
          final refreshedLocal = await DatabaseHelper().getLocalSections();
          if (mounted) {
            setState(() {
              _sections = List.of(refreshedLocal);
            });
          }
        }
      } catch (e) {
        // Silent fail on background sync
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _addSection() async {
    final trimmedName = _newCtl.text.trim();
    if (trimmedName.isEmpty) return;
    final exists = _sections.any((s) =>
        s['name'].toString().toLowerCase() == trimmedName.toLowerCase());
    if (exists) {
      _toast('A section with this name already exists.');
      return;
    }
    FocusScope.of(context).unfocus();
    _newCtl.clear();
    // Save locally first, at the top like the prototype
    await DatabaseHelper().saveLocalSection({
      'name': trimmedName,
      'server_id': null, // Local draft
      'is_system': 0,
      'icon': 'category',
      'sort_order': -1,
      'created_at': DateTime.now().toIso8601String()
    });
    // Background sync to API
    _apiService.createSection(trimmedName).catchError((_) => null);
    await _loadSections();
    _toast('Section added');
  }

  Future<void> _deleteSection(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Section'),
        content: const Text('Are you sure you want to delete this section?'),
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
      setState(() => _isLoading = true);

      // Delete locally first
      await DatabaseHelper().deleteLocalSection(id);

      // Background sync to API
      _apiService.deleteSection(id).catchError((_) => null);

      _loadSections();
    }
  }

  void _startRename(dynamic section) {
    _renameCtl.text = section['name'].toString();
    _renameCtl.selection =
        TextSelection(baseOffset: 0, extentOffset: _renameCtl.text.length);
    setState(() => _renamingId = section['id']);
  }

  Future<void> _saveRename(dynamic section) async {
    final id = section['id'] as int;
    final currentName = section['name'].toString();
    final trimmedName = _renameCtl.text.trim();
    if (trimmedName.isEmpty) {
      _toast('Name can’t be empty');
      return;
    }
    if (trimmedName == currentName) {
      setState(() => _renamingId = null);
      return;
    }
    final exists = _sections.any((s) =>
        s['id'] != id &&
        s['name'].toString().toLowerCase() == trimmedName.toLowerCase());
    if (exists) {
      _toast('A section with this name already exists.');
      return;
    }
    setState(() => _renamingId = null);
    // Update locally first; recipes in this section move with it
    await DatabaseHelper().updateLocalSection(id, trimmedName);
    await DatabaseHelper().renameRecipeSection(currentName, trimmedName);
    // Background sync to API
    _apiService.updateSection(id, trimmedName).catchError((_) => null);
    await _loadSections();
    _toast('Section renamed');
  }

  void _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, item);
    });

    // Update orders in DB
    final helper = DatabaseHelper();
    for (int i = 0; i < _sections.length; i++) {
      await helper.updateSectionOrder(_sections[i]['id'], i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _fg),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Manage sections',
                      style: TextStyle(fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _fg)),
                ],
              ),
            ),
            // ---- add row (prototype: input + Add button) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newCtl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addSection(),
                    decoration: _fieldDecoration('New section name'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _addSection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Add',
                        style: TextStyle(fontFamily: 'SpaceGrotesk',
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 10, 22, 10),
              child: Text('Drag ⠿ to change the order · tap the pencil to rename',
                  style: TextStyle(fontSize: 12, color: _muted)),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _sections.isEmpty
                      ? _buildEmptyState()
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                          itemCount: _sections.length,
                          onReorder: _onReorder,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (w, i, a) => Material(
                              color: Colors.transparent,
                              elevation: 6,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(14),
                              child: w),
                          itemBuilder: (context, index) =>
                              _sectionRow(index, _sections[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: _surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _accent)),
      );

  Widget _sectionRow(int index, dynamic section) {
    final bool isSystem = (section['is_system'] ?? 0) == 1;
    final bool isInServer = section['server_id'] != null;
    final bool isEditable = !isSystem || !isInServer;
    final name = section['name'].toString();
    final hue = (name.hashCode % 360).abs();
    final count = _counts[name] ?? 0;
    final renaming = _renamingId == section['id'];
    final dot = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: HSLColor.fromAHSL(1, hue.toDouble(), 0.42, 0.44).toColor(),
          borderRadius: BorderRadius.circular(10)),
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontFamily: 'SpaceGrotesk',
              color: Colors.white, fontWeight: FontWeight.w600)),
    );
    return Container(
      key: ValueKey(section['id']),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          if (renaming)
            const SizedBox(width: 8)
          else
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Drag to reorder $name',
                child: const SizedBox(
                  width: 34,
                  height: 40,
                  child: Icon(Icons.drag_indicator_rounded,
                      color: _muted, size: 20),
                ),
              ),
            ),
          dot,
          const SizedBox(width: 12),
          Expanded(
            child: renaming
                ? TextField(
                    controller: _renameCtl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saveRename(section),
                    decoration: _fieldDecoration('Section name').copyWith(
                        fillColor: _surface2,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: const BorderSide(color: _accent))),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _fg)),
                      Text('$count recipe${count == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          if (renaming) ...[
            _sqBtn(Icons.check_rounded, () => _saveRename(section),
                label: 'Save name', ok: true),
            const SizedBox(width: 6),
            _sqBtn(Icons.close_rounded,
                () => setState(() => _renamingId = null),
                label: 'Cancel'),
          ] else if (isEditable) ...[
            _sqBtn(Icons.edit_outlined, () => _startRename(section),
                label: 'Rename $name'),
            const SizedBox(width: 6),
            _sqBtn(Icons.delete_outline_rounded,
                () => _deleteSection(section['id']),
                danger: true, label: 'Delete $name'),
          ] else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.lock_outline_rounded, size: 18, color: _muted),
            ),
        ],
      ),
    );
  }

  Widget _sqBtn(IconData icon, VoidCallback onTap,
      {bool danger = false, bool ok = false, String? label}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: ok ? _accent : _line)),
          child: Icon(icon,
              size: 16,
              color: danger
                  ? const Color(0xFFC0392B)
                  : (ok ? _accent : _muted)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.dashboard_customize_outlined,
              size: 64, color: _accentSoft),
          SizedBox(height: 14),
          Text('No sections yet',
              style: TextStyle(
                  color: _muted, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

const _bg = Color(0xFFFAF8F5);
const _surface = Color(0xFFFFFFFF);
const _surface2 = Color(0xFFF4EFE8);
const _fg = Color(0xFF1E1916);
const _muted = Color(0xFF6D625B);
const _line = Color(0xFFEAE3D9);
const _accent = Color(0xFFC84B31);
const _accentSoft = Color(0xFFFCEEE9);
