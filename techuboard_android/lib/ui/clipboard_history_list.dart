import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_localizations.dart';
import '../clipboard_manager.dart';
import '../features/history/history_feed_controller.dart';
import '../models.dart';
import '../sync_manager.dart';
import 'app_components.dart';

enum DeviceFilterMode {
  all,
  thisPhone,
  peer,
  noDevices,
}

class PaginatedClipboardHistoryList extends StatefulWidget {
  final void Function(HistoryEntry entry)? onFileTap;
  final HistoryFeedController? controller;
  final DeviceFilterMode deviceFilter;
  final DiscoveredPeer? selectedPeer;
  final VoidCallback? onReturnToAll;
  final VoidCallback? onOpenDevicesTab;

  const PaginatedClipboardHistoryList({
    super.key,
    this.onFileTap,
    this.controller,
    this.deviceFilter = DeviceFilterMode.all,
    this.selectedPeer,
    this.onReturnToAll,
    this.onOpenDevicesTab,
  });

  @override
  State<PaginatedClipboardHistoryList> createState() =>
      _PaginatedClipboardHistoryListState();
}

class _PaginatedClipboardHistoryListState
    extends State<PaginatedClipboardHistoryList> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  late final HistoryFeedController _feed;
  Timer? _refreshTimer;
  Timer? _searchTimer;
  Timer? _copiedTimer;
  HistoryEntry? _copied;
  bool _isSelectMode = false;
  final Set<HistoryEntry> _selectedEntries = {};

  @override
  void initState() {
    super.initState();
    _feed =
        widget.controller ??
        HistoryFeedController(ClipboardManager.instance.fetchPage);
    _feed.addListener(_changed);
    if (_feed.entries.isEmpty) unawaited(_feed.refresh());
    _scrollController.addListener(_onScroll);
    if (widget.controller == null) {
      ClipboardManager.instance.addListener(_refreshFromDb);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // Small windows / large screens can fit an entire page without scrolling.
    // Continue only while content does not fill the viewport.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _scrollController.hasClients &&
          !_feed.failed &&
          _scrollController.position.maxScrollExtent == 0 &&
          _feed.hasMore &&
          !_feed.loading) {
        unawaited(_feed.loadMore());
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      ClipboardManager.instance.removeListener(_refreshFromDb);
    }
    _feed.removeListener(_changed);
    if (widget.controller == null) _feed.dispose();
    _refreshTimer?.cancel();
    _searchTimer?.cancel();
    _copiedTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshFromDb() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(milliseconds: 300),
      () => _feed.refresh(),
    );
  }

  List<HistoryEntry> get _filteredEntries {
    final entries = _feed.entries;
    switch (widget.deviceFilter) {
      case DeviceFilterMode.all:
        return entries;
      case DeviceFilterMode.thisPhone:
        final peers = SyncManager.instance.availablePeers;
        return entries.where((e) {
          final app = e.sourceApp ?? '';
          return app != 'Remote Sync' &&
              app != 'Mac' &&
              app != 'Windows' &&
              !peers.any((p) => p.displayName == app);
        }).toList();
      case DeviceFilterMode.peer:
        final peerName = widget.selectedPeer?.displayName.toLowerCase() ?? '';
        return entries.where((e) {
          final app = (e.sourceApp ?? '').toLowerCase();
          return app == 'remote sync' || (peerName.isNotEmpty && app.contains(peerName));
        }).toList();
      case DeviceFilterMode.noDevices:
        return const [];
    }
  }

  void _toggleSelectAll() {
    final visible = _filteredEntries;
    setState(() {
      if (_selectedEntries.length == visible.length && visible.isNotEmpty) {
        _selectedEntries.clear();
      } else {
        _selectedEntries.addAll(visible);
      }
    });
  }

  Future<void> _confirmDeleteSingle(HistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 36),
        title: const Text('Delete Clipboard Item?'),
        content: const Text(
          'Are you sure you want to delete this clipboard item? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ClipboardManager.instance.deleteEntry(entry);
      setState(() => _selectedEntries.remove(entry));
      if (mounted) showTechuMessage(context, 'Item deleted');
      _feed.refresh();
    }
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedEntries.isEmpty) return;
    final count = _selectedEntries.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 36),
        title: Text('Delete $count Selected Item${count > 1 ? "s" : ""}?'),
        content: Text(
          'Are you sure you want to delete $count selected items from clipboard history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ClipboardManager.instance.deleteEntries(_selectedEntries.toList());
      setState(() {
        _selectedEntries.clear();
        _isSelectMode = false;
      });
      if (mounted) showTechuMessage(context, '$count items deleted');
      _feed.refresh();
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 36),
        title: const Text('Clear All History?'),
        content: const Text(
          'Are you sure you want to clear all unpinned clipboard history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ClipboardManager.instance.clearHistory();
      setState(() {
        _selectedEntries.clear();
        _isSelectMode = false;
      });
      if (mounted) showTechuMessage(context, 'History cleared');
      _feed.refresh();
    }
  }

  Widget _buildSelectionActionBar(ColorScheme colors, bool isDark) {
    final visible = _filteredEntries;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2633) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 0.8),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _toggleSelectAll,
            child: Row(
              children: [
                Icon(
                  _selectedEntries.length == visible.length && visible.isNotEmpty
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _selectedEntries.length == visible.length && visible.isNotEmpty
                      ? 'Deselect All'
                      : 'Select All',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${_selectedEntries.length})',
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          if (_selectedEntries.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: _confirmDeleteSelected,
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: Text(
                'Delete (${_selectedEntries.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent.withOpacity(0.85),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: _confirmClearAll,
            child: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDeviceView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.portable_wifi_off_rounded,
                size: 38,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Device Connected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Connect with your Mac or PC to sync clips instantly:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.onOpenDevicesTab?.call(),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B2330) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(Icons.laptop_mac_rounded, size: 22, color: Colors.green),
                              Icon(Icons.arrow_forward_ios_rounded, size: 11, color: colors.onSurfaceVariant),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'MacBook / Mac',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Scan QR code or enter PIN to sync',
                            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.onOpenDevicesTab?.call(),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B2330) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(Icons.laptop_windows_rounded, size: 22, color: Colors.blue),
                              Icon(Icons.arrow_forward_ios_rounded, size: 11, color: colors.onSurfaceVariant),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Windows / PC',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Connect via LAN or Relay PIN',
                            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => widget.onReturnToAll?.call(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Return to All History'),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color})? _getBadgeInfo(HistoryEntry entry) {
    if (entry.item.type == 'image') {
      return (label: 'Image', color: const Color(0xFF38BDF8));
    }
    final text = entry.item.title;
    for (final unit in text.codeUnits) {
      if (unit >= 0x0980 && unit <= 0x09FF) {
        return (label: 'TechuAvro', color: const Color(0xFF22C55E));
      }
    }
    if (text.startsWith('http://') || text.startsWith('https://')) {
      return (label: 'URL', color: const Color(0xFFA855F7));
    }
    if (text.contains('=') ||
        text.contains('function ') ||
        text.contains('var ') ||
        text.contains('let ') ||
        text.contains('const ') ||
        text.contains('{') ||
        text.contains('def ') ||
        text.contains('class ')) {
      return (label: 'Code', color: const Color(0xFFF97316));
    }
    return null;
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 240 && !_feed.failed) {
      unawaited(_feed.loadMore());
    }
  }

  void _search({String? filter}) {
    _searchTimer?.cancel();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_feed.search(_searchController.text, filter ?? _feed.filter));
  }

  Future<void> _copy(HistoryEntry entry) async {
    try {
      await ClipboardManager.instance.copyToClipboard(entry.item);
      if (!mounted) return;
      unawaited(HapticFeedback.selectionClick());
      setState(() => _copied = entry);
      showTechuMessage(context, context.l10n.copiedToClipboard);
      _copiedTimer?.cancel();
      _copiedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = null);
      });
    } catch (_) {
      if (mounted) showTechuMessage(context, context.l10n.operationFailed);
    }
  }

  Future<void> _send(String text) async {
    final l10n = context.l10n;
    final peers = SyncManager.instance.availablePeers;
    if (peers.isEmpty) {
      showTechuMessage(context, l10n.noDevicesFound);
      return;
    }
    final peer = await showModalBottomSheet<DiscoveredPeer>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .65,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  l10n.sendText,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...peers.map(
                (p) => ListTile(
                  leading: const TechuIcon(Icons.devices_rounded),
                  title: Text(p.displayName),
                  subtitle: Text(p.host),
                  onTap: () => Navigator.pop(sheetContext, p),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (peer == null || !mounted) return;
    try {
      final success = await SyncManager.instance.sendTextToPeer(
        text,
        peerId: peer.peerId,
      );
      if (mounted) {
        showTechuMessage(
          context,
          success ? l10n.textSentTo(peer.displayName) : l10n.sendFailed,
        );
      }
    } catch (_) {
      if (mounted) showTechuMessage(context, l10n.sendFailed);
    }
  }

  Future<void> _sendFile(File file) async {
    final l10n = context.l10n;
    final peers = SyncManager.instance.availablePeers;
    if (peers.isEmpty) {
      showTechuMessage(context, l10n.noDevicesFound);
      return;
    }
    final peer = await showModalBottomSheet<DiscoveredPeer>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .65,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Send File to Device',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...peers.map(
                (p) => ListTile(
                  leading: const TechuIcon(Icons.devices_rounded),
                  title: Text(p.displayName),
                  subtitle: Text(p.host),
                  onTap: () => Navigator.pop(sheetContext, p),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (peer == null || !mounted) return;
    try {
      final success = await SyncManager.instance.sendFileToPeer(
        file,
        peerId: peer.peerId,
      );
      if (mounted) {
        showTechuMessage(
          context,
          success ? 'Sending to ${peer.displayName}...' : l10n.sendFailed,
        );
      }
    } catch (_) {
      if (mounted) showTechuMessage(context, l10n.sendFailed);
    }
  }

  Future<void> _preview(HistoryEntry entry) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.preview,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: entry.item.type == 'image'
                      ? Image.file(
                          File(entry.item.value as String),
                          errorBuilder: (_, __, ___) =>
                              Text(context.l10n.fileNotFound),
                        )
                      : SelectableText(
                          entry.item.type == 'fileURLs'
                              ? (entry.item.value as List<String>).join('\n')
                              : entry.item.value.toString(),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (entry.item.type == 'text' || Platform.isWindows)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _copy(entry);
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(context.l10n.copyContent),
                    ),
                  if (entry.item.type == 'text')
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _send(entry.item.value.toString());
                      },
                      icon: const Icon(Icons.send_outlined),
                      label: Text(context.l10n.send),
                    ),
                  if (entry.item.type == 'image' || entry.item.type == 'fileURL')
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _sendFile(File(entry.item.value.toString()));
                      },
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Send to Device'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return context.l10n.today;
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return context.l10n.yesterday;
    }
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.searchHistory,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.clearSearch,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _search();
                      },
                    ),
            ),
            onSubmitted: (_) => _search(),
            onChanged: (_) {
              setState(() {});
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 250), _search);
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              for (final filter in [
                ('all', l10n.allItems),
                ('text', l10n.textItems),
                ('links', l10n.linkItems),
                ('files', l10n.fileItems),
                ('images', l10n.imageItems),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter.$2),
                    selected: _feed.filter == filter.$1,
                    onSelected: (_) => _search(filter: filter.$1),
                    showCheckmark: false,
                  ),
                ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  setState(() {
                    _isSelectMode = !_isSelectMode;
                    if (!_isSelectMode) _selectedEntries.clear();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _isSelectMode
                        ? colors.primary.withOpacity(0.18)
                        : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isSelectMode
                          ? colors.primary.withOpacity(0.6)
                          : (isDark ? Colors.white12 : Colors.black12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSelectMode ? Icons.check_circle_rounded : Icons.checklist_rounded,
                        size: 14,
                        color: _isSelectMode ? colors.primary : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isSelectMode ? 'Done' : 'Select',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isSelectMode ? colors.primary : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.deviceFilter == DeviceFilterMode.noDevices)
          Expanded(child: _buildNoDeviceView(context))
        else ...[
          if (_isSelectMode) _buildSelectionActionBar(colors, isDark),
          Expanded(
            child: () {
              final visibleEntries = _filteredEntries;
              if (visibleEntries.isEmpty) {
                return _feed.loading
                    ? const Center(child: CircularProgressIndicator())
                    : TechuEmptyState(
                        icon: _feed.failed
                            ? Icons.cloud_off_rounded
                            : (_feed.query.isNotEmpty || _feed.filter != 'all'
                                  ? Icons.search_off_rounded
                                  : Icons.content_paste_rounded),
                        title: _feed.failed
                            ? l10n.loadFailed
                            : (_feed.query.isNotEmpty || _feed.filter != 'all'
                                  ? l10n.nothingFound
                                  : l10n.noClipboardHistory),
                        message: _feed.failed
                            ? l10n.retryHint
                            : (_feed.query.isNotEmpty || _feed.filter != 'all'
                                  ? l10n.changeSearchHint
                                  : Platform.isIOS
                                  ? l10n.iosHistoryEmptyHint
                                  : l10n.historyEmptyHint),
                        action: _feed.failed
                            ? FilledButton(
                                onPressed: _feed.refresh,
                                child: Text(l10n.retry),
                              )
                            : null,
                      );
              }

              return RefreshIndicator(
                onRefresh: _feed.refresh,
                child: ListView.builder(
                  key: const PageStorageKey('clipboard-history'),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: visibleEntries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == visibleEntries.length) {
                      if (_feed.failed) {
                        return Center(
                          child: TextButton(
                            onPressed: _feed.refresh,
                            child: Text(l10n.retry),
                          ),
                        );
                      }
                      return _feed.loading
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : const SizedBox(height: 8);
                    }
                    final entry = visibleEntries[index];
                    final isFile =
                        entry.item.type == 'fileURL' ||
                        entry.item.type == 'fileURLs';
                    final isText = entry.item.type == 'text';
                    final uri = isText
                        ? Uri.tryParse(entry.item.value.toString().trim())
                        : null;
                    final isLink =
                        uri?.scheme == 'http' || uri?.scheme == 'https';
                    final icon = isFile
                        ? Icons.description_outlined
                        : isLink
                        ? Icons.link_rounded
                        : isText
                        ? Icons.notes_rounded
                        : Icons.image_outlined;
                    final label = _dateLabel(entry.date);
                    final showDate =
                        index == 0 ||
                        _dateLabel(visibleEntries[index - 1].date) != label;
                    final title = entry.item.title;
                    final isSelected = _selectedEntries.contains(entry);

                    final badge = _getBadgeInfo(entry);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                            child: Text(
                              label,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Card(
                            elevation: 0.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                                width: 0.8,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                if (_isSelectMode) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedEntries.remove(entry);
                                    } else {
                                      _selectedEntries.add(entry);
                                    }
                                  });
                                } else if (isFile) {
                                  widget.onFileTap?.call(entry);
                                } else if (isText) {
                                  _copy(entry);
                                } else {
                                  _preview(entry);
                                }
                              },
                              onLongPress: () {
                                if (_isSelectMode) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedEntries.remove(entry);
                                    } else {
                                      _selectedEntries.add(entry);
                                    }
                                  });
                                } else {
                                  _preview(entry);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    if (_isSelectMode) ...[
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons.circle_outlined,
                                        size: 20,
                                        color: isSelected
                                            ? colors.primary
                                            : colors.onSurfaceVariant.withOpacity(0.4),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    if (entry.item.type == 'image') ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 44,
                                          height: 32,
                                          child: Image.file(
                                            File(entry.item.value.toString()),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: colors.surfaceContainerHighest,
                                              child: const Icon(Icons.image_outlined, size: 18),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ] else ...[
                                      Icon(
                                        icon,
                                        size: 18,
                                        color: isLink
                                            ? Colors.purpleAccent
                                            : colors.primary,
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              if (badge != null) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  margin: const EdgeInsets.only(right: 6),
                                                  decoration: BoxDecoration(
                                                    color: badge.color.withOpacity(0.14),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    badge.label,
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: badge.color,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Text(
                                                entry.sourceApp ?? 'Techuboard',
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: colors.onSurfaceVariant,
                                                  fontSize: 10,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text('·', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10)),
                                              const SizedBox(width: 5),
                                              Text(
                                                MaterialLocalizations.of(context).formatTimeOfDay(
                                                  TimeOfDay.fromDateTime(entry.date),
                                                ),
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: colors.onSurfaceVariant,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isSelectMode) ...[
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _copy(entry),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          child: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 180),
                                            child: Icon(
                                              _copied == entry ? Icons.check_rounded : Icons.copy_rounded,
                                              key: ValueKey(_copied == entry),
                                              size: 17,
                                              color: colors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _confirmDeleteSingle(entry),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          child: Icon(
                                            Icons.delete_outline_rounded,
                                            size: 17,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            }(),
          ),
        ],
      ],
    );
  }
}

class MacHistoryTab extends StatelessWidget {
  const MacHistoryTab({super.key});
  @override
  Widget build(BuildContext context) => const PaginatedClipboardHistoryList();
}
