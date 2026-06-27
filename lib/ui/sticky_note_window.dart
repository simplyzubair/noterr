import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';
import '../models/note.dart';
import '../services/daily_quote.dart';
import 'note_colors.dart';

class StickyNoteWindowApp extends StatelessWidget {
  const StickyNoteWindowApp({
    super.key,
    required this.note,
  });

  final Note note;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: note.title.isEmpty ? 'Noterr sticky' : note.title,
      debugShowCheckedModeBanner: false,
      theme: buildNoterrTheme(Brightness.light),
      home: StickyNoteWindow(
        note: note,
      ),
    );
  }
}

class StickyNoteWindow extends StatefulWidget {
  const StickyNoteWindow({
    super.key,
    required this.note,
  });

  final Note note;

  @override
  State<StickyNoteWindow> createState() => _StickyNoteWindowState();
}

class _StickyNoteWindowState extends State<StickyNoteWindow>
    with WindowListener {
  static const _channel = WindowMethodChannel(
    'noterr_sticky_notes',
    mode: ChannelMode.unidirectional,
  );

  late Note _note;
  late final TextEditingController _title;
  late final TextEditingController _body;
  final Map<String, FocusNode> _checklistFocusNodes = {};
  WindowController? _windowController;
  bool _rolledUp = false;
  bool _showStyleControls = false;
  String? _pendingChecklistFocusId;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _title = TextEditingController(text: _note.title);
    _body = TextEditingController(text: _note.body);
    windowManager.addListener(this);
    unawaited(_registerWindowHandler());
  }

  @override
  void dispose() {
    unawaited(_windowController?.setWindowMethodHandler(null));
    windowManager.removeListener(this);
    _title.dispose();
    _body.dispose();
    for (final node in _checklistFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _registerWindowHandler() async {
    final controller = await WindowController.fromCurrentEngine();
    _windowController = controller;
    await controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'sticky-note-replaced':
          final note = Note.fromJson(
            Map<String, dynamic>.from(call.arguments as Map),
          );
          await _replaceFromMainWindow(note);
          return true;
        case 'sticky-note-lock':
          await windowManager.close();
          return true;
        case 'sticky-note-hide':
          await windowManager.hide();
          return true;
      }
      return null;
    });
  }

  Future<void> _replaceFromMainWindow(Note note) async {
    if (!mounted || note.id != _note.id) return;
    if (_title.text != note.title) _title.text = note.title;
    if (_body.text != note.body) _body.text = note.body;
    if (note.isAlwaysOnTop != _note.isAlwaysOnTop) {
      await windowManager.setAlwaysOnTop(note.isAlwaysOnTop);
    }
    if (note.opacity != _note.opacity) {
      await windowManager.setOpacity(note.opacity);
    }
    setState(() => _note = note);
  }

  Future<void> _save({
    String? title,
    String? body,
    String? colorHex,
    List<ChecklistItem>? checklist,
    StickyBounds? bounds,
    double? opacity,
    bool? popOnDesktop,
    bool? showOnMobileWidget,
    bool? isAlwaysOnTop,
  }) async {
    final next = _note.copyWith(
      title: title,
      body: body,
      colorHex: colorHex,
      checklist: checklist,
      bounds: bounds,
      opacity: opacity,
      popOnDesktop: popOnDesktop,
      showOnMobileWidget: showOnMobileWidget,
      isAlwaysOnTop: isAlwaysOnTop,
    );
    if (!mounted) return;
    setState(() => _note = next);
    await _channel.invokeMethod(
      'sticky-note-updated',
      next.toJson(),
    );
  }

  Future<void> _close() async {
    await _saveBounds();
    await _windowController?.setWindowMethodHandler(null);
    await _channel.invokeMethod('sticky-note-closed', _note.id);
    await windowManager.close();
  }

  Future<void> _delete() async {
    await _channel.invokeMethod('sticky-note-delete', _note.id);
    await windowManager.close();
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_note.isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    await _save(isAlwaysOnTop: next);
  }

  Future<void> _toggleRolledUp() async {
    final next = !_rolledUp;
    setState(() => _rolledUp = next);
    if (next) {
      await windowManager.setSize(const Size(320, 48));
      return;
    }
    final bounds = _note.bounds ?? StickyBounds.defaults();
    await windowManager.setSize(Size(bounds.width, bounds.height));
  }

  Future<void> _makeWide() async {
    final bounds = await windowManager.getBounds();
    await windowManager
        .setSize(Size(720, bounds.height < 360 ? 420 : bounds.height));
    await _saveBounds();
  }

  Future<void> _toggleChecklistItem(ChecklistItem item) async {
    await _save(
      checklist: _note.checklist
          .map((current) => current.id == item.id
              ? current.copyWith(done: !current.done)
              : current)
          .toList(),
    );
  }

  Future<void> _addChecklistItem() async {
    final item = ChecklistItem(text: 'New task');
    _pendingChecklistFocusId = item.id;
    await _save(
      checklist: [
        ..._note.checklist,
        item,
      ],
    );
  }

  Future<void> _addChecklistItemAfter(ChecklistItem item) async {
    final next = ChecklistItem(text: 'New task');
    _pendingChecklistFocusId = next.id;
    final items = [..._note.checklist];
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
      checklist: _note.checklist
          .map(
            (current) =>
                current.id == item.id ? current.copyWith(text: text) : current,
          )
          .toList(),
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

  Future<void> _togglePopOnDesktop() {
    return _save(popOnDesktop: !_note.popOnDesktop);
  }

  Future<void> _toggleMobileWidget() {
    return _save(showOnMobileWidget: !_note.showOnMobileWidget);
  }

  Future<void> _setOpacity(double opacity) async {
    await windowManager.setOpacity(opacity);
    await _save(opacity: opacity);
  }

  Future<void> _saveNow() async {
    await _save(
        title: _title.text, body: _body.text, checklist: _note.checklist);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved and synced')),
    );
  }

  Future<void> _runQuickAction(_StickyAction action) {
    return switch (action) {
      _StickyAction.save => _saveNow(),
      _StickyAction.addTask => _addChecklistItem(),
      _StickyAction.pinOnTop => _toggleAlwaysOnTop(),
      _StickyAction.phoneWidget => _toggleMobileWidget(),
      _StickyAction.desktopPopup => _togglePopOnDesktop(),
      _StickyAction.style => _toggleStyleControls(),
      _StickyAction.rollUp => _toggleRolledUp(),
      _StickyAction.makeWide => _makeWide(),
      _StickyAction.delete => _delete(),
      _StickyAction.close => _close(),
    };
  }

  Future<void> _toggleStyleControls() async {
    setState(() => _showStyleControls = !_showStyleControls);
  }

  Future<void> _showQuickMenu(Offset position) async {
    final action = await showMenu<_StickyAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: _quickMenuItems(_note),
    );
    if (action != null) await _runQuickAction(action);
  }

  Future<void> _saveBounds() async {
    final bounds = await windowManager.getBounds();
    await _save(
      bounds: StickyBounds(
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
      ),
    );
  }

  @override
  void onWindowMoved() {
    if (!_rolledUp) unawaited(_saveBounds());
  }

  @override
  void onWindowResized() {
    if (!_rolledUp) unawaited(_saveBounds());
  }

  @override
  Widget build(BuildContext context) {
    final color = noteColor(_note.colorHex);
    final supportsBody = _note.supportsBody;
    final supportsChecklist = _note.supportsChecklist;
    return GestureDetector(
      onSecondaryTapDown: (details) => _showQuickMenu(details.globalPosition),
      child: Scaffold(
        backgroundColor: color,
        body: Column(
          children: [
            _StickyTitleBar(
              color: color,
              note: _note,
              isAlwaysOnTop: _note.isAlwaysOnTop,
              rolledUp: _rolledUp,
              onQuickAction: _runQuickAction,
              onAlwaysOnTop: _toggleAlwaysOnTop,
              onSave: _saveNow,
              onRollUp: _toggleRolledUp,
              onWide: _makeWide,
              onClose: _close,
            ),
            if (!_rolledUp)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    children: [
                      TextField(
                        controller: _title,
                        onChanged: (value) => _save(title: value),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Title',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _StickyQuoteStrip(quote: DailyQuote.forDate()),
                      ),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            if (supportsBody)
                              SizedBox(
                                height: _note.type == NoteType.full ? 120 : 190,
                                child: TextField(
                                  controller: _body,
                                  onChanged: (value) => _save(body: value),
                                  expands: true,
                                  maxLines: null,
                                  minLines: null,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 15,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Write a note',
                                  ),
                                ),
                              ),
                            if (supportsChecklist) ...[
                              const SizedBox(height: 8),
                              if (_note.checklist.isEmpty)
                                const Text(
                                  'No checklist items',
                                  style: TextStyle(color: Colors.black54),
                                )
                              else
                                ..._note.checklist.map((item) {
                                  return Row(
                                    key: ValueKey(item.id),
                                    children: [
                                      Checkbox(
                                        value: item.done,
                                        onChanged: (_) =>
                                            _toggleChecklistItem(item),
                                      ),
                                      Expanded(
                                        child: _StickyChecklistField(
                                          item: item,
                                          focusNode:
                                              _focusNodeForChecklistItem(item),
                                          onText: (value) =>
                                              _updateChecklistItem(item, value),
                                          onEnter: () =>
                                              _addChecklistItemAfter(item),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                            ],
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          if (supportsChecklist)
                            IconButton(
                              tooltip: 'Add checklist item',
                              onPressed: _addChecklistItem,
                              icon: const Icon(Icons.add_task, size: 18),
                            ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Style and transparency',
                            onPressed: _toggleStyleControls,
                            icon: const Icon(Icons.tune, size: 18),
                          ),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        child: !_showStyleControls
                            ? const SizedBox.shrink()
                            : _StickyStyleControls(
                                key: const ValueKey('sticky-style'),
                                note: _note,
                                onColor: (hex) => _save(colorHex: hex),
                                onOpacity: _setOpacity,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickyQuoteStrip extends StatelessWidget {
  const _StickyQuoteStrip({required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.auto_awesome, size: 13, color: Colors.black54),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            quote,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

enum _StickyAction {
  save,
  addTask,
  pinOnTop,
  phoneWidget,
  desktopPopup,
  style,
  rollUp,
  makeWide,
  delete,
  close,
}

class _StickyChecklistField extends StatefulWidget {
  const _StickyChecklistField({
    required this.item,
    required this.focusNode,
    required this.onText,
    required this.onEnter,
  });

  final ChecklistItem item;
  final FocusNode focusNode;
  final ValueChanged<String> onText;
  final VoidCallback onEnter;

  @override
  State<_StickyChecklistField> createState() => _StickyChecklistFieldState();
}

class _StickyChecklistFieldState extends State<_StickyChecklistField> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.item.text);
  }

  @override
  void didUpdateWidget(covariant _StickyChecklistField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _text.text = widget.item.text;
      return;
    }
    if (_text.text != widget.item.text && !widget.focusNode.hasFocus) {
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
    return TextField(
      controller: _text,
      focusNode: widget.focusNode,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => widget.onEnter(),
      onChanged: widget.onText,
      style: TextStyle(
        color: Colors.black87,
        decoration: widget.item.done ? TextDecoration.lineThrough : null,
      ),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: 'Checklist item',
      ),
    );
  }
}

class _StickyStyleControls extends StatelessWidget {
  const _StickyStyleControls({
    super.key,
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
      children: [
        Row(
          children: [
            ...notePalette.take(6).map(
                  (hex) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => onColor(hex),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: noteColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: note.colorHex == hex
                                ? Colors.black87
                                : Colors.black26,
                            width: note.colorHex == hex ? 2 : 1,
                          ),
                        ),
                        child: const SizedBox.square(dimension: 18),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.opacity, size: 18, color: Colors.black87),
            Expanded(
              child: Slider(
                value: note.opacity.clamp(0.45, 1),
                min: 0.45,
                max: 1,
                divisions: 11,
                onChanged: onOpacity,
              ),
            ),
            Text(
              '${(note.opacity * 100).round()}%',
              style: const TextStyle(color: Colors.black87),
            ),
          ],
        ),
      ],
    );
  }
}

List<PopupMenuEntry<_StickyAction>> _quickMenuItems(Note note) {
  return [
    const PopupMenuItem(
      value: _StickyAction.save,
      child: ListTile(
        leading: Icon(Icons.save_outlined),
        title: Text('Save and sync'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    if (note.supportsChecklist)
      const PopupMenuItem(
        value: _StickyAction.addTask,
        child: ListTile(
          leading: Icon(Icons.add_task),
          title: Text('Add task'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: _StickyAction.pinOnTop,
      child: ListTile(
        leading: Icon(
          note.isAlwaysOnTop
              ? Icons.vertical_align_top
              : Icons.vertical_align_top_outlined,
        ),
        title: Text(note.isAlwaysOnTop ? 'Unpin from top' : 'Keep on top'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: _StickyAction.phoneWidget,
      child: ListTile(
        leading: Icon(
          note.showOnMobileWidget
              ? Icons.phone_android
              : Icons.phone_android_outlined,
        ),
        title: Text(
          note.showOnMobileWidget
              ? 'Remove from phone widget'
              : 'Show on phone widget',
        ),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: _StickyAction.desktopPopup,
      child: ListTile(
        leading: Icon(note.popOnDesktop
            ? Icons.desktop_windows
            : Icons.desktop_access_disabled),
        title: Text(
          note.popOnDesktop ? 'Stop desktop popups' : 'Pop up on desktop',
        ),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuItem(
      value: _StickyAction.style,
      child: ListTile(
        leading: Icon(Icons.tune),
        title: Text('Style and transparency'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: _StickyAction.rollUp,
      child: ListTile(
        leading: Icon(Icons.unfold_less),
        title: Text('Roll up'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuItem(
      value: _StickyAction.makeWide,
      child: ListTile(
        leading: Icon(Icons.open_in_full),
        title: Text('Make wide'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: _StickyAction.delete,
      child: ListTile(
        leading: Icon(Icons.delete_outline),
        title: Text('Delete'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuItem(
      value: _StickyAction.close,
      child: ListTile(
        leading: Icon(Icons.close),
        title: Text('Close'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  ];
}

class _StickyTitleBar extends StatelessWidget {
  const _StickyTitleBar({
    required this.color,
    required this.note,
    required this.isAlwaysOnTop,
    required this.rolledUp,
    required this.onQuickAction,
    required this.onAlwaysOnTop,
    required this.onSave,
    required this.onRollUp,
    required this.onWide,
    required this.onClose,
  });

  final Color color;
  final Note note;
  final bool isAlwaysOnTop;
  final bool rolledUp;
  final ValueChanged<_StickyAction> onQuickAction;
  final VoidCallback onAlwaysOnTop;
  final VoidCallback onSave;
  final VoidCallback onRollUp;
  final VoidCallback onWide;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.08),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child:
                    Icon(Icons.drag_indicator, size: 18, color: Colors.black54),
              ),
            ),
            const Spacer(),
            PopupMenuButton<_StickyAction>(
              tooltip: 'Quick actions',
              onSelected: onQuickAction,
              itemBuilder: (_) => _quickMenuItems(note),
              icon:
                  const Icon(Icons.more_vert, size: 18, color: Colors.black87),
            ),
            IconButton(
              tooltip: 'Save and sync',
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined,
                  size: 18, color: Colors.black87),
            ),
            IconButton(
              tooltip:
                  isAlwaysOnTop ? 'Disable always on top' : 'Always on top',
              onPressed: onAlwaysOnTop,
              icon: Icon(
                isAlwaysOnTop
                    ? Icons.vertical_align_top
                    : Icons.vertical_align_top_outlined,
                size: 18,
                color: Colors.black87,
              ),
            ),
            IconButton(
              tooltip: rolledUp ? 'Expand sticky note' : 'Roll up sticky note',
              onPressed: onRollUp,
              icon: Icon(
                rolledUp ? Icons.unfold_more : Icons.unfold_less,
                size: 18,
                color: Colors.black87,
              ),
            ),
            IconButton(
              tooltip: 'Make wide',
              onPressed: onWide,
              icon: const Icon(Icons.open_in_full,
                  size: 18, color: Colors.black87),
            ),
            IconButton(
              tooltip: 'Close sticky note',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}
