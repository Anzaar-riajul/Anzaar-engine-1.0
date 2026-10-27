import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../database/snippet_repository.dart';
import '../../models.dart';
import '../../sync_manager.dart';

class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key});

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<SnippetFolderItem> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSnippets();
    SnippetRepository.instance.onSnippetsChanged.listen((updated) {
      if (mounted) {
        setState(() {
          _folders = updated;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSnippets() async {
    final list = await SnippetRepository.instance.fetchAllFolders();
    if (mounted) {
      setState(() {
        _folders = list;
        _isLoading = false;
      });
    }
  }

  String _selectedDeviceFilter = 'all';
  bool _isSyncing = false;

  Future<void> _syncNotesNow() async {
    setState(() => _isSyncing = true);
    try {
      await SyncManager.instance.requestSnippetsFetch();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _loadSnippets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Notes synchronized with connected devices!'),
              ],
            ),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _isSyncing = false);
  }

  List<SnippetFolderItem> get _filteredFolders {
    var list = _folders;

    if (_selectedDeviceFilter != 'all') {
      if (_selectedDeviceFilter == 'this_device') {
        list = list.where((f) {
          final d = (f.deviceName ?? '').toLowerCase();
          return d.isEmpty || d.contains('this') || d.contains('phone') || d.contains('android') || d == 'local';
        }).toList();
      } else if (_selectedDeviceFilter == 'mac') {
        list = list.where((f) {
          final d = (f.deviceName ?? '').toLowerCase();
          return d.contains('mac') || d.contains('desktop') || d.contains('laptop') || d.contains('apple');
        }).toList();
      } else {
        list = list.where((f) => (f.deviceName ?? '').toLowerCase() == _selectedDeviceFilter).toList();
      }
    }

    if (_searchQuery.trim().isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    final result = <SnippetFolderItem>[];
    for (final folder in list) {
      final matchesFolder = folder.title.toLowerCase().contains(q);
      final matchingSnippets = folder.snippets.where((s) {
        return s.title.toLowerCase().contains(q) ||
            s.content.toLowerCase().contains(q);
      }).toList();

      if (matchesFolder || matchingSnippets.isNotEmpty) {
        result.add(
          folder.copyWith(
            snippets: matchesFolder ? folder.snippets : matchingSnippets,
          ),
        );
      }
    }
    return result;
  }

  void _showCreateOrEditFolderDialog([SnippetFolderItem? folder]) {
    final isEditing = folder != null;
    final controller = TextEditingController(text: folder?.title ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditing ? 'Edit Folder' : 'New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder Name (e.g. Work, Personal)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(ctx);

              final now = DateTime.now().millisecondsSinceEpoch;
              if (isEditing) {
                await SnippetRepository.instance.saveFolder(
                  folder.copyWith(title: title, updatedAt: now),
                );
              } else {
                final newFolder = SnippetFolderItem(
                  id: const Uuid().v4(),
                  title: title,
                  updatedAt: now,
                  sortOrder: _folders.length,
                );
                await SnippetRepository.instance.saveFolder(newFolder);
              }
            },
            child: Text(isEditing ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateOrEditSnippetDialog(
    String folderId, [
    SnippetItem? snippet,
  ]) {
    final isEditing = snippet != null;
    final titleController = TextEditingController(text: snippet?.title ?? '');
    final contentController =
        TextEditingController(text: snippet?.content ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? 'Edit Note' : 'New Note',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title / Label',
                hintText: 'e.g. Email signature, Home address',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Note Content',
                hintText: 'Content to paste when tapped',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded),
              label: Text(isEditing ? 'Save Note' : 'Add Note'),
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text;
                if (title.isEmpty || content.isEmpty) return;
                Navigator.pop(ctx);

                final now = DateTime.now().millisecondsSinceEpoch;
                if (isEditing) {
                  await SnippetRepository.instance.saveSnippet(
                    snippet.copyWith(
                      title: title,
                      content: content,
                      updatedAt: now,
                    ),
                  );
                } else {
                  final newSnippet = SnippetItem(
                    id: const Uuid().v4(),
                    folderId: folderId,
                    title: title,
                    content: content,
                    updatedAt: now,
                  );
                  await SnippetRepository.instance.saveSnippet(newSnippet);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _copySnippet(SnippetItem snippet) {
    Clipboard.setData(ClipboardData(text: snippet.content));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${snippet.title}" to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildDeviceTabChip(String key, String label, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    final isSelected = _selectedDeviceFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedDeviceFilter = key),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withOpacity(0.18)
              : colors.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colors.primary.withOpacity(0.6)
                : colors.outlineVariant.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayFolders = _filteredFolders;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateOrEditFolderDialog(),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New Folder'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      controller: _searchController,
                      hintText: 'Search notes...',
                      leading: const Icon(Icons.search_rounded),
                      trailing: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                      ],
                      onChanged: (val) => setState(() => _searchQuery = val),
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor:
                          WidgetStatePropertyAll(colors.surfaceContainerLow),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _isSyncing ? null : _syncNotesNow,
                    tooltip: 'Sync Notes with Mac',
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              height: 42,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildDeviceTabChip('all', 'All Notes', Icons.folder_copy_outlined),
                  const SizedBox(width: 8),
                  _buildDeviceTabChip('mac', 'Mac', Icons.laptop_mac_rounded),
                  const SizedBox(width: 8),
                  _buildDeviceTabChip('this_device', 'This Device', Icons.smartphone_rounded),
                ],
              ),
            ),
          ),
          if (displayFolders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.note_alt_rounded,
                        size: 64,
                        color: colors.primary.withAlpha(128),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No notes yet'
                            : 'No matching notes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Create folders and notes here or sync from your Mac.'
                            : 'Try searching with another keyword.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final folder = displayFolders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: colors.surfaceContainerLow,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          leading: Icon(
                            folder.isEnabled
                                ? Icons.folder_rounded
                                : Icons.folder_off_rounded,
                            color: folder.isEnabled
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          title: Text(
                            folder.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: folder.isEnabled
                                  ? colors.onSurface
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.scale(
                                scale: 0.8,
                                child: Switch(
                                  value: folder.isEnabled,
                                  onChanged: (val) {
                                    SnippetRepository.instance.saveFolder(
                                      folder.copyWith(
                                        isEnabled: val,
                                        updatedAt: DateTime.now()
                                            .millisecondsSinceEpoch,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded),
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _showCreateOrEditFolderDialog(folder);
                                  } else if (action == 'delete') {
                                    SnippetRepository.instance
                                        .deleteFolder(folder.id);
                                  } else if (action == 'add_snippet') {
                                    _showCreateOrEditSnippetDialog(folder.id);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'add_snippet',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text('Add Note'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text('Rename Folder'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Delete Folder',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          children: [
                            if (folder.snippets.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'No notes in this folder',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Add Note'),
                                      onPressed: () =>
                                          _showCreateOrEditSnippetDialog(
                                        folder.id,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              for (final snippet in folder.snippets)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 2,
                                  ),
                                  leading: Container(
                                    width: 3.5,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  title: Text(
                                    snippet.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    snippet.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => _showCreateOrEditSnippetDialog(folder.id, snippet),
                                        child: Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Icon(
                                            Icons.edit_rounded,
                                            size: 16,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => SnippetRepository.instance.deleteSnippet(snippet.id),
                                        child: Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 16,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _copySnippet(snippet),
                                  onLongPress: () {
                                    showModalBottomSheet<void>(
                                      context: context,
                                      builder: (ctx) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(
                                                Icons.edit_rounded,
                                              ),
                                              title: const Text('Edit Note'),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                _showCreateOrEditSnippetDialog(
                                                  folder.id,
                                                  snippet,
                                                );
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.red,
                                              ),
                                              title: const Text(
                                                'Delete Note',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                SnippetRepository.instance
                                                    .deleteSnippet(snippet.id);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 8,
                                  left: 12,
                                ),
                                child: TextButton.icon(
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Add Note'),
                                  onPressed: () =>
                                      _showCreateOrEditSnippetDialog(folder.id),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: displayFolders.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
