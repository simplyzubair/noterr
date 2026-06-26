import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import 'note_colors.dart';

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.note,
    required this.onChanged,
    required this.onArchive,
    required this.onDelete,
    required this.onRestore,
    required this.onAlwaysOnTop,
    required this.onShowSticky,
  });

  final Note note;
  final Future<void> Function(Note note) onChanged;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onAlwaysOnTop;
  final VoidCallback onShowSticky;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  late final TextEditingController _board;
  final Map<String, FocusNode> _checklistFocusNodes = {};
  String? _pendingChecklistFocusId;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
    _tags = TextEditingController(text: widget.note.tags.join(', '));
    _board = TextEditingController(text: widget.note.boardName);
  }

  @override
  void didUpdateWidget(covariant NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _replaceText(_title, widget.note.title);
      _replaceText(_body, widget.note.body);
      _replaceText(_tags, widget.note.tags.join(', '));
      _replaceText(_board, widget.note.boardName);
      return;
    }
    _replaceText(_title, widget.note.title);
    _replaceText(_body, widget.note.body);
    _replaceText(_tags, widget.note.tags.join(', '));
    _replaceText(_board, widget.note.boardName);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _board.dispose();
    for (final node in _checklistFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _save({
    String? title,
    NoteType? type,
    String? body,
    String? colorHex,
    String? boardName,
    List<String>? tags,
    List<ChecklistItem>? checklist,
    List<String>? deletedChecklistItemKeys,
    List<NoteAttachment>? attachments,
    NoteReminder? reminder,
    bool? isPinned,
  }) {
    return widget.onChanged(
      widget.note.copyWith(
        title: title,
        type: type,
        body: body,
        colorHex: colorHex,
        boardName: boardName,
        tags: tags,
        checklist: checklist,
        deletedChecklistItemKeys: deletedChecklistItemKeys,
        attachments: attachments,
        reminder: reminder,
        isPinned: isPinned,
      ),
    );
  }

  Future<void> _insertTimestamp() async {
    final stamp = DateFormat.yMMMd().add_jm().format(DateTime.now());
    await _replaceBodySelection(stamp);
  }

  Future<void> _insertBullet() => _replaceBodySelection('- ');

  Future<void> _insertNumberedItem() => _replaceBodySelection('1. ');

  Future<void> _insertHeading() => _replaceBodySelection('# ');

  Future<void> _wrapBold() async {
    final selection = _body.selection;
    if (!selection.isValid || selection.isCollapsed) {
      await _replaceBodySelection('**bold text**');
      return;
    }
    final selected = _body.text.substring(selection.start, selection.end);
    await _replaceBodySelection('**$selected**');
  }

  Future<void> _replaceBodySelection(String value) async {
    final selection = _body.selection;
    final start = selection.start < 0 ? _body.text.length : selection.start;
    final end = selection.end < 0 ? _body.text.length : selection.end;
    final nextText = _body.text.replaceRange(start, end, value);
    _body.text = nextText;
    _body.selection = TextSelection.collapsed(offset: start + value.length);
    await _save(body: nextText);
  }

  void _replaceText(TextEditingController controller, String text) {
    if (controller.text == text) return;
    final oldOffset = controller.selection.baseOffset;
    final offset = oldOffset < 0
        ? text.length
        : oldOffset > text.length
            ? text.length
            : oldOffset;
    controller.text = text;
    controller.selection = TextSelection.collapsed(offset: offset);
  }

  List<String> _parseTags(String value) {
    return value
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _pickAttachment() async {
    final file = await openFile();
    if (file == null) return;
    final sizeBytes = await file.length();
    await _save(
      attachments: [
        ...widget.note.attachments,
        NoteAttachment(
          name: file.name,
          mimeType: file.mimeType ?? 'application/octet-stream',
          localPath: file.path,
          sizeBytes: sizeBytes,
        ),
      ],
    );
  }

  Future<void> _setReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      initialDate: widget.note.reminder.dueAt ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(widget.note.reminder.dueAt ?? now),
    );
    if (time == null) return;
    final dueAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    await _save(reminder: NoteReminder(dueAt: dueAt));
  }

  Future<void> _addChecklistItem() async {
    final item = ChecklistItem(text: '');
    _pendingChecklistFocusId = item.id;
    await _save(
      checklist: [
        ...widget.note.checklist,
        item,
      ],
    );
  }

  Future<void> _addChecklistItemAfter(ChecklistItem item) async {
    final next = ChecklistItem(text: '');
    _pendingChecklistFocusId = next.id;
    final items = [...widget.note.checklist];
    final index = items.indexWhere((current) => current.id == item.id);
    if (index == -1) {
      items.add(next);
    } else {
      items.insert(index + 1, next);
    }
    await _save(checklist: items);
  }

  Future<void> _updateChecklistItem(ChecklistItem item, String text) async {
    await _save(
      checklist: widget.note.checklist
          .map((current) => current.id == item.id
              ? current.copyWith(text: text)
              : current)
          .toList(),
      deletedChecklistItemKeys: _reviveChecklistText(
        widget.note.deletedChecklistItemKeys,
        text,
      ),
    );
  }

  Future<void> _toggleChecklistItem(ChecklistItem item) async {
    await _save(
      checklist: widget.note.checklist
          .map((current) => current.id == item.id
              ? current.copyWith(done: !current.done)
              : current)
          .toList(),
    );
  }

  Future<void> _removeChecklistItem(ChecklistItem item) async {
    await _save(
      checklist:
          widget.note.checklist.where((current) => current.id != item.id).toList(),
      deletedChecklistItemKeys: _deletedChecklistKeys(widget.note, [item]),
    );
  }

  List<String> _deletedChecklistKeys(
    Note note,
    Iterable<ChecklistItem> items,
  ) {
    final keys = note.deletedChecklistItemKeys
        .where((key) => key.trim().isNotEmpty)
        .toSet();
    for (final item in items) {
      final text = item.text.trim().toLowerCase();
      if (text.isNotEmpty) keys.add('text:$text');
      keys.add('id:${item.id}');
    }
    return keys.toList();
  }

  List<String> _reviveChecklistText(List<String> deletedKeys, String text) {
    final key = 'text:${text.trim().toLowerCase()}';
    if (key == 'text:') return deletedKeys;
    return deletedKeys.where((deletedKey) => deletedKey != key).toList();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final reminder = note.reminder.dueAt?.toLocal();
    final reminderText =
        reminder == null ? null : DateFormat.yMMMd().add_jm().format(reminder);
    final wordCount = note.body
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    final characterCount = note.body.length;
    final supportsBody = note.supportsBody;
    final supportsChecklist = note.supportsChecklist;

    return ColoredBox(
      color: noteColor(note.colorHex).withValues(alpha: 0.34),
      child: Column(
        children: [
          _EditorToolbar(
            note: note,
            onArchive: widget.onArchive,
            onDelete: widget.onDelete,
            onRestore: widget.onRestore,
            onAlwaysOnTop: widget.onAlwaysOnTop,
            onShowSticky: widget.onShowSticky,
            onPinned: () => _save(isPinned: !note.isPinned),
            onReminder: _setReminder,
            onAttachment: _pickAttachment,
            onTimestamp: supportsBody ? _insertTimestamp : null,
            onBold: supportsBody ? _wrapBold : null,
            onBullet: supportsBody ? _insertBullet : null,
            onNumbered: supportsBody ? _insertNumberedItem : null,
            onHeading: supportsBody ? _insertHeading : null,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                TextField(
                  controller: _title,
                  onChanged: (value) => _save(title: value),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Title',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<NoteType>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: NoteType.note,
                        icon: Icon(Icons.sticky_note_2_outlined),
                        label: Text('Note'),
                      ),
                      ButtonSegment(
                        value: NoteType.checklist,
                        icon: Icon(Icons.checklist),
                        label: Text('Checklist'),
                      ),
                      ButtonSegment(
                        value: NoteType.full,
                        icon: Icon(Icons.edit_note),
                        label: Text('Full Editor'),
                      ),
                    ],
                    selected: {note.type},
                    onSelectionChanged: (value) => _save(type: value.first),
                  ),
                ),
                if (supportsBody) ...[
                  const SizedBox(height: 4),
                  TextField(
                    controller: _body,
                    onChanged: (value) => _save(body: value),
                    minLines: note.type == NoteType.full ? 6 : 12,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Write a note',
                      alignLabelWithHint: true,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$wordCount words | $characterCount characters',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _SectionHeader(
                  icon: Icons.palette_outlined,
                  text: 'Color',
                  action: Wrap(
                    spacing: 8,
                    children: notePalette.map((hex) {
                      final selected = note.colorHex == hex;
                      return Tooltip(
                        message: hex,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => _save(colorHex: hex),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: noteColor(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: selected ? 3 : 1,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black26,
                              ),
                            ),
                            child: const SizedBox.square(dimension: 28),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _board,
                  onChanged: (value) => _save(
                    boardName: value.trim().isEmpty ? 'Personal' : value.trim(),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Memoboard',
                    prefixIcon: Icon(Icons.dashboard_outlined),
                    hintText: 'Personal, Work, Ideas',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tags,
                  onChanged: (value) => _save(tags: _parseTags(value)),
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    prefixIcon: Icon(Icons.sell_outlined),
                    hintText: 'work, idea, urgent',
                  ),
                ),
                if (supportsChecklist) ...[
                  const SizedBox(height: 20),
                  _SectionHeader(
                    icon: Icons.checklist,
                    text: 'Checklist',
                    action: IconButton(
                      tooltip: 'Add checklist item',
                      onPressed: _addChecklistItem,
                      icon: const Icon(Icons.add_task),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (note.checklist.isEmpty)
                    FilledButton.icon(
                      onPressed: _addChecklistItem,
                      icon: const Icon(Icons.add_task),
                      label: const Text('Add first checklist item'),
                    )
                  else
                    ...note.checklist.map((item) {
                      final focusNode = _focusNodeForChecklistItem(item);
                      return _ChecklistRow(
                        key: ValueKey(item.id),
                        item: item,
                        focusNode: focusNode,
                        onToggle: () => _toggleChecklistItem(item),
                        onText: (text) => _updateChecklistItem(item, text),
                        onEnter: () => _addChecklistItemAfter(item),
                        onRemove: () => _removeChecklistItem(item),
                      );
                    }),
                ],
                const SizedBox(height: 20),
                _SectionHeader(
                  icon: Icons.alarm,
                  text: 'Reminder',
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (reminderText != null) Text(reminderText),
                      IconButton(
                        tooltip: 'Set reminder',
                        onPressed: _setReminder,
                        icon: const Icon(Icons.alarm_add),
                      ),
                      if (reminderText != null)
                        IconButton(
                          tooltip: 'Clear reminder',
                          onPressed: () => _save(
                            reminder: const NoteReminder(dueAt: null),
                          ),
                          icon: const Icon(Icons.alarm_off),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  icon: Icons.attach_file,
                  text: 'Attachments',
                  action: IconButton(
                    tooltip: 'Attach file',
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                if (note.attachments.isEmpty)
                  const Text('No attachments')
                else
                  ...note.attachments.map((attachment) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(attachment.name),
                      subtitle: Text('${attachment.sizeBytes} bytes'),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  FocusNode _focusNodeForChecklistItem(ChecklistItem item) {
    final node = _checklistFocusNodes.putIfAbsent(item.id, FocusNode.new);
    if (_pendingChecklistFocusId == item.id) {
      _pendingChecklistFocusId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
    return node;
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.note,
    required this.onArchive,
    required this.onDelete,
    required this.onRestore,
    required this.onAlwaysOnTop,
    required this.onShowSticky,
    required this.onPinned,
    required this.onReminder,
    required this.onAttachment,
    required this.onTimestamp,
    required this.onBold,
    required this.onBullet,
    required this.onNumbered,
    required this.onHeading,
  });

  final Note note;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onAlwaysOnTop;
  final VoidCallback onShowSticky;
  final VoidCallback onPinned;
  final VoidCallback onReminder;
  final VoidCallback onAttachment;
  final VoidCallback? onTimestamp;
  final VoidCallback? onBold;
  final VoidCallback? onBullet;
  final VoidCallback? onNumbered;
  final VoidCallback? onHeading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: note.isPinned ? 'Unpin' : 'Pin',
              onPressed: onPinned,
              icon: Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            ),
            IconButton(
              tooltip: note.isAlwaysOnTop ? 'Disable always on top' : 'Always on top',
              onPressed: onAlwaysOnTop,
              icon: Icon(
                note.isAlwaysOnTop
                    ? Icons.vertical_align_top
                    : Icons.vertical_align_top_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Show as desktop sticky note',
              onPressed: onShowSticky,
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: 'Reminder',
              onPressed: onReminder,
              icon: const Icon(Icons.alarm),
            ),
            IconButton(
              tooltip: 'Insert date and time',
              onPressed: onTimestamp,
              icon: const Icon(Icons.today),
            ),
            IconButton(
              tooltip: 'Bold',
              onPressed: onBold,
              icon: const Icon(Icons.format_bold),
            ),
            IconButton(
              tooltip: 'Bullet list',
              onPressed: onBullet,
              icon: const Icon(Icons.format_list_bulleted),
            ),
            IconButton(
              tooltip: 'Numbered list',
              onPressed: onNumbered,
              icon: const Icon(Icons.format_list_numbered),
            ),
            IconButton(
              tooltip: 'Heading',
              onPressed: onHeading,
              icon: const Icon(Icons.title),
            ),
            IconButton(
              tooltip: 'Attach',
              onPressed: onAttachment,
              icon: const Icon(Icons.attach_file),
            ),
            const Spacer(),
            if (note.isDeleted)
              IconButton(
                tooltip: 'Restore',
                onPressed: onRestore,
                icon: const Icon(Icons.restore_from_trash),
              )
            else ...[
              IconButton(
                tooltip: note.isArchived ? 'Unarchive' : 'Archive',
                onPressed: onArchive,
                icon: Icon(note.isArchived ? Icons.unarchive : Icons.archive),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        action,
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
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
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
              isDense: true,
              hintText: 'Checklist item',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          onPressed: widget.onRemove,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
