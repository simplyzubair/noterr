import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/noterr_controller.dart';

/// Evening planning: tick off what got done today, then write the next day's
/// tasks. Opened from the menu or from the 21:00 to 00:00 reminders.
///
/// Saving writes the next day's board straight away, so the plan survives the
/// app being closed overnight. Anything left unticked today carries over by
/// itself when the next day starts, whether or not a plan was saved.
class PlanTomorrowScreen extends StatefulWidget {
  const PlanTomorrowScreen({
    super.key,
    required this.controller,
    this.onSaved,
  });

  final NoterrController controller;

  /// Called after a plan is saved, so pending reminders can be cancelled.
  final VoidCallback? onSaved;

  @override
  State<PlanTomorrowScreen> createState() => _PlanTomorrowScreenState();
}

class _PlanTomorrowScreenState extends State<PlanTomorrowScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final List<String> _tasks = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tasks.addAll(widget.controller.plannedOwnTasks);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _addFromInput() {
    // Pasting several lines adds one task per line.
    final lines = _input.text
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*([-*]|\[ ?\])\s*'), '').trim())
        .where((l) => l.isNotEmpty);
    setState(() {
      for (final line in lines) {
        if (!_tasks.any((t) => t.toLowerCase() == line.toLowerCase())) {
          _tasks.add(line);
        }
      }
      _input.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _toggleToday(String itemId, bool done) async {
    final today = widget.controller.todayTodoNote;
    if (today == null) return;
    await widget.controller.updateNote(
      today.copyWith(
        checklist: [
          for (final item in today.checklist)
            item.id == itemId ? item.copyWith(done: done) : item,
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_input.text.trim().isNotEmpty) _addFromInput();
    setState(() => _saving = true);
    try {
      await widget.controller.savePlannedTasks(_tasks);
      widget.onSaved?.call();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(content: Text('Plan saved: ${_tasks.length} tasks')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.controller.planningTargetDay;
    final dayLabel = DateFormat('EEEE d MMM').format(target);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final today = widget.controller.todayTodoNote;
        final todayItems = today?.checklist
                .where((i) => i.text.trim().isNotEmpty)
                .toList() ??
            const [];
        final openCount = todayItems.where((i) => !i.done).length;
        final isForToday = DateUtils.isSameDay(target, DateTime.now());
        return Scaffold(
          appBar: AppBar(title: Text('Plan $dayLabel')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (!isForToday) ...[
                Text(
                  'Today',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  openCount == 0
                      ? 'Everything is done.'
                      : '$openCount still open. Tick what you finished. '
                          'The rest moves to $dayLabel by itself.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                for (final item in todayItems)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: item.done,
                    onChanged: (v) => _toggleToday(item.id, v ?? false),
                    title: Text(
                      item.text,
                      style: item.done
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                  ),
                const Divider(height: 32),
              ],
              Text(
                isForToday ? 'Today' : dayLabel,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _input,
                focusNode: _focus,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'Add a task',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Add',
                    icon: const Icon(Icons.add),
                    onPressed: _addFromInput,
                  ),
                ),
                onSubmitted: (_) => _addFromInput(),
              ),
              const SizedBox(height: 8),
              if (_tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No tasks yet.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  // newIndex already accounts for the removed item.
                  onReorderItem: (from, to) => setState(() {
                    _tasks.insert(to, _tasks.removeAt(from));
                  }),
                  children: [
                    for (final task in _tasks)
                      ListTile(
                        key: ValueKey(task),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.radio_button_unchecked),
                        title: Text(task),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _tasks.remove(task)),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save plan'),
          ),
        );
      },
    );
  }
}
