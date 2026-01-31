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

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() => _isLoading = true);
    try {
      final localSections = await DatabaseHelper().getLocalSections();
      setState(() {
        _sections = localSections;
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
              _sections = refreshedLocal;
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

  Future<void> _addSection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Section'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: 'Section Name (e.g. Italian)'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name != null) {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return;

      // Duplicate Check
      final exists = _sections.any((s) =>
          s['name'].toString().toLowerCase() == trimmedName.toLowerCase());

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('A section with this name already exists.')),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      // Save locally first
      await DatabaseHelper().saveLocalSection({
        'name': trimmedName,
        'server_id': null, // Local draft
        'is_system': 0,
        'icon': 'category',
        'sort_order': _sections.length,
        'created_at': DateTime.now().toIso8601String()
      });

      // Background sync to API
      _apiService.createSection(trimmedName).catchError((_) => null);

      _loadSections();
    }
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

  Future<void> _editSection(int id, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Section'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Section Name'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null) {
      final trimmedName = newName.trim();
      if (trimmedName.isEmpty || trimmedName == currentName) return;

      // Duplicate Check
      final exists = _sections.any((s) =>
          s['id'] != id &&
          s['name'].toString().toLowerCase() == trimmedName.toLowerCase());

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('A section with this name already exists.')),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      // Update locally first
      await DatabaseHelper().updateLocalSection(id, trimmedName);

      // Background sync to API
      _apiService.updateSection(id, trimmedName).catchError((_) => null);

      _loadSections();
    }
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Arrange Categories',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE74C3C)))
          : _sections.isEmpty
              ? _buildEmptyState()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _sections.length,
                  onReorder: _onReorder,
                  proxyDecorator: (widget, index, animation) {
                    return Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      child: widget,
                    );
                  },
                  itemBuilder: (context, index) {
                    final section = _sections[index];
                    final bool isSystem = (section['is_system'] ?? 0) == 1;
                    final bool isInServer = section['server_id'] != null;
                    final bool isEditable = !isSystem || !isInServer;

                    return Container(
                      key: ValueKey(section['id']),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSystem
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isSystem
                                ? Icons.dashboard_customize_rounded
                                : Icons.category_rounded,
                            color: isSystem
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFF97316),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          section['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            isSystem
                                ? 'Global Category'
                                : (!isInServer
                                    ? 'Local Draft'
                                    : 'Personal Category'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isEditable) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_rounded,
                                    size: 20, color: Color(0xFF64748B)),
                                onPressed: () => _editSection(
                                    section['id'], section['name']),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20, color: Color(0xFFE74C3C)),
                                onPressed: () => _deleteSection(section['id']),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                              ),
                            ] else
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.lock_outline_rounded,
                                    size: 18, color: Color(0xFF94A3B8)),
                              ),
                            const SizedBox(width: 8),
                            const Icon(Icons.drag_indicator_rounded,
                                color: Color(0xFFCBD5E1)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSection,
        label: const Text('NEW CATEGORY',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        icon: const Icon(Icons.add_rounded),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 4,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear_rounded,
              size: 80, color: Colors.grey.shade200),
          const SizedBox(height: 20),
          const Text('No categories yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('Create your first category to start organizing.',
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
