import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../controllers/noterr_controller.dart';
import '../models/note.dart';
import '../services/sticky_window_service.dart';
import 'note_colors.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.controller});

  final NoterrController controller;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WindowListener, TrayListener {
  final _quickText = TextEditingController();
  NoteType _quickType = NoteType.checklist;
  bool _allowClose = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      unawaited(_initDesktopShell());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.ensureTodayTodoNote();
    });
  }

  @override
  void dispose() {
    _quickText.dispose();
    if (_isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _initDesktopShell() async {
    try {
      await windowManager.setPreventClose(true);
      await trayManager.setIcon('windows/runner/resources/app_icon.ico');
      await trayManager.setToolTip('Noterr');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show_window', label: 'Open Noterr'),
            MenuItem.separator(),
            MenuItem(key: 'exit_app', label: 'Exit Noterr'),
          ],
        ),
      );
    } catch (_) {
      // Desktop shell plugins are unavailable in widget tests.
    }
  }

  @override
  void onWindowClose() {
    if (_allowClose) {
      windowManager.destroy();
      return;
    }
    unawaited(_hideToTray());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showFromTray());
      case 'exit_app':
        unawaited(_exitApp());
    }
  }

  Future<void> _hideToTray() async {
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } catch (_) {}
  }

  Future<void> _showFromTray() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _exitApp() async {
    _allowClose = true;
    try {
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      await StickyWindowService.instance.closeAll();
      await windowManager.destroy();
    } catch (_) {}
  }

  Future<void> _createQuickItem() async {
    final text = _quickText.text.trim();
    if (text.isEmpty && _quickType == NoteType.note) return;
    _quickText.clear();

    if (_quickType == NoteType.checklist) {
      if (text.isEmpty) {
        final note = await widget.controller.ensureTodayTodoNote();
        _openItem(note);
        return;
      }
      await widget.controller.addTodayTask(text);
      return;
    }

    await widget.controller.addTodayNote(text);
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HistoryScreen(controller: widget.controller),
      ),
    );
  }

  void _openItem(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ItemDetailScreen(
          controller: widget.controller,
          noteId: note.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final items = widget.controller.workspaceItems;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Noterr'),
            actions: [
              _SyncChip(controller: widget.controller),
              IconButton(
                tooltip: 'Sync now',
                onPressed: widget.controller.syncNow,
                icon: const Icon(Icons.sync),
              ),
              IconButton(
                tooltip: 'History',
                onPressed: _openHistory,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Lock notes',
                onPressed: widget.controller.lock,
                icon: const Icon(Icons.lock_outline),
              ),
              if (_isDesktop)
                IconButton(
                  tooltip: 'Exit Noterr',
                  onPressed: _exitApp,
                  icon: const Icon(Icons.power_settings_new),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _QuickCreateBar(
                  controller: _quickText,
                  type: _quickType,
                  onTypeChanged: (type) => setState(() => _quickType = type),
                  onCreate: _createQuickItem,
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Add a note or checklist.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final note = items[index];
                            return _ItemCard(
                              key: ValueKey(note.id),
                              note: note,
                              controller: widget.controller,
                              onOpen: () => _openItem(note),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickCreateBar extends StatelessWidget {
  const _QuickCreateBar({
    required this.controller,
    required this.type,
    required this.onTypeChanged,
    required this.onCreate,
  });

  final TextEditingController controller;
  final NoteType type;
  final ValueChanged<NoteType> onTypeChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<NoteType>(
                    segments: const [
                      ButtonSegment(
                        value: NoteType.checklist,
                        icon: Icon(Icons.checklist),
                        label: Text('Task'),
                      ),
                      ButtonSegment(
                        value: NoteType.note,
                        icon: Icon(Icons.sticky_note_2_outlined),
                        label: Text('Note'),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (selected) =>
                        onTypeChanged(selected.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onCreate(),
              decoration: InputDecoration(
                hintText: type == NoteType.checklist
                    ? 'Add a task and press Enter'
                    : 'Add a note to today and press Enter',
                prefixIcon: Icon(
                  type == NoteType.checklist
                      ? Icons.add_task
                      : Icons.note_add_outlined,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Add',
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.note,
    required this.controller,
    required this.onOpen,
  });

  final Note note;
  final NoterrController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final activeCount = note.checklist.where((item) => !item.done).length;
    final doneCount = note.checklist.length - activeCount;
    return Material(
      color: noteColor(note.colorHex).withValues(alpha: note.opacity),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    note.type == NoteType.full
                        ? Icons.today_outlined
                        : note.type == NoteType.checklist
                            ? Icons.checklist
                            : Icons.sticky_note_2_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Show as desktop sticky',
                    onPressed: () => StickyWindowService.instance.show(note),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  PopupMenuButton<_CardAction>(
                    tooltip: 'More',
                    onSelected: (action) {
                      switch (action) {
                        case _CardAction.archive:
                          controller.archiveNote(note, true);
                        case _CardAction.delete:
                          controller.softDeleteNote(note);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _CardAction.archive,
                        child: ListTile(
                          leading: Icon(Icons.archive_outlined),
                          title: Text('Archive'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: _CardAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('$activeCount left, $doneCount done'),
              if (note.preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note.preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (note.showOnMobileWidget)
                    const Chip(
                      avatar: Icon(Icons.phone_android, size: 16),
                      label: Text('Widget'),
                    ),
                  if (note.popOnDesktop)
                    const Chip(
                      avatar: Icon(Icons.desktop_windows, size: 16),
                      label: Text('Desktop'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CardAction { archive, delete }

class _ItemDetailScreen extends StatelessWidget {
  const _ItemDetailScreen({
    required this.controller,
    required this.noteId,
  });

  final NoterrController controller;
  final String noteId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final note =
            controller.notes.where((item) => item.id == noteId).firstOrNull;
        if (note == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Noterr')),
            body: const Center(child: Text('This item is no longer here.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(note.isArchived ? note.title : 'Today'),
            actions: [
              IconButton(
                tooltip: 'Show as desktop sticky',
                onPressed: () => StickyWindowService.instance.show(note),
                icon: const Icon(Icons.open_in_new),
              ),
              IconButton(
                tooltip: note.isArchived ? 'Unarchive' : 'Archive',
                onPressed: () => controller.archiveNote(note, !note.isArchived),
                icon: Icon(
                  note.isArchived ? Icons.unarchive : Icons.archive_outlined,
                ),
              ),
            ],
          ),
          body: _ItemEditor(controller: controller, note: note),
        );
      },
    );
  }
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.controller,
    required this.note,
  });

  final NoterrController controller;
  final Note note;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final Map<String, FocusNode> _focusNodes = {};
  String? _pendingFocusId;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
  }

  @override
  void didUpdateWidget(covariant _ItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _title.text = widget.note.title;
      _body.text = widget.note.body;
      return;
    }
    if (_title.text != widget.note.title) _title.text = widget.note.title;
    if (_body.text != widget.note.body) _body.text = widget.note.body;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _addChecklistItem([ChecklistItem? after]) async {
    final next = after == null
        ? await widget.controller.addChecklistItem(widget.note)
        : await widget.controller.addChecklistItemAfter(widget.note, after);
    setState(() => _pendingFocusId = next.id);
  }

  FocusNode _focusNodeFor(ChecklistItem item) {
    final node = _focusNodes.putIfAbsent(item.id, FocusNode.new);
    if (_pendingFocusId == item.id) {
      _pendingFocusId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
    return node;
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Material(
          color: noteColor(note.colorHex).withValues(alpha: note.opacity),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _title,
                  onChanged: (value) =>
                      widget.controller.updateNote(note.copyWith(title: value)),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Title',
                  ),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (note.supportsBody)
                  TextField(
                    controller: _body,
                    onChanged: (value) => widget.controller.updateNote(
                      note.copyWith(body: value),
                    ),
                    minLines: note.supportsChecklist ? 4 : 8,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Today notes',
                    ),
                  ),
                if (note.supportsChecklist) ...[
                  const SizedBox(height: 8),
                  if (note.checklist.isEmpty)
                    FilledButton.icon(
                      onPressed: () => _addChecklistItem(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add first task'),
                    )
                  else
                    ...note.checklist.map(
                      (item) => _ChecklistRow(
                        key: ValueKey(item.id),
                        item: item,
                        focusNode: _focusNodeFor(item),
                        onToggle: () => widget.controller.toggleChecklistItem(
                          note,
                          item,
                        ),
                        onText: (text) => widget.controller.updateChecklistItem(
                          note,
                          item,
                          text,
                        ),
                        onEnter: () => _addChecklistItem(item),
                        onRemove: () =>
                            widget.controller.removeChecklistItem(note, item),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _addChecklistItem(),
                    icon: const Icon(Icons.add_task),
                    label: const Text('Add task'),
                  ),
                ],
                const SizedBox(height: 14),
                _ColorAndOpacity(
                  note: note,
                  onColor: (colorHex) => widget.controller.updateNote(
                    note.copyWith(colorHex: colorHex),
                  ),
                  onOpacity: (opacity) => widget.controller.updateNote(
                    note.copyWith(opacity: opacity),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Desktop sticky'),
                      avatar: const Icon(Icons.desktop_windows, size: 16),
                      selected: note.popOnDesktop,
                      onSelected: (value) => widget.controller.updateNote(
                        note.copyWith(popOnDesktop: value),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Mobile widget'),
                      avatar: const Icon(Icons.phone_android, size: 16),
                      selected: note.showOnMobileWidget,
                      onSelected: (value) => widget.controller.updateNote(
                        note.copyWith(showOnMobileWidget: value),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Always on top'),
                      avatar: const Icon(Icons.vertical_align_top, size: 16),
                      selected: note.isAlwaysOnTop,
                      onSelected: (value) => widget.controller.updateNote(
                        note.copyWith(isAlwaysOnTop: value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({
    super.key,
    required this.item,
    required this.focusNode,
    required this.onToggle,
    required this.onText,
    required this.onEnter,
    required this.onRemove,
  });

  final ChecklistItem item;
  final FocusNode focusNode;
  final VoidCallback onToggle;
  final ValueChanged<String> onText;
  final VoidCallback onEnter;
  final VoidCallback onRemove;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.item.text);
  }

  @override
  void didUpdateWidget(covariant _ChecklistRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _text.text = widget.item.text;
    } else if (!widget.focusNode.hasFocus && _text.text != widget.item.text) {
      _text.text = widget.item.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Checkbox(
                value: widget.item.done, onChanged: (_) => widget.onToggle()),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: widget.focusNode,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => widget.onEnter(),
                onChanged: widget.onText,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Task',
                ),
                style: TextStyle(
                  decoration:
                      widget.item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete task',
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorAndOpacity extends StatelessWidget {
  const _ColorAndOpacity({
    required this.note,
    required this.onColor,
    required this.onOpacity,
  });

  final Note note;
  final ValueChanged<String> onColor;
  final ValueChanged<double> onOpacity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: notePalette.take(8).map((hex) {
            return InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => onColor(hex),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: noteColor(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        note.colorHex == hex ? Colors.black87 : Colors.black26,
                    width: note.colorHex == hex ? 2 : 1,
                  ),
                ),
                child: const SizedBox.square(dimension: 24),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.opacity, size: 18),
            Expanded(
              child: Slider(
                value: note.opacity.clamp(0.45, 1),
                min: 0.45,
                max: 1,
                divisions: 11,
                onChanged: onOpacity,
              ),
            ),
            Text('${(note.opacity * 100).round()}%'),
          ],
        ),
      ],
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen({required this.controller});

  final NoterrController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final notes = controller.historyNotes;
        return Scaffold(
          appBar: AppBar(title: const Text('Last 30 Days')),
          body: notes.isEmpty
              ? const Center(child: Text('Nothing saved in the last 30 days.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    final date = note.updatedAt.toLocal();
                    return Material(
                      color: note.isDeleted
                          ? Theme.of(context).colorScheme.errorContainer
                          : noteColor(note.colorHex).withValues(
                              alpha: note.opacity,
                            ),
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        onTap: note.isDeleted
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _ItemDetailScreen(
                                      controller: controller,
                                      noteId: note.id,
                                    ),
                                  ),
                                ),
                        leading: Icon(
                          note.type == NoteType.full
                              ? Icons.today_outlined
                              : note.type == NoteType.checklist
                                  ? Icons.checklist
                                  : Icons.sticky_note_2_outlined,
                        ),
                        title: Text(
                          note.title.isEmpty ? 'Untitled' : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${note.preview}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.controller});

  final NoterrController controller;

  @override
  Widget build(BuildContext context) {
    final text = switch (controller.syncState) {
      SyncState.offline => 'Local',
      SyncState.idle => 'Synced',
      SyncState.syncing => 'Syncing',
      SyncState.error => 'Sync issue',
    };
    final icon = switch (controller.syncState) {
      SyncState.offline => Icons.cloud_off,
      SyncState.idle => Icons.cloud_done,
      SyncState.syncing => Icons.cloud_sync,
      SyncState.error => Icons.error_outline,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: controller.error ?? text,
        child: ActionChip(
          avatar: Icon(icon, size: 18),
          label: Text(text),
          onPressed: () => _showSyncDetails(context),
        ),
      ),
    );
  }

  void _showSyncDetails(BuildContext context) {
    final account = controller.syncAccountId;
    final error = controller.error;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sync status'),
          content: SelectableText(
            [
              'Mode: ${controller.hasCloud ? 'Cloud' : 'Local only'}',
              'State: ${controller.syncState.name}',
              'Account: ${account == null ? 'not signed in' : _short(account)}',
              'Device: ${_short(controller.deviceId)}',
              'Items here: ${controller.notes.length}',
              'Last pull count: ${controller.lastPulledCount}',
              'Last push count: ${controller.lastPushedCount}',
              'Last sync: ${_time(controller.lastSyncAt)}',
              'Last push: ${_time(controller.lastPushAt)}',
              'Last live event: ${_time(controller.lastRemoteEventAt)}',
              if (error != null) 'Error: $error',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                controller.syncNow();
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ],
        );
      },
    );
  }

  String _short(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 8)}...';
  }

  String _time(DateTime? value) {
    if (value == null) return 'never';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
