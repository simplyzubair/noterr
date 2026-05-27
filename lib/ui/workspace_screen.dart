import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_config.dart';
import '../controllers/noterr_controller.dart';
import '../models/note.dart';
import '../services/daily_quote.dart';
import '../services/startup_service.dart';
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
  final _startupService = const StartupService();
  bool _allowClose = false;
  bool _startOnLogin = true;
  bool _privacyHidden = false;
  Timer? _reminderTimer;
  final Set<String> _shownReminderKeys = {};

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
      _checkTaskReminders();
    });
    _reminderTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkTaskReminders(),
    );
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    _reminderTimer?.cancel();
    super.dispose();
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _initDesktopShell() async {
    try {
      await windowManager.setPreventClose(true);
      final startOnLogin = await _startupService.ensureDefaultEnabled();
      if (mounted) setState(() => _startOnLogin = startOnLogin);
      await trayManager.setIcon('windows/runner/resources/app_icon.ico');
      await trayManager.setToolTip('Noterr');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'quick_task', label: 'Quick add task'),
            MenuItem(key: 'quick_note', label: 'Quick add note'),
            MenuItem.separator(),
            MenuItem(key: 'template_work', label: 'Template: Work day'),
            MenuItem(key: 'template_calls', label: 'Template: Calls'),
            MenuItem(key: 'template_shopping', label: 'Template: Shopping'),
            MenuItem(
                key: 'template_prayer', label: 'Template: Prayer / habits'),
            MenuItem(key: 'template_project', label: 'Template: Project tasks'),
            MenuItem.separator(),
            MenuItem(key: 'toggle_privacy', label: 'Hide/show sticky'),
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
      case 'quick_task':
        unawaited(_openQuickAdd(isTask: true));
      case 'quick_note':
        unawaited(_openQuickAdd(isTask: false));
      case 'template_work':
        unawaited(widget.controller.applyTemplate('work'));
      case 'template_calls':
        unawaited(widget.controller.applyTemplate('calls'));
      case 'template_shopping':
        unawaited(widget.controller.applyTemplate('shopping'));
      case 'template_prayer':
        unawaited(widget.controller.applyTemplate('prayer'));
      case 'template_project':
        unawaited(widget.controller.applyTemplate('project'));
      case 'toggle_privacy':
        unawaited(_togglePrivacy());
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

  Future<void> _openQuickAdd({required bool isTask}) async {
    await _showFromTray();
    if (!mounted) return;
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isTask ? 'Quick add task' : 'Quick add note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: isTask ? 1 : 3,
          maxLines: isTask ? 1 : 6,
          textInputAction:
              isTask ? TextInputAction.done : TextInputAction.newline,
          decoration: InputDecoration(
            hintText: isTask ? 'Task' : 'Note',
          ),
          onSubmitted:
              isTask ? (_) => Navigator.of(context).pop(controller.text) : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    final text = value?.trim();
    if (text == null || text.isEmpty) return;
    if (isTask) {
      await widget.controller.addTodayTask(text);
    } else {
      await widget.controller.addTodayNote(text);
    }
    await StickyWindowService.instance.showDailySticky();
  }

  Future<void> _togglePrivacy() async {
    _privacyHidden = !_privacyHidden;
    if (_privacyHidden) {
      await StickyWindowService.instance.hideAll();
    } else {
      await StickyWindowService.instance.showDailySticky();
    }
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

  Future<void> _setStartOnLogin(bool value) async {
    setState(() => _startOnLogin = value);
    await _startupService.setEnabled(value);
  }

  Future<void> _openAndroidUpdate() async {
    final uri = Uri.parse(AppConfig.androidUpdateUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _SyncStatusTile(controller: widget.controller),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.power_settings_new),
                    title: const Text('Start Noterr with Windows'),
                    subtitle:
                        const Text('Show the daily sticky after sign in.'),
                    value: _startOnLogin,
                    onChanged: (value) {
                      setSheetState(() => _startOnLogin = value);
                      unawaited(_setStartOnLogin(value));
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.system_update_alt),
                    title: const Text('Check Android update'),
                    subtitle: const Text('Opens the private APK release page.'),
                    onTap: _openAndroidUpdate,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HistoryScreen(controller: widget.controller),
      ),
    );
  }

  void _openDailyReview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DailyReviewScreen(controller: widget.controller),
      ),
    );
  }

  void _openTemplates() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final templates = widget.controller.templates;
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Templates',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add template',
                        onPressed: () => _editTemplate(),
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        tooltip: 'Reset templates',
                        onPressed: () =>
                            unawaited(widget.controller.resetTemplates()),
                        icon: const Icon(Icons.restart_alt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final entry in templates.entries)
                    _TemplateTile(
                      icon: _templateIcon(entry.key),
                      title: _templateTitle(entry.key),
                      count: entry.value.length,
                      onTap: () => _applyTemplateAndClose(entry.key),
                      onEdit: () => _editTemplate(
                        name: entry.key,
                        tasks: entry.value,
                      ),
                      onDelete: templates.length <= 1
                          ? null
                          : () => unawaited(
                              widget.controller.deleteTemplate(entry.key)),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _applyTemplateAndClose(String name) {
    Navigator.of(context).pop();
    unawaited(widget.controller.applyTemplate(name));
  }

  IconData _templateIcon(String key) {
    return switch (key) {
      'work' => Icons.work_outline,
      'calls' => Icons.call_outlined,
      'shopping' => Icons.shopping_basket_outlined,
      'prayer' => Icons.self_improvement,
      'project' => Icons.account_tree_outlined,
      _ => Icons.checklist,
    };
  }

  String _templateTitle(String key) {
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _editTemplate({
    String? name,
    List<String> tasks = const [],
  }) async {
    final nameController = TextEditingController(text: name ?? '');
    final tasksController = TextEditingController(text: tasks.join('\n'));
    final result = await showDialog<({String name, List<String> tasks})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name == null ? 'Add template' : 'Edit template'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Template name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tasksController,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Tasks',
                  hintText: 'One task per line',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final templateName = nameController.text.trim();
              final templateTasks = tasksController.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              if (templateName.isEmpty || templateTasks.isEmpty) return;
              Navigator.of(context).pop((
                name: templateName,
                tasks: templateTasks,
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    tasksController.dispose();
    if (result == null) return;
    await widget.controller.saveTemplate(result.name, result.tasks);
    final newKey = result.name.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          '_',
        );
    if (name != null && name != newKey) {
      await widget.controller.deleteTemplate(name);
    }
  }

  void _checkTaskReminders() {
    if (!mounted || !widget.controller.isUnlocked) return;
    for (final reminder in widget.controller.dueChecklistReminders) {
      if (_shownReminderKeys.contains(reminder.key)) continue;
      _shownReminderKeys.add(reminder.key);
      _showTaskReminder(reminder);
      break;
    }
  }

  Future<void> _showTaskReminder(DueChecklistReminder reminder) async {
    if (_isDesktop) {
      unawaited(StickyWindowService.instance.show(reminder.note));
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Task reminder'),
        content: Text(reminder.item.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('dismiss'),
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('later'),
            child: const Text('15 min'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('tomorrow'),
            child: const Text('Tomorrow'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('done'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    switch (result) {
      case 'later':
        await widget.controller.setChecklistReminder(
          reminder.note,
          reminder.item,
          DateTime.now().add(const Duration(minutes: 15)),
        );
      case 'tomorrow':
        await widget.controller.setChecklistReminder(
          reminder.note,
          reminder.item,
          DateTime.now().add(const Duration(days: 1)),
        );
      case 'done':
        await widget.controller.toggleChecklistItem(
          reminder.note,
          reminder.item,
        );
      case 'dismiss':
        await widget.controller.dismissChecklistReminder(
          reminder.note,
          reminder.item,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final dailyBoard = widget.controller.todayTodoNote;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Noterr'),
            actions: [
              IconButton(
                tooltip: 'History',
                onPressed: _openHistory,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Daily review',
                onPressed: _openDailyReview,
                icon: const Icon(Icons.fact_check_outlined),
              ),
              IconButton(
                tooltip: 'Templates',
                onPressed: _openTemplates,
                icon: const Icon(Icons.dashboard_customize_outlined),
              ),
              if (_isDesktop)
                IconButton(
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
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
            child: dailyBoard == null
                ? const Center(child: CircularProgressIndicator())
                : _ItemEditor(
                    controller: widget.controller,
                    note: dailyBoard,
                    showTitle: false,
                  ),
          ),
        );
      },
    );
  }
}

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
    this.showTitle = true,
  });

  final NoterrController controller;
  final Note note;
  final bool showTitle;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final Map<String, FocusNode> _focusNodes = {};
  String? _pendingFocusId;
  bool _showStyleControls = false;

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
                if (widget.showTitle)
                  TextField(
                    controller: _title,
                    onChanged: (value) => widget.controller
                        .updateNote(note.copyWith(title: value)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Title',
                    ),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.today_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Show as desktop sticky',
                          onPressed: () =>
                              StickyWindowService.instance.show(note),
                          icon: const Icon(Icons.open_in_new),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DailyQuoteStrip(quote: DailyQuote.forDate()),
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
                        onFocus: () => widget.controller.toggleFocusTask(
                          note,
                          item,
                        ),
                        onReminder: () => _pickReminder(item),
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
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filledTonal(
                    tooltip: 'Style and display',
                    onPressed: () => setState(
                      () => _showStyleControls = !_showStyleControls,
                    ),
                    icon: const Icon(Icons.tune),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: !_showStyleControls
                      ? const SizedBox.shrink()
                      : _StyleAndDisplayControls(
                          key: const ValueKey('style-controls'),
                          note: note,
                          onColor: (colorHex) => widget.controller.updateNote(
                            note.copyWith(colorHex: colorHex),
                          ),
                          onOpacity: (opacity) => widget.controller.updateNote(
                            note.copyWith(opacity: opacity),
                          ),
                          onPopOnDesktop: (value) =>
                              widget.controller.updateNote(
                            note.copyWith(popOnDesktop: value),
                          ),
                          onMobileWidget: (value) =>
                              widget.controller.updateNote(
                            note.copyWith(showOnMobileWidget: value),
                          ),
                          onAlwaysOnTop: (value) =>
                              widget.controller.updateNote(
                            note.copyWith(isAlwaysOnTop: value),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickReminder(ChecklistItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Later today'),
              onTap: () => Navigator.of(context).pop('today'),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Tomorrow morning'),
              onTap: () => Navigator.of(context).pop('tomorrow'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Pick time'),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            if (item.reminderAt != null)
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Remove reminder'),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
          ],
        ),
      ),
    );
    final now = DateTime.now();
    final dueAt = switch (action) {
      'today' => DateTime(now.year, now.month, now.day, 17),
      'tomorrow' => DateTime(now.year, now.month, now.day + 1, 9),
      'pick' => await _pickDateTime(now),
      'remove' => null,
      _ => null,
    };
    if (action == null) return;
    await widget.controller.setChecklistReminder(widget.note, item, dueAt);
  }

  Future<DateTime?> _pickDateTime(DateTime now) async {
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _DailyQuoteStrip extends StatelessWidget {
  const _DailyQuoteStrip({required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.auto_awesome,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            quote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.62),
                ),
          ),
        ),
      ],
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('$count tasks'),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Edit template',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete template',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Use template',
            onPressed: onTap,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      onTap: onTap,
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
    required this.onFocus,
    required this.onReminder,
    required this.onRemove,
  });

  final ChecklistItem item;
  final FocusNode focusNode;
  final VoidCallback onToggle;
  final ValueChanged<String> onText;
  final VoidCallback onEnter;
  final VoidCallback onFocus;
  final VoidCallback onReminder;
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
          color: widget.item.isFocus
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    child: Checkbox(
                      value: widget.item.done,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => widget.onToggle(),
                    ),
                  ),
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
                        decoration: widget.item.done
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight:
                            widget.item.isFocus ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete task',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 38, right: 4, top: 2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _TinyTaskAction(
                      icon: widget.item.isFocus
                          ? Icons.flag
                          : Icons.outlined_flag,
                      label: 'Now',
                      selected: widget.item.isFocus,
                      onPressed: widget.onFocus,
                    ),
                    _TinyTaskAction(
                      icon: widget.item.reminderAt == null
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                      label: 'Remind',
                      selected: widget.item.reminderAt != null,
                      onPressed: widget.onReminder,
                    ),
                    if (widget.item.reminderAt != null)
                      _TaskMetaText(
                        DateFormat('d MMM, HH:mm')
                            .format(widget.item.reminderAt!.toLocal()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyTaskAction extends StatelessWidget {
  const _TinyTaskAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _TaskMetaText extends StatelessWidget {
  const _TaskMetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _StyleAndDisplayControls extends StatelessWidget {
  const _StyleAndDisplayControls({
    super.key,
    required this.note,
    required this.onColor,
    required this.onOpacity,
    required this.onPopOnDesktop,
    required this.onMobileWidget,
    required this.onAlwaysOnTop,
  });

  final Note note;
  final ValueChanged<String> onColor;
  final ValueChanged<double> onOpacity;
  final ValueChanged<bool> onPopOnDesktop;
  final ValueChanged<bool> onMobileWidget;
  final ValueChanged<bool> onAlwaysOnTop;

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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Desktop sticky'),
              avatar: const Icon(Icons.desktop_windows, size: 16),
              selected: note.popOnDesktop,
              onSelected: onPopOnDesktop,
            ),
            FilterChip(
              label: const Text('Mobile widget'),
              avatar: const Icon(Icons.phone_android, size: 16),
              selected: note.showOnMobileWidget,
              onSelected: onMobileWidget,
            ),
            FilterChip(
              label: const Text('Always on top'),
              avatar: const Icon(Icons.vertical_align_top, size: 16),
              selected: note.isAlwaysOnTop,
              onSelected: onAlwaysOnTop,
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyReviewScreen extends StatelessWidget {
  const _DailyReviewScreen({required this.controller});

  final NoterrController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final today = controller.todayTodoNote;
        final done =
            today?.checklist.where((item) => item.done).toList() ?? const [];
        return Scaffold(
          appBar: AppBar(title: const Text('Daily review')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'What did I finish today?',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (done.isEmpty)
                const Text('No completed tasks yet.')
              else
                ...done.map(
                  (item) => ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(item.text),
                  ),
                ),
              const Divider(height: 28),
              Text(
                'Today notes',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                today?.body.trim().isEmpty == false
                    ? today!.body.trim()
                    : 'No notes written today.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryScreen extends StatefulWidget {
  const _HistoryScreen({required this.controller});

  final NoterrController controller;

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final query = _search.text.trim();
        final notes = widget.controller.historyNotes
            .where((note) => note.matchesQuery(query))
            .toList();
        final grouped = <String, Map<String, List<Note>>>{};
        for (final note in notes) {
          final date = note.createdAt.toLocal();
          final month = DateFormat('MMMM yyyy').format(date);
          final day = DateFormat('d MMM yyyy').format(date);
          grouped.putIfAbsent(month, () => <String, List<Note>>{});
          grouped[month]!.putIfAbsent(day, () => <Note>[]);
          grouped[month]![day]!.add(note);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Last 365 Days')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search history',
                  ),
                ),
              ),
              Expanded(
                child: notes.isEmpty
                    ? const Center(
                        child: Text('Nothing found in the last year.'),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          for (final month in grouped.entries)
                            ExpansionTile(
                              initiallyExpanded: true,
                              title: Text(month.key),
                              children: [
                                for (final day in month.value.entries) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      10,
                                      16,
                                      6,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        day.key,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ),
                                  for (final note in day.value)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        0,
                                        8,
                                        8,
                                      ),
                                      child: Material(
                                        color: note.isDeleted
                                            ? Theme.of(context)
                                                .colorScheme
                                                .errorContainer
                                            : noteColor(note.colorHex)
                                                .withValues(
                                                alpha: note.opacity,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: ListTile(
                                          onTap: note.isDeleted
                                              ? null
                                              : () =>
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          _ItemDetailScreen(
                                                        controller:
                                                            widget.controller,
                                                        noteId: note.id,
                                                      ),
                                                    ),
                                                  ),
                                          leading: const Icon(
                                            Icons.article_outlined,
                                          ),
                                          title: Text(
                                            note.title.isEmpty
                                                ? 'Untitled'
                                                : note.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            note.preview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SyncStatusTile extends StatelessWidget {
  const _SyncStatusTile({required this.controller});

  final NoterrController controller;

  @override
  Widget build(BuildContext context) {
    final text = _syncText(controller);
    final icon = switch (controller.syncState) {
      SyncState.offline => Icons.cloud_off,
      SyncState.idle => Icons.cloud_done,
      SyncState.syncing => Icons.cloud_sync,
      SyncState.error => Icons.error_outline,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: const Text('Sync status'),
      subtitle: Text(controller.error ?? text),
      trailing: IconButton(
        tooltip: 'Sync now',
        onPressed: controller.syncNow,
        icon: const Icon(Icons.sync),
      ),
      onTap: () => _showSyncDetails(context, controller),
    );
  }
}

String _syncText(NoterrController controller) {
  if (!controller.hasCloud) return 'Saved locally';
  final time = controller.lastSyncAt ??
      controller.lastPushAt ??
      controller.lastRemoteEventAt;
  if (time == null) return 'Sync ready';
  return 'Synced ${_ago(time)}';
}

String _ago(DateTime value) {
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inSeconds < 10) return 'now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  return '${diff.inHours}h ago';
}

void _showSyncDetails(BuildContext context, NoterrController controller) {
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
            'Account: ${account == null ? 'not signed in' : _shortValue(account)}',
            'Device: ${_shortValue(controller.deviceId)}',
            'Items here: ${controller.notes.length}',
            'Last pull count: ${controller.lastPulledCount}',
            'Last push count: ${controller.lastPushedCount}',
            'Last sync: ${_timeValue(controller.lastSyncAt)}',
            'Last push: ${_timeValue(controller.lastPushAt)}',
            'Last live event: ${_timeValue(controller.lastRemoteEventAt)}',
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

String _shortValue(String value) {
  if (value.length <= 8) return value;
  return '${value.substring(0, 8)}...';
}

String _timeValue(DateTime? value) {
  if (value == null) return 'never';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
