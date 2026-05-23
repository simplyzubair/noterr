import 'package:flutter/material.dart';

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

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _quickTask = TextEditingController();
  final _newSticky = TextEditingController();
  final _quickTaskFocus = FocusNode();
  final Map<String, FocusNode> _taskFocusNodes = {};
  String? _pendingTaskFocusId;
  double _splitRatio = 0.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.ensureTodayTodoNote();
    });
  }

  @override
  void dispose() {
    _quickTask.dispose();
    _newSticky.dispose();
    _quickTaskFocus.dispose();
    for (final node in _taskFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _addTask([String? text]) async {
    final value = (text ?? _quickTask.text).trim();
    if (value.isEmpty) {
      _refocusQuickTask();
      return;
    }
    _quickTask.clear();
    await widget.controller.addTodayTask(value);
    _refocusQuickTask();
  }

  void _refocusQuickTask() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _quickTaskFocus.requestFocus();
    });
  }

  Future<void> _addTaskAfter(ChecklistItem item) async {
    final next = await widget.controller.addTodayTaskAfter(item);
    setState(() => _pendingTaskFocusId = next.id);
  }

  Future<void> _createSticky() async {
    final text = _newSticky.text.trim();
    if (text.isEmpty) return;
    _newSticky.clear();
    final note = await widget.controller.createNote(type: NoteType.note);
    final updated = note.copyWith(
      title: text.length > 36 ? '${text.substring(0, 36)}...' : text,
      body: text,
      popOnDesktop: true,
      showOnMobileWidget: true,
      colorHex: 'FFF4B8',
    );
    await widget.controller.updateNote(updated);
    await StickyWindowService.instance.show(updated);
  }

  Future<void> _updateSticky(Note note, {String? title, String? body}) {
    return widget.controller.updateNote(
      note.copyWith(
        title: title,
        body: body,
        popOnDesktop: true,
        showOnMobileWidget: true,
      ),
    );
  }

  FocusNode _focusNodeForTask(ChecklistItem item) {
    final node = _taskFocusNodes.putIfAbsent(item.id, FocusNode.new);
    if (_pendingTaskFocusId == item.id) {
      _pendingTaskFocusId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
    return node;
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HistoryScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final todo = widget.controller.todayTodoNote;
        final stickyNotes = widget.controller.stickyNotes;
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
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 860;
              final todoPanel = _TodayTodoPanel(
                note: todo,
                quickTask: _quickTask,
                quickTaskFocus: _quickTaskFocus,
                focusNodeForTask: _focusNodeForTask,
                onAddTask: _addTask,
                onAddAfter: _addTaskAfter,
                onToggle: widget.controller.toggleTodayTask,
                onText: widget.controller.updateTodayTask,
                onRemove: widget.controller.removeTodayTask,
                onClearDone: widget.controller.clearDoneTodayTasks,
                onFloat:
                    todo == null ? null : () => StickyWindowService.instance.show(todo),
              );
              final stickyPanel = _StickyNotesPanel(
                notes: stickyNotes,
                newSticky: _newSticky,
                onCreate: _createSticky,
                onUpdate: _updateSticky,
                onFloat: StickyWindowService.instance.show,
                onDelete: widget.controller.softDeleteNote,
                onColor: (note, colorHex) => widget.controller.updateNote(
                  note.copyWith(colorHex: colorHex),
                ),
              );
              if (narrow) {
                return ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    SizedBox(height: 520, child: todoPanel),
                    const SizedBox(height: 12),
                    SizedBox(height: 520, child: stickyPanel),
                  ],
                );
              }
              final dividerWidth = 12.0;
              final available = constraints.maxWidth - dividerWidth;
              final leftWidth = available * _splitRatio;
              final rightWidth = available - leftWidth;
              return Row(
                children: [
                  SizedBox(width: leftWidth, child: todoPanel),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _splitRatio =
                              (_splitRatio + details.delta.dx / available)
                                  .clamp(0.28, 0.72);
                        });
                      },
                      child: const SizedBox(
                        width: 12,
                        child: VerticalDivider(width: 1),
                      ),
                    ),
                  ),
                  SizedBox(width: rightWidth, child: stickyPanel),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _TodayTodoPanel extends StatelessWidget {
  const _TodayTodoPanel({
    required this.note,
    required this.quickTask,
    required this.quickTaskFocus,
    required this.focusNodeForTask,
    required this.onAddTask,
    required this.onAddAfter,
    required this.onToggle,
    required this.onText,
    required this.onRemove,
    required this.onClearDone,
    required this.onFloat,
  });

  final Note? note;
  final TextEditingController quickTask;
  final FocusNode quickTaskFocus;
  final FocusNode Function(ChecklistItem item) focusNodeForTask;
  final Future<void> Function([String? text]) onAddTask;
  final Future<void> Function(ChecklistItem item) onAddAfter;
  final Future<void> Function(ChecklistItem item) onToggle;
  final Future<void> Function(ChecklistItem item, String text) onText;
  final Future<void> Function(ChecklistItem item) onRemove;
  final Future<void> Function() onClearDone;
  final VoidCallback? onFloat;

  @override
  Widget build(BuildContext context) {
    final items = note?.checklist ?? const <ChecklistItem>[];
    final activeItems = items.where((item) => !item.done).toList();
    final doneItems = items.where((item) => item.done).toList();
    final doneCount = doneItems.length;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Today To Do',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Show as desktop sticky',
                  onPressed: onFloat,
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  tooltip: 'Clear done',
                  onPressed: items.any((item) => item.done) ? onClearDone : null,
                  icon: const Icon(Icons.cleaning_services_outlined),
                ),
              ],
            ),
            Text(
              '${items.length - doneCount} left, $doneCount done',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: quickTask,
              focusNode: quickTaskFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: onAddTask,
              decoration: InputDecoration(
                hintText: 'Type a task and press Enter',
                prefixIcon: const Icon(Icons.add_task),
                suffixIcon: IconButton(
                  tooltip: 'Add task',
                  onPressed: onAddTask,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Nothing yet. Add one task.'))
                  : ListView(
                      children: [
                        if (activeItems.isNotEmpty)
                          _TodoSection(
                            title: 'Next',
                            items: activeItems,
                            focusNodeForTask: focusNodeForTask,
                            onToggle: onToggle,
                            onText: onText,
                            onEnter: onAddAfter,
                            onRemove: onRemove,
                          ),
                        if (doneItems.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _TodoSection(
                            title: 'Done',
                            items: doneItems,
                            focusNodeForTask: focusNodeForTask,
                            onToggle: onToggle,
                            onText: onText,
                            onEnter: onAddAfter,
                            onRemove: onRemove,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoSection extends StatelessWidget {
  const _TodoSection({
    required this.title,
    required this.items,
    required this.focusNodeForTask,
    required this.onToggle,
    required this.onText,
    required this.onEnter,
    required this.onRemove,
  });

  final String title;
  final List<ChecklistItem> items;
  final FocusNode Function(ChecklistItem item) focusNodeForTask;
  final Future<void> Function(ChecklistItem item) onToggle;
  final Future<void> Function(ChecklistItem item, String text) onText;
  final Future<void> Function(ChecklistItem item) onEnter;
  final Future<void> Function(ChecklistItem item) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _TodoRow(
              item: item,
              focusNode: focusNodeForTask(item),
              onToggle: () => onToggle(item),
              onText: (text) => onText(item, text),
              onEnter: () => onEnter(item),
              onRemove: () => onRemove(item),
            ),
          );
        }),
      ],
    );
  }
}

class _TodoRow extends StatefulWidget {
  const _TodoRow({
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
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.item.text);
  }

  @override
  void didUpdateWidget(covariant _TodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _text.text = widget.item.text;
      return;
    }
    if (!widget.focusNode.hasFocus && _text.text != widget.item.text) {
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
    return Material(
      color: widget.item.done
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.32),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Checkbox(value: widget.item.done, onChanged: (_) => widget.onToggle()),
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
    );
  }
}

class _StickyNotesPanel extends StatelessWidget {
  const _StickyNotesPanel({
    required this.notes,
    required this.newSticky,
    required this.onCreate,
    required this.onUpdate,
    required this.onFloat,
    required this.onDelete,
    required this.onColor,
  });

  final List<Note> notes;
  final TextEditingController newSticky;
  final Future<void> Function() onCreate;
  final Future<void> Function(Note note, {String? title, String? body}) onUpdate;
  final Future<void> Function(Note note) onFloat;
  final Future<void> Function(Note note) onDelete;
  final Future<void> Function(Note note, String colorHex) onColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sticky Notes',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: newSticky,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onCreate(),
              decoration: InputDecoration(
                hintText: 'Quick sticky note',
                prefixIcon: const Icon(Icons.note_add_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Create sticky',
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: notes.isEmpty
                  ? const Center(child: Text('No sticky notes yet.'))
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _StickyCard(
                          note: note,
                          onUpdate: onUpdate,
                          onFloat: () => onFloat(note),
                          onDelete: () => onDelete(note),
                          onColor: (color) => onColor(note, color),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyCard extends StatefulWidget {
  const _StickyCard({
    required this.note,
    required this.onUpdate,
    required this.onFloat,
    required this.onDelete,
    required this.onColor,
  });

  final Note note;
  final Future<void> Function(Note note, {String? title, String? body}) onUpdate;
  final VoidCallback onFloat;
  final VoidCallback onDelete;
  final ValueChanged<String> onColor;

  @override
  State<_StickyCard> createState() => _StickyCardState();
}

class _StickyCardState extends State<_StickyCard> {
  late final TextEditingController _title;
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
  }

  @override
  void didUpdateWidget(covariant _StickyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _title.text = widget.note.title;
      _body.text = widget.note.body;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: noteColor(widget.note.colorHex),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    onChanged: (value) =>
                        widget.onUpdate(widget.note, title: value),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Title',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Float on desktop',
                  onPressed: widget.onFloat,
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: _body,
              onChanged: (value) => widget.onUpdate(widget.note, body: value),
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Write sticky note',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: notePalette.take(6).map((hex) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => widget.onColor(hex),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: noteColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.note.colorHex == hex
                              ? Colors.black87
                              : Colors.black26,
                          width: widget.note.colorHex == hex ? 2 : 1,
                        ),
                      ),
                      child: const SizedBox.square(dimension: 20),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
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
          appBar: AppBar(
            title: const Text('History'),
          ),
          body: notes.isEmpty
              ? const Center(child: Text('Nothing saved yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    final date = note.updatedAt.toLocal();
                    return Material(
                      color: note.isDeleted
                          ? Theme.of(context).colorScheme.errorContainer
                          : noteColor(note.colorHex),
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        leading: Icon(
                          note.type == NoteType.checklist
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
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (note.isDeleted)
                              const Chip(label: Text('Deleted'))
                            else if (note.isArchived)
                              const Chip(label: Text('Archived')),
                            if (note.type == NoteType.checklist)
                              Chip(label: Text('${note.checklist.length} tasks')),
                          ],
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
              'Notes here: ${controller.notes.length}',
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
