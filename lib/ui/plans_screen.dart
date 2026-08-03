import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/noterr_controller.dart';
import '../models/plan.dart';
import '../services/plan_parser.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.controller});

  final NoterrController controller;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late DateTime _weekStart;
  late DateTime _monthStart;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final today = dateOnly(DateTime.now());
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _monthStart = DateTime(today.year, today.month);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openImport([Plan? plan]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlanImportScreen(
          controller: widget.controller,
          existing: plan,
        ),
      ),
    );
  }

  Future<void> _deletePlan(Plan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete plan?'),
        content: Text('Delete ${plan.title}? Existing daily history stays.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deletePlan(plan);
  }

  void _showPlan(Plan plan) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PlanDetailSheet(
        plan: plan,
        onEdit: () {
          Navigator.of(context).pop();
          unawaited(_openImport(plan));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Plans'),
            actions: [
              IconButton(
                tooltip: 'Import plan',
                onPressed: _openImport,
                icon: const Icon(Icons.add),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(icon: Icon(Icons.description_outlined), text: 'Plans'),
                Tab(icon: Icon(Icons.view_week_outlined), text: 'Week'),
                Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Month'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _plansTab(),
              _weekTab(),
              _monthTab(),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Import plan',
            onPressed: _openImport,
            child: const Icon(Icons.post_add_outlined),
          ),
        );
      },
    );
  }

  Widget _plansTab() {
    final plans = widget.controller.plans;
    if (plans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'No plans yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openImport,
              icon: const Icon(Icons.post_add_outlined),
              label: const Text('Import plan'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      itemCount: plans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final plan = plans[index];
        final progress = _progressFor(plan);
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showPlan(plan),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _StatusPill(active: plan.isActive),
                      PopupMenuButton<String>(
                        tooltip: 'Plan actions',
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              unawaited(_openImport(plan));
                            case 'toggle':
                              unawaited(widget.controller
                                  .setPlanActive(plan, !plan.isActive));
                            case 'delete':
                              unawaited(_deletePlan(plan));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: ListTile(
                              leading: Icon(
                                plan.isActive
                                    ? Icons.pause_outlined
                                    : Icons.play_arrow,
                              ),
                              title: Text(plan.isActive ? 'Pause' : 'Activate'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    '${DateFormat('d MMM yyyy').format(plan.startDate)} - '
                    '${DateFormat('d MMM yyyy').format(plan.endDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress.ratio),
                  const SizedBox(height: 6),
                  Text(
                    '${progress.completed} completed | '
                    '${progress.missed} missed | '
                    '${plan.items.length} plan items',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _weekTab() {
    final end = _weekStart.add(const Duration(days: 6));
    final occurrences = widget.controller.planOccurrences(_weekStart, end);
    final grouped = <DateTime, List<PlanOccurrence>>{};
    for (var offset = 0; offset < 7; offset++) {
      grouped[_weekStart.add(Duration(days: offset))] = [];
    }
    for (final occurrence in occurrences) {
      grouped[dateOnly(occurrence.date)]!.add(occurrence);
    }
    return Column(
      children: [
        _RangeHeader(
          title:
              '${DateFormat('d MMM').format(_weekStart)} - ${DateFormat('d MMM').format(end)}',
          onPrevious: () => setState(
            () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
          ),
          onNext: () => setState(
            () => _weekStart = _weekStart.add(const Duration(days: 7)),
          ),
        ),
        Expanded(
          child: occurrences.isEmpty
              ? const Center(child: Text('No plan tasks this week.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                  children: [
                    for (final day in grouped.entries)
                      if (day.value.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                          child: Text(
                            DateFormat('EEEE, d MMM').format(day.key),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        for (final occurrence in day.value)
                          _OccurrenceTile(
                            occurrence: occurrence,
                            status: widget.controller
                                .planOccurrenceStatus(occurrence),
                          ),
                      ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _monthTab() {
    final end = DateTime(_monthStart.year, _monthStart.month + 1, 0);
    final occurrences = widget.controller.planOccurrences(_monthStart, end);
    final overlapping = widget.controller.plans.where((plan) {
      return plan.isActive &&
          !plan.endDate.isBefore(_monthStart) &&
          !plan.startDate.isAfter(end);
    }).toList();
    return Column(
      children: [
        _RangeHeader(
          title: DateFormat('MMMM yyyy').format(_monthStart),
          onPrevious: () => setState(
            () =>
                _monthStart = DateTime(_monthStart.year, _monthStart.month - 1),
          ),
          onNext: () => setState(
            () =>
                _monthStart = DateTime(_monthStart.year, _monthStart.month + 1),
          ),
        ),
        Expanded(
          child: overlapping.isEmpty
              ? const Center(child: Text('No active plans this month.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                  itemCount: overlapping.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final plan = overlapping[index];
                    final planOccurrences = occurrences
                        .where((item) => item.plan.id == plan.id)
                        .toList();
                    final completed = planOccurrences.where((item) {
                      return widget.controller.planOccurrenceStatus(item) ==
                          PlanOccurrenceStatus.completed;
                    }).length;
                    final due = planOccurrences.where((item) {
                      return widget.controller.planOccurrenceStatus(item) !=
                          PlanOccurrenceStatus.upcoming;
                    }).length;
                    final outcomes = plan.items.where(
                      (item) => item.kind == PlanItemKind.outcome,
                    );
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (outcomes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              for (final outcome in outcomes)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('- ${outcome.text}'),
                                ),
                            ],
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: due == 0 ? 0 : completed / due,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$completed of $due due tasks completed',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  _PlanProgress _progressFor(Plan plan) {
    final today = dateOnly(DateTime.now());
    final end = today.isBefore(plan.endDate) ? today : plan.endDate;
    if (end.isBefore(plan.startDate)) return const _PlanProgress();
    final occurrences = widget.controller
        .planOccurrences(plan.startDate, end, activeOnly: false)
        .where((item) => item.plan.id == plan.id);
    var completed = 0;
    var missed = 0;
    var total = 0;
    for (final occurrence in occurrences) {
      total++;
      switch (widget.controller.planOccurrenceStatus(occurrence)) {
        case PlanOccurrenceStatus.completed:
          completed++;
        case PlanOccurrenceStatus.missed:
          missed++;
        case PlanOccurrenceStatus.upcoming || PlanOccurrenceStatus.today:
          break;
      }
    }
    return _PlanProgress(
      completed: completed,
      missed: missed,
      total: total,
    );
  }
}

class _PlanProgress {
  const _PlanProgress({
    this.completed = 0,
    this.missed = 0,
    this.total = 0,
  });

  final int completed;
  final int missed;
  final int total;

  double get ratio => total == 0 ? 0 : completed / total;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        active ? 'Active' : 'Paused',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _RangeHeader extends StatelessWidget {
  const _RangeHeader({
    required this.title,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({required this.occurrence, required this.status});

  final PlanOccurrence occurrence;
  final PlanOccurrenceStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      PlanOccurrenceStatus.completed => (
          Icons.check_circle,
          Theme.of(context).colorScheme.primary,
        ),
      PlanOccurrenceStatus.missed => (
          Icons.history,
          Theme.of(context).colorScheme.error,
        ),
      PlanOccurrenceStatus.today => (
          Icons.radio_button_checked,
          Theme.of(context).colorScheme.tertiary,
        ),
      PlanOccurrenceStatus.upcoming => (
          Icons.radio_button_unchecked,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color, size: 20),
          title: Text(occurrence.item.text),
          subtitle: Text(occurrence.plan.title),
        ),
      ),
    );
  }
}

class _PlanDetailSheet extends StatelessWidget {
  const _PlanDetailSheet({required this.plan, required this.onEdit});

  final Plan plan;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit plan',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Text(
              '${DateFormat('d MMM yyyy').format(plan.startDate)} - '
              '${DateFormat('d MMM yyyy').format(plan.endDate)}',
            ),
            const SizedBox(height: 18),
            for (final kind in PlanItemKind.values)
              if (plan.items.any((item) => item.kind == kind)) ...[
                Text(
                  kind.label,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                for (final item
                    in plan.items.where((item) => item.kind == kind))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_kindIcon(kind), size: 20),
                    title: Text(item.text),
                    subtitle: item.createsDailyTask
                        ? Text(_scheduleText(item))
                        : null,
                  ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

IconData _kindIcon(PlanItemKind kind) => switch (kind) {
      PlanItemKind.outcome => Icons.track_changes,
      PlanItemKind.project => Icons.account_tree_outlined,
      PlanItemKind.task => Icons.check_box_outlined,
      PlanItemKind.habit => Icons.repeat,
    };

String _scheduleText(PlanItem item) {
  final days = item.weekdays.map(_shortWeekday).join(', ');
  final base = item.cadence.label;
  if (days.isNotEmpty) return '$base | $days';
  if (item.scheduledDate != null &&
      (item.cadence == PlanCadence.once ||
          item.cadence == PlanCadence.monthly)) {
    return '$base | ${DateFormat('d MMM').format(item.scheduledDate!)}';
  }
  return base;
}

String _shortWeekday(int day) => const {
      DateTime.monday: 'Mon',
      DateTime.tuesday: 'Tue',
      DateTime.wednesday: 'Wed',
      DateTime.thursday: 'Thu',
      DateTime.friday: 'Fri',
      DateTime.saturday: 'Sat',
      DateTime.sunday: 'Sun',
    }[day]!;

class PlanImportScreen extends StatefulWidget {
  const PlanImportScreen({
    super.key,
    required this.controller,
    this.existing,
  });

  final NoterrController controller;
  final Plan? existing;

  @override
  State<PlanImportScreen> createState() => _PlanImportScreenState();
}

class _PlanImportScreenState extends State<PlanImportScreen> {
  static const _parser = PlanParser();

  late final TextEditingController _title;
  late final TextEditingController _source;
  late DateTime _startDate;
  late DateTime _endDate;
  Plan? _draft;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _source = TextEditingController(text: existing?.sourceText ?? '');
    _startDate = existing?.startDate ?? today;
    _endDate = existing?.endDate ?? today.add(const Duration(days: 30));
    _draft = existing;
  }

  @override
  void dispose() {
    _title.dispose();
    _source.dispose();
    super.dispose();
  }

  void _invalidateDraft() {
    if (_draft == null && _error == null) return;
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    const types = [
      XTypeGroup(
        label: 'Text plans',
        extensions: ['txt', 'md', 'markdown'],
        mimeTypes: ['text/plain', 'text/markdown'],
      ),
    ];
    final file = await openFile(acceptedTypeGroups: types);
    if (file == null) return;
    try {
      final contents = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _source.text = contents;
        if (_title.text.trim().isEmpty) {
          _title.text = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
        }
        _draft = null;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'This file could not be read as text.');
    }
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      _startDate = dateOnly(date);
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      _draft = null;
      _error = null;
    });
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      _endDate = dateOnly(date);
      _draft = null;
      _error = null;
    });
  }

  Plan? _parse() {
    try {
      final value = _parser.parse(
        sourceText: _source.text,
        startDate: _startDate,
        endDate: _endDate,
        title: _title.text,
        existing: widget.existing,
      );
      setState(() {
        _draft = value;
        _title.text = value.title;
        _error = null;
      });
      return value;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'The plan format could not be understood.');
    }
    return null;
  }

  Future<void> _save() async {
    var plan = _draft ?? _parse();
    if (plan == null) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give this plan a name.');
      return;
    }
    plan = plan.copyWith(
      title: title,
      sourceText: _source.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
    );
    setState(() => _saving = true);
    try {
      await widget.controller.savePlan(plan);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  void _replaceItem(PlanItem item, PlanItem replacement) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(
        items: draft.items
            .map((current) => current.id == item.id ? replacement : current)
            .toList(),
      );
    });
  }

  void _removeItem(PlanItem item) {
    final draft = _draft;
    if (draft == null || draft.items.length <= 1) return;
    setState(() {
      _draft = draft.copyWith(
        items: draft.items.where((current) => current.id != item.id).toList(),
      );
    });
  }

  Future<void> _editSchedule(PlanItem item) async {
    var cadence = item.cadence;
    var selectedDays = item.weekdays.toSet();
    var anchor = item.scheduledDate ?? _startDate;
    if (cadence == PlanCadence.daily && selectedDays.isEmpty) {
      selectedDays = {
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
        DateTime.sunday,
      };
    } else if (cadence == PlanCadence.weekly && selectedDays.isEmpty) {
      selectedDays = {anchor.weekday};
    }
    final updated = await showDialog<PlanItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final usesDays =
              cadence == PlanCadence.daily || cadence == PlanCadence.weekly;
          final usesDate =
              cadence == PlanCadence.once || cadence == PlanCadence.monthly;
          return AlertDialog(
            title: const Text('Schedule'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<PlanCadence>(
                    initialValue: cadence,
                    decoration: const InputDecoration(labelText: 'Repeats'),
                    items: [
                      for (final value in PlanCadence.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        cadence = value;
                        if (cadence == PlanCadence.weekly &&
                            selectedDays.isEmpty) {
                          selectedDays = {anchor.weekday};
                        }
                      });
                    },
                  ),
                  if (usesDays) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var day = DateTime.monday;
                            day <= DateTime.sunday;
                            day++)
                          FilterChip(
                            label: Text(_shortWeekday(day).substring(0, 1)),
                            selected: selectedDays.contains(day),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedDays.add(day);
                                } else if (selectedDays.length > 1) {
                                  selectedDays.remove(day);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                  if (usesDate) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        cadence == PlanCadence.monthly
                            ? 'Day ${anchor.day} each month'
                            : DateFormat('d MMM yyyy').format(anchor),
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: anchor,
                          firstDate: _startDate,
                          lastDate: _endDate,
                        );
                        if (picked != null) {
                          setDialogState(() => anchor = dateOnly(picked));
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  item.copyWith(
                    cadence: cadence,
                    weekdays:
                        usesDays ? (selectedDays.toList()..sort()) : const [],
                    scheduledDate: anchor,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    if (updated != null) _replaceItem(item, updated);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Import plan' : 'Edit plan'),
        actions: [
          if (draft != null)
            IconButton(
              tooltip: 'Save plan',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Plan name',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _DateButton(
                        label: 'Starts',
                        date: _startDate,
                        onPressed: _pickStartDate,
                      ),
                      _DateButton(
                        label: 'Ends',
                        date: _endDate,
                        onPressed: _pickEndDate,
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Choose text file'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _source,
                    minLines: 10,
                    maxLines: 18,
                    onChanged: (_) => _invalidateDraft(),
                    decoration: const InputDecoration(
                      labelText: 'Plan text',
                      alignLabelWithHint: true,
                      hintText: 'Plan: August Health\n\nOutcomes:\n'
                          '- Lose 1 kg\n\nDaily:\n'
                          '- Walk 1 km Monday to Saturday',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (draft == null)
                    FilledButton.icon(
                      onPressed: _parse,
                      icon: const Icon(Icons.manage_search),
                      label: const Text('Review schedule'),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Review',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _parse,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Read again'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final item in draft.items)
                      _PlanItemEditor(
                        key: ValueKey(item.id),
                        item: item,
                        onChanged: (value) => _replaceItem(item, value),
                        onSchedule: item.createsDailyTask
                            ? () => _editSchedule(item)
                            : null,
                        onDelete: draft.items.length <= 1
                            ? null
                            : () => _removeItem(item),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        widget.existing == null ? 'Activate plan' : 'Save plan',
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.onPressed,
  });

  final String label;
  final DateTime date;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.event_outlined),
      label: Text('$label | ${DateFormat('d MMM yyyy').format(date)}'),
    );
  }
}

class _PlanItemEditor extends StatefulWidget {
  const _PlanItemEditor({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onSchedule,
    required this.onDelete,
  });

  final PlanItem item;
  final ValueChanged<PlanItem> onChanged;
  final VoidCallback? onSchedule;
  final VoidCallback? onDelete;

  @override
  State<_PlanItemEditor> createState() => _PlanItemEditorState();
}

class _PlanItemEditorState extends State<_PlanItemEditor> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.item.text);
  }

  @override
  void didUpdateWidget(covariant _PlanItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.item.text) _text.text = widget.item.text;
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
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_kindIcon(widget.item.kind), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      onChanged: (text) =>
                          widget.onChanged(widget.item.copyWith(text: text)),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Plan item',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Row(
                children: [
                  DropdownButton<PlanItemKind>(
                    value: widget.item.kind,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final kind in PlanItemKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(kind.label),
                        ),
                    ],
                    onChanged: (kind) {
                      if (kind != null) {
                        widget.onChanged(widget.item.copyWith(kind: kind));
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  if (widget.item.createsDailyTask)
                    TextButton.icon(
                      onPressed: widget.onSchedule,
                      icon: const Icon(Icons.event_repeat, size: 18),
                      label: Text(_scheduleText(widget.item)),
                    )
                  else
                    Text(
                      'Reference',
                      style: Theme.of(context).textTheme.bodySmall,
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
