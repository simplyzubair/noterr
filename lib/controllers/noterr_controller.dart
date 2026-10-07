import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../models/plan.dart';
import '../services/local_vault.dart';
import '../services/obsidian_sync_service.dart';
import '../services/remote_sync_service.dart';
import '../services/vault_crypto.dart';
import '../services/weekly_summary.dart';
import '../services/widget_publisher.dart';

enum SyncState { offline, idle, syncing, error }

enum PlanOccurrenceStatus { upcoming, today, completed, missed }

const _templateBoardName = 'System';
const _templateNoteTitle = '__noterr_templates_v1';
const _planBoardName = 'Plans';
const _planTag = 'noterr-plan-v1';
const Map<String, List<String>> _defaultTemplates = {
  'work': [
    'Choose today\'s one priority',
    'Clear urgent messages',
    'Deep work block',
    'Follow up before closing work',
  ],
  'calls': [
    'List people to call',
    'Make the important call first',
    'Send recap or next step',
  ],
  'shopping': [
    'Check pantry/fridge',
    'List essentials',
    'Buy only what is needed',
  ],
  'prayer': [
    'Fajr',
    'Dhuhr',
    'Asr',
    'Maghrib',
    'Isha',
    'Quran / reflection',
  ],
  'project': [
    'Define next milestone',
    'Pick one blocker',
    'Ship one small improvement',
    'Write next action',
  ],
};

class DueChecklistReminder {
  const DueChecklistReminder({
    required this.note,
    required this.item,
  });

  final Note note;
  final ChecklistItem item;

  String get key =>
      '${note.id}:${item.id}:${item.reminderAt?.toIso8601String()}';
}

class NoterrController extends ChangeNotifier {
  NoterrController({
    required LocalVault localVault,
    required RemoteSyncService remote,
    required WidgetPublisher widgetPublisher,
    ObsidianSyncService? obsidianSync,
  })  : _localVault = localVault,
        _remote = remote,
        _widgetPublisher = widgetPublisher,
        _obsidian = obsidianSync ?? ObsidianSyncService();

  final LocalVault _localVault;
  final RemoteSyncService _remote;
  final WidgetPublisher _widgetPublisher;
  final ObsidianSyncService _obsidian;

  final List<Note> _notes = [];
  final Set<String> _dirtyNoteIds = {};
  SecretKey? _key;
  StreamSubscription<RemoteNoteEnvelope>? _remoteSub;
  Timer? _syncTimer;
  Timer? _dailyTimer;
  Timer? _obsidianPollTimer;
  String? _weeklyRunKey;
  String _deviceId = '';
  String? _activeVaultSalt;
  DateTime? _lastPulledAt;
  DateTime? _lastSyncAt;
  DateTime? _lastPushAt;
  DateTime? _lastRemoteEventAt;
  int _lastPulledCount = 0;
  int _lastPushedCount = 0;
  SyncState _syncState = SyncState.offline;
  String? _error;

  bool get isUnlocked => _key != null;
  bool get hasCloud => _remote.isAvailable;
  bool get isSignedIn => !hasCloud || _remote.currentUserId != null;
  SyncState get syncState => _syncState;
  String? get error => _error;
  String get deviceId => _deviceId;
  String? get syncAccountId => _remote.currentUserId;
  DateTime? get lastSyncAt => _lastSyncAt;
  DateTime? get lastPushAt => _lastPushAt;
  DateTime? get lastRemoteEventAt => _lastRemoteEventAt;
  int get lastPulledCount => _lastPulledCount;
  int get lastPushedCount => _lastPushedCount;

  /// Returns true if this device has never set a PIN / passphrase.
  Future<bool> isFirstTimeSetup() => _localVault.hasSavedPassphrase().then((v) => !v);

  // ── Obsidian sync ──────────────────────────────────────────────────────────
  ObsidianSyncService get obsidian => _obsidian;
  bool get hasObsidianSync => _obsidian.isConfigured;

  Future<void> saveObsidianConfig(ObsidianSyncConfig config) async {
    await _obsidian.saveConfig(config);
    // Immediately push today's note if unlocked.
    final today = todayTodoNote;
    if (today != null) {
      unawaited(_obsidianPush(today));
    }
    _startObsidianPollTimer();
    notifyListeners();
  }

  Future<void> clearObsidianConfig() async {
    _obsidianPollTimer?.cancel();
    await _obsidian.clearConfig();
    notifyListeners();
  }

  List<Note> get notes => List.unmodifiable(_notes);

  List<Plan> get plans {
    final values = <Plan>[];
    for (final note in _notes) {
      if (note.isDeleted ||
          note.boardName != _planBoardName ||
          !note.tags.contains(_planTag)) {
        continue;
      }
      try {
        values.add(
          Plan.fromJson(
            Map<String, dynamic>.from(jsonDecode(note.body) as Map),
          ),
        );
      } catch (_) {
        // Keep a malformed imported plan from affecting the daily board.
      }
    }
    values.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return List.unmodifiable(values);
  }

  List<PlanOccurrence> planOccurrences(
    DateTime start,
    DateTime end, {
    bool activeOnly = true,
  }) {
    final first = dateOnly(start);
    final last = dateOnly(end);
    if (last.isBefore(first)) return const [];
    final result = <PlanOccurrence>[];
    for (final plan in plans) {
      if (activeOnly && !plan.isActive) continue;
      var date = first;
      while (!date.isAfter(last)) {
        for (final item in plan.itemsFor(date)) {
          result.add(PlanOccurrence(plan: plan, item: item, date: date));
        }
        date = date.add(const Duration(days: 1));
      }
    }
    result.sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      if (dateOrder != 0) return dateOrder;
      return a.item.text.toLowerCase().compareTo(b.item.text.toLowerCase());
    });
    return result;
  }

  PlanOccurrenceStatus planOccurrenceStatus(PlanOccurrence occurrence) {
    final matchingItems = _notes
        .where((note) => !note.isDeleted)
        .expand((note) => note.checklist)
        .where((item) {
      return item.planId == occurrence.plan.id &&
          item.planItemId == occurrence.item.id &&
          item.scheduledFor != null &&
          isSamePlanDate(item.scheduledFor!, occurrence.date);
    });
    if (matchingItems.any((item) => item.done)) {
      return PlanOccurrenceStatus.completed;
    }
    final today = dateOnly(DateTime.now());
    if (occurrence.date.isBefore(today)) return PlanOccurrenceStatus.missed;
    if (isSamePlanDate(occurrence.date, today)) {
      return PlanOccurrenceStatus.today;
    }
    return PlanOccurrenceStatus.upcoming;
  }

  Plan? planById(String? id) {
    if (id == null) return null;
    return plans.where((plan) => plan.id == id).firstOrNull;
  }

  Map<String, List<String>> get templates {
    final saved = _templateNote;
    if (saved == null || saved.body.trim().isEmpty) {
      return Map.unmodifiable(_defaultTemplates);
    }
    try {
      final raw = jsonDecode(saved.body) as Map<String, dynamic>;
      final parsed = raw.map((key, value) {
        final items = ((value as List?) ?? const [])
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        return MapEntry(key, items);
      })
        ..removeWhere((_, items) => items.isEmpty);
      if (parsed.isEmpty) return Map.unmodifiable(_defaultTemplates);
      return Map.unmodifiable(parsed);
    } catch (_) {
      return Map.unmodifiable(_defaultTemplates);
    }
  }

  Note? get _templateNote {
    for (final note in _notes) {
      if (!note.isDeleted &&
          note.boardName == _templateBoardName &&
          note.title == _templateNoteTitle) {
        return note;
      }
    }
    return null;
  }

  Note? _planNoteById(String id) {
    for (final note in _notes) {
      if (note.isDeleted ||
          note.boardName != _planBoardName ||
          !note.tags.contains(_planTag)) {
        continue;
      }
      try {
        final plan = Plan.fromJson(
          Map<String, dynamic>.from(jsonDecode(note.body) as Map),
        );
        if (plan.id == id) return note;
      } catch (_) {}
    }
    return null;
  }

  Future<void> savePlan(Plan value) async {
    final plan = value.copyWith(updatedAt: DateTime.now().toUtc());
    final encoded = const JsonEncoder.withIndent('  ').convert(plan.toJson());
    final existing = _planNoteById(plan.id);
    if (existing == null) {
      final note = Note.blank(_deviceId, type: NoteType.note).copyWith(
        title: plan.title,
        body: encoded,
        boardName: _planBoardName,
        tags: [_planTag, 'plan:${plan.id}'],
        isArchived: true,
        isPinned: false,
        popOnDesktop: false,
        showOnMobileWidget: false,
      );
      _notes.add(note);
      await _persistAndPush(note);
    } else {
      await updateNote(
        existing.copyWith(
          title: plan.title,
          body: encoded,
          tags: [_planTag, 'plan:${plan.id}'],
          isArchived: true,
          popOnDesktop: false,
          showOnMobileWidget: false,
        ),
      );
    }
    await _materializePlanItemsForToday();
  }

  Future<void> setPlanActive(Plan plan, bool active) async {
    await savePlan(plan.copyWith(isActive: active));
    if (!active) await _removePendingPlanTasksFromToday(plan.id);
  }

  Future<void> deletePlan(Plan plan) async {
    final note = _planNoteById(plan.id);
    if (note == null) return;
    await _removePendingPlanTasksFromToday(plan.id);
    await softDeleteNote(note);
  }

  Future<void> _removePendingPlanTasksFromToday(String planId) async {
    final today = todayTodoNote;
    if (today == null) return;
    final pending = today.checklist
        .where((item) => item.planId == planId && !item.done)
        .toList();
    if (pending.isEmpty) return;
    await updateNote(
      today.copyWith(
        checklist: today.checklist
            .where((item) => item.planId != planId || item.done)
            .toList(),
        deletedChecklistItemKeys: _deletedChecklistKeys(today, pending),
      ),
    );
  }

  List<Note> visibleNotes({
    String query = '',
    String? boardName,
    String? tag,
    bool archived = false,
    bool trash = false,
  }) {
    return _notes.where((note) {
      if (trash) return note.isDeleted && note.matchesQuery(query);
      if (archived != note.isArchived) return false;
      if (note.isDeleted) return false;
      if (boardName != null &&
          boardName.isNotEmpty &&
          note.boardName != boardName) {
        return false;
      }
      if (tag != null && tag.isNotEmpty && !note.tags.contains(tag)) {
        return false;
      }
      return note.matchesQuery(query);
    }).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  List<String> get allTags {
    final tags = _notes.expand((note) => note.tags).toSet().toList();
    tags.sort();
    return tags;
  }

  List<String> get allBoards {
    final boards = _notes
        .where((note) => !note.isDeleted)
        .map((note) =>
            note.boardName.trim().isEmpty ? 'Personal' : note.boardName)
        .toSet()
        .toList();
    if (boards.isEmpty) boards.add('Personal');
    boards.sort();
    return boards;
  }

  Note? get todayTodoNote {
    final now = DateTime.now();
    return _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.supportsChecklist &&
          note.boardName == 'Today' &&
          _isSameLocalDay(note.dayKey, now);
    }).firstOrNull;
  }

  List<Note> get stickyNotes {
    return _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.id != todayTodoNote?.id &&
          !_isFutureDailyBoard(note) &&
          note.type != NoteType.checklist;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<Note> get workspaceItems {
    final daily = todayTodoNote;
    return daily == null ? const [] : [daily];
  }

  List<Note> get historyNotes {
    final oldest = DateTime.now().toUtc().subtract(const Duration(days: 365));
    return _notes.where((note) {
      return !note.isDeleted &&
          note.isArchived &&
          note.boardName == 'History' &&
          note.createdAt.isAfter(oldest);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<DueChecklistReminder> get dueChecklistReminders {
    final now = DateTime.now().toUtc();
    final reminders = <DueChecklistReminder>[];
    for (final note in _notes) {
      if (note.isDeleted || note.isArchived) continue;
      for (final item in note.checklist) {
        final dueAt = item.reminderAt;
        if (item.done || item.reminderDone || dueAt == null) continue;
        if (!dueAt.toUtc().isAfter(now)) {
          reminders.add(DueChecklistReminder(note: note, item: item));
        }
      }
    }
    reminders.sort(
      (a, b) => a.item.reminderAt!.compareTo(b.item.reminderAt!),
    );
    return reminders;
  }

  // ── Weekly summary ───────────────────────────────────────────────────────

  static const weeklySummaryBoard = 'Weekly Summary';

  /// Writes the weekly summary as a Noterr note and an Obsidian page.
  ///
  /// From Sunday 06:00 it summarises the current week so far (Monday to
  /// today). From Monday on, it writes the finished Monday-to-Sunday summary
  /// for the week before, once, and tags it `final`. Safe to call often.
  Future<void> maybeWriteWeeklySummary({DateTime? now}) async {
    if (_key == null) return;
    final at = now ?? DateTime.now();
    final bool isFinal;
    final DateTime weekStart;
    if (at.weekday == DateTime.sunday) {
      if (at.hour < 6) return;
      weekStart = mondayOf(at);
      isFinal = false;
    } else {
      weekStart = mondayOf(at).subtract(const Duration(days: 7));
      isFinal = true;
    }
    final summary = WeeklySummary.compute(
      _notes,
      weekStart,
      until: isFinal ? null : at,
    );
    final runKey = '${summary.isoWeek}:${isFinal ? 'final' : _dayOnly(at)}';
    if (_weeklyRunKey == runKey) return;
    _weeklyRunKey = runKey;

    final title = 'Week ${summary.isoWeek}';
    final existing = _notes.where((note) {
      return !note.isDeleted &&
          note.boardName == weeklySummaryBoard &&
          note.title == title;
    }).firstOrNull;
    if (isFinal && existing != null && existing.tags.contains('final')) return;
    // Nothing happened that week (for example a fresh install): no page.
    if (summary.total == 0 && existing == null) return;

    final body = summary.toPlainText();
    final tags = ['weekly-summary', if (isFinal) 'final'];
    if (existing == null) {
      final note = Note.blank(_deviceId, type: NoteType.note).copyWith(
        title: title,
        body: body,
        boardName: weeklySummaryBoard,
        tags: tags,
        colorHex: 'E3F2FD',
        popOnDesktop: false,
        showOnMobileWidget: false,
      );
      _notes.add(note);
      await _persistAndPush(note);
    } else if (existing.body != body || !listEquals(existing.tags, tags)) {
      await updateNote(existing.copyWith(body: body, tags: tags));
    }

    if (_obsidian.isConfigured) {
      try {
        await _obsidian.writeWeeklySummary(
          summary.isoWeek,
          summary.toMarkdown(),
        );
      } catch (e) {
        debugPrint('[WeeklySummary] Obsidian write failed: $e');
      }
    }
  }

  // ── Planning the next day ────────────────────────────────────────────────

  /// The day an evening planning session is for. Reminders run from 21:00 to
  /// 00:00; the midnight one belongs to the evening before, so before 04:00
  /// the target is the day that has just started.
  DateTime get planningTargetDay {
    final now = DateTime.now();
    final today = _dayOnly(now);
    return now.hour < 4 ? today : today.add(const Duration(days: 1));
  }

  /// The daily board for [planningTargetDay], if it exists yet.
  Note? get plannedDayNote => _dailyBoardFor(planningTargetDay);

  /// True once the user has written at least one task for the target day.
  /// Tasks carried over automatically don't count; they aren't a plan.
  bool get hasPlannedNextDay => isDayPlanned(planningTargetDay);

  /// Whether the user wrote any task of their own for [day].
  bool isDayPlanned(DateTime day) {
    final board = _dailyBoardFor(day);
    if (board == null) return false;
    return board.checklist.any(
      (item) => _isOwnPlannedTask(item) && item.text.trim().isNotEmpty,
    );
  }

  /// A task the user typed for that day, as opposed to one carried over from
  /// an earlier day or generated by a Plan.
  bool _isOwnPlannedTask(ChecklistItem item) =>
      item.carriedFrom == null && item.planId == null;

  /// The user's own tasks already planned for [planningTargetDay].
  List<String> get plannedOwnTasks {
    final board = plannedDayNote;
    if (board == null) return const [];
    return board.checklist
        .where((i) => _isOwnPlannedTask(i) && i.text.trim().isNotEmpty)
        .map((i) => i.text.trim())
        .toList();
  }

  /// Open tasks on today's board, shown at planning time so they can be
  /// ticked off before they carry over to the next day.
  List<ChecklistItem> get openTasksToday {
    final today = todayTodoNote;
    if (today == null) return const [];
    return today.checklist
        .where((item) => !item.done && item.text.trim().isNotEmpty)
        .toList();
  }

  /// Gets or creates the board for [planningTargetDay]. Written straight
  /// away, with its own [Note.noteDate], so a plan made at 21:00 is safe even
  /// if the app is killed overnight.
  Future<Note> ensurePlannedDayNote() async {
    final day = planningTargetDay;
    final existing = _dailyBoardFor(day);
    if (existing != null) return existing;
    if (_isSameLocalDay(day, DateTime.now())) return ensureTodayTodoNote();
    final board = _newTodayBoard(day);
    _notes.add(board);
    await _persistAndPush(board);
    return board;
  }

  /// Replaces the user's own tasks on the planned board with [texts], keeping
  /// carried-over and Plan-generated ones. Blank lines and duplicates are
  /// dropped.
  Future<void> savePlannedTasks(List<String> texts) async {
    final board = await ensurePlannedDayNote();
    final carried = board.checklist
        .where((item) => !_isOwnPlannedTask(item))
        .toList();
    final seen = carried.map((i) => i.text.trim().toLowerCase()).toSet();
    final ownByText = {
      for (final item in board.checklist.where(_isOwnPlannedTask))
        item.text.trim().toLowerCase(): item,
    };
    final own = <ChecklistItem>[];
    for (final raw in texts) {
      final text = raw.trim();
      final key = text.toLowerCase();
      if (text.isEmpty || !seen.add(key)) continue;
      own.add(ownByText[key] ?? ChecklistItem(text: text));
    }
    await updateNote(board.copyWith(checklist: [...own, ...carried]));
  }

  Note? _dailyBoardFor(DateTime day) {
    return _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          _isDailyBoard(note) &&
          _isSameLocalDay(note.dayKey, day);
    }).firstOrNull;
  }

  Future<Note> ensureTodayTodoNote() async {
    await _rollDailyBoardIfNeeded();
    var note = todayTodoNote;
    final now = DateTime.now();
    final title = _dailyTitle(now);
    if (note != null) {
      if (note.title != title) {
        final updated = _touch(note.copyWith(title: title));
        await _persistAndPush(updated);
        note = updated;
      }
    } else {
      note = _newTodayBoard(now);
      _notes.add(note);
      await _persistAndPush(note);
    }
    return _materializePlanItems(note, now);
  }

  Future<void> _materializePlanItemsForToday() async {
    await ensureTodayTodoNote();
  }

  Future<Note> _materializePlanItems(Note note, DateTime value) async {
    final date = dateOnly(value);
    final activePlans = plans.where(
      (plan) => plan.isActive && plan.isInRange(date),
    );
    final occurrences = <PlanOccurrence>[
      for (final plan in activePlans)
        for (final item in plan.itemsFor(date))
          PlanOccurrence(plan: plan, item: item, date: date),
    ];
    if (occurrences.isEmpty) return note;

    final checklist = [...note.checklist];
    final existingIds = checklist.map((item) => item.id).toSet();
    final existingTexts = checklist
        .where((item) => !item.done)
        .map((item) => item.text.trim().toLowerCase())
        .where((text) => text.isNotEmpty)
        .toSet();
    final deletedIds = note.deletedChecklistItemKeys
        .where((key) => key.startsWith('id:'))
        .map((key) => key.substring(3))
        .toSet();
    var changed = false;
    for (final occurrence in occurrences) {
      final id = occurrence.id;
      final text = occurrence.item.text.trim();
      final carriedIndex = checklist.indexWhere((item) {
        return !item.done &&
            item.planId == occurrence.plan.id &&
            item.planItemId == occurrence.item.id;
      });
      if (carriedIndex != -1) {
        final current = checklist[carriedIndex];
        if (!existingIds.contains(id) &&
            !deletedIds.contains(id) &&
            (current.scheduledFor == null ||
                !isSamePlanDate(current.scheduledFor!, date))) {
          checklist[carriedIndex] = ChecklistItem(
            id: id,
            text: current.text,
            done: current.done,
            isFocus: current.isFocus,
            carriedFrom: current.carriedFrom,
            reminderAt: current.reminderAt,
            reminderDone: current.reminderDone,
            planId: occurrence.plan.id,
            planItemId: occurrence.item.id,
            scheduledFor: date,
          );
          existingIds
            ..remove(current.id)
            ..add(id);
          changed = true;
        }
        continue;
      }
      if (text.isEmpty ||
          existingIds.contains(id) ||
          deletedIds.contains(id) ||
          existingTexts.contains(text.toLowerCase())) {
        continue;
      }
      checklist.add(
        ChecklistItem(
          id: id,
          text: text,
          planId: occurrence.plan.id,
          planItemId: occurrence.item.id,
          scheduledFor: date,
        ),
      );
      existingIds.add(id);
      existingTexts.add(text.toLowerCase());
      changed = true;
    }
    if (!changed) return note;

    final updated = _touch(note.copyWith(checklist: checklist));
    await _persistAndPush(updated);
    return updated;
  }

  Future<void> addTodayNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final note = await ensureTodayTodoNote();
    final body = note.body.trim();
    final nextBody = body.isEmpty ? trimmed : '$body\n\n$trimmed';
    await updateNote(note.copyWith(body: nextBody));
  }

  Future<void> addTodayTask(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final note = await ensureTodayTodoNote();
    await updateNote(
      note.copyWith(
        checklist: [
          ...note.checklist,
          ChecklistItem(text: trimmed),
        ],
        deletedChecklistItemKeys: _reviveChecklistText(
          note.deletedChecklistItemKeys,
          trimmed,
        ),
      ),
    );
  }

  Future<ChecklistItem> addTodayTaskAfter(ChecklistItem item) async {
    final note = await ensureTodayTodoNote();
    final items = [...note.checklist];
    final next = ChecklistItem(text: '');
    final index = items.indexWhere((current) => current.id == item.id);
    if (index == -1) {
      items.add(next);
    } else {
      items.insert(index + 1, next);
    }
    await updateNote(
      note.copyWith(
        checklist: items,
        deletedChecklistItemKeys: _reviveChecklistText(
          note.deletedChecklistItemKeys,
          next.text,
        ),
      ),
    );
    return next;
  }

  Future<void> updateTodayTask(ChecklistItem item, String text) async {
    final note = await ensureTodayTodoNote();
    await updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(text: text)
                  : current,
            )
            .toList(),
      ),
    );
  }

  Future<void> toggleTodayTask(ChecklistItem item) async {
    final note = await ensureTodayTodoNote();
    await updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(done: !current.done)
                  : current,
            )
            .toList(),
      ),
    );
  }

  Future<void> removeTodayTask(ChecklistItem item) async {
    final note = await ensureTodayTodoNote();
    await updateNote(
      note.copyWith(
        checklist:
            note.checklist.where((current) => current.id != item.id).toList(),
        deletedChecklistItemKeys: _deletedChecklistKeys(note, [item]),
      ),
    );
  }

  Future<ChecklistItem> addChecklistItem(Note note, {String text = ''}) async {
    final next = ChecklistItem(text: text);
    await updateNote(
      note.copyWith(
        checklist: [...note.checklist, next],
        deletedChecklistItemKeys: _reviveChecklistText(
          note.deletedChecklistItemKeys,
          text,
        ),
      ),
    );
    return next;
  }

  Future<ChecklistItem> addChecklistItemAfter(
      Note note, ChecklistItem item) async {
    final next = ChecklistItem(text: '');
    final items = [...note.checklist];
    final index = items.indexWhere((current) => current.id == item.id);
    if (index == -1) {
      items.add(next);
    } else {
      items.insert(index + 1, next);
    }
    await updateNote(
      note.copyWith(
        checklist: items,
        deletedChecklistItemKeys: _reviveChecklistText(
          note.deletedChecklistItemKeys,
          next.text,
        ),
      ),
    );
    return next;
  }

  Future<void> updateChecklistItem(
    Note note,
    ChecklistItem item,
    String text,
  ) {
    return updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(text: text)
                  : current,
            )
            .toList(),
        deletedChecklistItemKeys: _reviveChecklistText(
          note.deletedChecklistItemKeys,
          text,
        ),
      ),
    );
  }

  Future<void> toggleFocusTask(Note note, ChecklistItem item) {
    final shouldFocus = !item.isFocus;
    return updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(isFocus: shouldFocus)
                  : current.copyWith(isFocus: false),
            )
            .toList(),
      ),
    );
  }

  Future<void> setChecklistReminder(
    Note note,
    ChecklistItem item,
    DateTime? dueAt,
  ) {
    return updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(
                      reminderAt: dueAt?.toUtc(),
                      clearReminder: dueAt == null,
                      reminderDone: false,
                    )
                  : current,
            )
            .toList(),
      ),
    );
  }

  Future<void> dismissChecklistReminder(Note note, ChecklistItem item) {
    return updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(reminderDone: true)
                  : current,
            )
            .toList(),
      ),
    );
  }

  Future<void> toggleChecklistItem(Note note, ChecklistItem item) {
    return updateNote(
      note.copyWith(
        checklist: note.checklist
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(done: !current.done)
                  : current,
            )
            .toList(),
      ),
    );
  }

  Future<void> removeChecklistItem(Note note, ChecklistItem item) {
    final deletedKeys = _deletedChecklistKeys(note, [item]);
    return updateNote(
      note.copyWith(
        checklist:
            note.checklist.where((current) => current.id != item.id).toList(),
        deletedChecklistItemKeys: deletedKeys,
      ),
    );
  }

  Future<void> clearDoneTodayTasks() async {
    final note = await ensureTodayTodoNote();
    final done = note.checklist.where((item) => item.done).toList();
    await updateNote(
      note.copyWith(
        checklist: note.checklist.where((item) => !item.done).toList(),
        deletedChecklistItemKeys: _deletedChecklistKeys(note, done),
      ),
    );
  }

  Future<void> applyTemplate(String name) async {
    final tasks = templates[name] ?? const <String>[];
    for (final task in tasks) {
      await addTodayTask(task);
    }
  }

  Future<void> saveTemplate(String name, List<String> tasks) async {
    final key = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final cleaned = tasks
        .map((task) => task.trim())
        .where((task) => task.isNotEmpty)
        .toList();
    if (key.isEmpty || cleaned.isEmpty) return;
    final nextTemplates = Map<String, List<String>>.from(templates)
      ..[key] = cleaned;
    await _saveTemplates(nextTemplates);
  }

  Future<void> deleteTemplate(String name) async {
    final nextTemplates = Map<String, List<String>>.from(templates)
      ..remove(name);
    if (nextTemplates.isEmpty) {
      nextTemplates.addAll(_defaultTemplates);
    }
    await _saveTemplates(nextTemplates);
  }

  Future<void> resetTemplates() {
    return _saveTemplates(Map<String, List<String>>.from(_defaultTemplates));
  }

  Future<void> _saveTemplates(Map<String, List<String>> value) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    final existing = _templateNote;
    if (existing == null) {
      final note = Note.blank(_deviceId, type: NoteType.note).copyWith(
        title: _templateNoteTitle,
        body: encoded,
        boardName: _templateBoardName,
        isArchived: true,
        popOnDesktop: false,
        showOnMobileWidget: false,
      );
      _notes.add(note);
      await _persistAndPush(note);
      return;
    }
    await updateNote(existing.copyWith(body: encoded));
  }

  List<Note> dueReminderNotes(DateTime now) {
    return _notes.where((note) {
      final dueAt = note.reminder.dueAt;
      return !note.isDeleted &&
          !note.reminder.completed &&
          dueAt != null &&
          !dueAt.toUtc().isAfter(now.toUtc());
    }).toList()
      ..sort((a, b) => a.reminder.dueAt!.compareTo(b.reminder.dueAt!));
  }

  Future<void> signOut() async {
    _syncTimer?.cancel();
    _dailyTimer?.cancel();
    _obsidianPollTimer?.cancel();
    await _remoteSub?.cancel();
    await _localVault.clearSavedPassphrase();
    await _remote.closeSyncProfile();
    _key = null;
    _notes.clear();
    notifyListeners();
  }

  Future<void> lock() async {
    _syncTimer?.cancel();
    _dailyTimer?.cancel();
    _obsidianPollTimer?.cancel();
    await _remoteSub?.cancel();
    _key = null;
    _notes.clear();
    _syncState = hasCloud ? SyncState.idle : SyncState.offline;
    notifyListeners();
  }

  Future<void> unlock(String passphrase) async {
    if (passphrase.trim().isEmpty) {
      throw ArgumentError('Enter a sync passkey.');
    }
    final cleanPassphrase = passphrase.trim();
    _deviceId = await _localVault.getOrCreateDeviceId();
    if (hasCloud) {
      final cachedSalt = await _localVault.readCachedVaultSalt();
      if (cachedSalt != null) {
        try {
          await _openLocalVault(cleanPassphrase, cachedSalt);
          await _finishUnlock(cleanPassphrase);
          return;
        } catch (_) {
          // Older builds may have cached the wrong salt. Retry online below.
        }
      }

      final fallbackSalt =
          await _localVault.readCachedVaultSalt() ?? VaultCrypto.randomSalt();
      await _remote.openSyncProfile(
        cleanPassphrase,
        vaultSalt: fallbackSalt,
      );
      final cloudSalt = await _remote.getOrCreateVaultSalt();
      await _localVault.saveCachedVaultSalt(cloudSalt);
      await _openLocalVault(
        cleanPassphrase,
        cloudSalt,
        allowEmptyCloudRecovery: true,
      );
      await _finishUnlock(cleanPassphrase);
      return;
    }

    // A vault first written by a build that had cloud sync was encrypted with
    // the salt cached from the server, not the local one. Such a vault opens
    // only with that cached salt, so try it before giving up, otherwise every
    // passphrase looks wrong here.
    final salt = await _localVault.getOrCreateLocalSalt();
    try {
      await _openLocalVault(cleanPassphrase, salt);
    } catch (_) {
      final cachedSalt = await _localVault.readCachedVaultSalt();
      if (cachedSalt == null || cachedSalt == salt) rethrow;
      await _openLocalVault(cleanPassphrase, cachedSalt);
    }
    await _finishUnlock(cleanPassphrase);
  }

  Future<void> _openLocalVault(
    String passphrase,
    String salt, {
    bool allowEmptyCloudRecovery = false,
  }) async {
    _key = await VaultCrypto.deriveKey(passphrase: passphrase, salt: salt);
    _activeVaultSalt = salt;

    LocalVaultSnapshot snapshot;
    try {
      snapshot = await _localVault.load(_key!);
    } catch (_) {
      if (!allowEmptyCloudRecovery) {
        _key = null;
        _activeVaultSalt = null;
        rethrow;
      }
      await _localVault.backUpVault(suffix: 'local-only-backup');
      snapshot = const LocalVaultSnapshot(notes: [], lastPulledAt: null);
    }
    _notes
      ..clear()
      ..addAll(snapshot.notes);
    _lastPulledAt = snapshot.lastPulledAt;
    _syncState = hasCloud ? SyncState.idle : SyncState.offline;
    notifyListeners();
  }

  Future<void> _finishUnlock(String passphrase) async {
    await ensureTodayTodoNote();
    if (!hasCloud || _remote.currentUserId != null) {
      _subscribeRemote();
    }
    _startDailyTimer();
    await _localVault.savePassphrase(passphrase);
    await _widgetPublisher.configureLiveWidgetSync(
      passphrase,
      vaultSalt: _activeVaultSalt,
    );
    await _publishWidget();
    // Load Obsidian config and start sync.
    await _obsidian.loadConfig();
    final today = todayTodoNote;
    if (today != null && _obsidian.isConfigured) {
      unawaited(_obsidianPush(today));
    }
    _startObsidianPollTimer();
    unawaited(maybeWriteWeeklySummary());
    if (hasCloud) {
      unawaited(_finishCloudUnlock(passphrase));
    }
  }

  Future<void> _finishCloudUnlock(String passphrase) async {
    try {
      final fallbackSalt =
          await _localVault.readCachedVaultSalt() ?? VaultCrypto.randomSalt();
      await _remote.openSyncProfile(passphrase, vaultSalt: fallbackSalt);
      final salt = await _remote.getOrCreateVaultSalt();
      await _localVault.saveCachedVaultSalt(salt);
      await _widgetPublisher.configureLiveWidgetSync(
        passphrase,
        vaultSalt: salt,
      );
      if (_activeVaultSalt != salt) {
        await _openLocalVault(
          passphrase,
          salt,
          allowEmptyCloudRecovery: true,
        );
      }
      await syncNow();
      _subscribeRemote();
      _startSyncTimer();
    } catch (error) {
      _setError(error.toString());
    }
  }

  Future<bool> unlockSavedDevice() async {
    final passphrase = await _localVault.readSavedPassphrase();
    if (passphrase == null || passphrase.trim().isEmpty) return false;
    try {
      await unlock(passphrase);
      return true;
    } catch (_) {
      rethrow;
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (!hasCloud || _key == null) return;
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_syncState == SyncState.syncing) return;
      unawaited(syncNow());
    });
  }

  void _startDailyTimer() {
    _dailyTimer?.cancel();
    if (_key == null) return;
    _dailyTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(ensureTodayTodoNote());
      unawaited(maybeWriteWeeklySummary());
    });
  }

  void _startObsidianPollTimer() {
    _obsidianPollTimer?.cancel();
    if (!_obsidian.isConfigured || _key == null) return;
    _obsidianPollTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_obsidianPoll()),
    );
  }

  /// Push Noterr → Obsidian daily note.
  Future<void> _obsidianPush(Note note) async {
    if (!_obsidian.isConfigured) return;
    try {
      // Write to the note's own day, so tomorrow's plan lands in tomorrow's file.
      await _obsidian.push(note, note.dayKey);
    } catch (e) {
      debugPrint('[ObsidianSync] push error: $e');
    }
  }

  /// Poll Obsidian daily note → Noterr (pick up external edits).
  Future<void> _obsidianPoll() async {
    if (!_obsidian.isConfigured || _key == null) return;
    final today = todayTodoNote;
    if (today == null) return;
    try {
      final result = await _obsidian.pull(today, DateTime.now());
      if (!result.hasChanges) return;

      Note updated = today;

      // Merge new body lines
      if (result.addedBodyLines.isNotEmpty) {
        final extra = result.addedBodyLines.join('\n');
        final body  = updated.body.trim();
        updated = updated.copyWith(
          body: body.isEmpty ? extra : '$body\n\n$extra',
        );
      }

      // Add new tasks
      if (result.addedTasks.isNotEmpty) {
        final newItems = result.addedTasks
            .map((t) => ChecklistItem(text: t.text, done: t.done))
            .toList();
        updated = updated.copyWith(
          checklist: [...updated.checklist, ...newItems],
        );
      }

      // Update done-state of tasks that changed in Obsidian
      if (result.updatedTasks.isNotEmpty) {
        final byText = {for (final t in result.updatedTasks) t.text.toLowerCase(): t};
        final checklist = updated.checklist.map((item) {
          final obsTask = byText[item.text.trim().toLowerCase()];
          if (obsTask == null) return item;
          return item.copyWith(done: obsTask.done);
        }).toList();
        updated = updated.copyWith(checklist: checklist);
      }

      await updateNote(updated);
    } catch (e) {
      debugPrint('[ObsidianSync] poll error: $e');
    }
  }

  Future<Note> createNote({
    String boardName = 'Personal',
    NoteType type = NoteType.note,
    String? title,
    String? body,
  }) async {
    final note = Note.blank(_deviceId, type: type).copyWith(
      boardName: boardName,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : switch (type) {
              NoteType.note => 'Sticky note',
              NoteType.checklist => 'Checklist',
              NoteType.full => 'Full note',
            },
      body: body,
    );
    _notes.add(note);
    await _persistAndPush(note);
    return note;
  }

  Future<void> updateNote(Note note) async {
    final current = _findNote(note.id);
    final bodyWasCleared = current != null &&
        current.body.trim().isNotEmpty &&
        note.body.trim().isEmpty &&
        note.supportsBody;
    final changed = note.copyWith(
      updatedAt: DateTime.now().toUtc(),
      revision: note.revision + 1,
      deviceId: _deviceId,
      bodyClearedAt: bodyWasCleared ? DateTime.now().toUtc() : null,
    );
    _replace(changed);
    await _persistAndPush(changed);
  }

  Future<void> archiveNote(Note note, bool archived) {
    return updateNote(note.copyWith(isArchived: archived));
  }

  Future<void> softDeleteNote(Note note) {
    return updateNote(
      note.copyWith(
        isDeleted: true,
        deletedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> restoreNote(Note note) {
    return updateNote(note.copyWith(isDeleted: false));
  }

  Future<void> snoozeReminder(Note note, Duration duration) {
    return updateNote(
      note.copyWith(
        reminder: NoteReminder(
          dueAt: DateTime.now().toUtc().add(duration),
          repeatRule: note.reminder.repeatRule,
        ),
      ),
    );
  }

  Future<void> dismissReminder(Note note) {
    return updateNote(
      note.copyWith(
        reminder: NoteReminder(
          dueAt: note.reminder.dueAt,
          repeatRule: note.reminder.repeatRule,
          completed: true,
        ),
      ),
    );
  }

  Future<void> syncNow() async {
    final key = _key;
    if (!hasCloud || key == null) return;
    _setSync(SyncState.syncing);
    try {
      final since = _lastPulledAt?.subtract(const Duration(seconds: 5));
      final remoteNotes = await _remote.pullNotes(key, since: since);
      _lastPulledCount = remoteNotes.length;
      _merge(remoteNotes);
      await _rollDailyBoardIfNeeded();
      await _materializePlanItemsForToday();
      final shouldBackfillCloud = remoteNotes.isEmpty &&
          _lastPulledAt == null &&
          _notes.any((note) => !note.isDeleted);
      final notesToPush = shouldBackfillCloud
          ? _notes
          : _notes.where((note) => _dirtyNoteIds.contains(note.id)).toList();
      var pushed = 0;
      for (final note in notesToPush) {
        await _remote.pushNote(note, key, _deviceId);
        _dirtyNoteIds.remove(note.id);
        pushed++;
      }
      _lastPushedCount = pushed;
      _lastPulledAt = DateTime.now().toUtc();
      _lastSyncAt = _lastPulledAt;
      await _saveLocal();
      await _publishWidget();
      notifyListeners();
      _setSync(SyncState.idle);
    } catch (error) {
      _setError(error.toString());
    }
  }

  Future<void> saveNow() async {
    await ensureTodayTodoNote();
    await _saveLocal();
    await _publishWidget();
    notifyListeners();
    if (hasCloud) {
      await syncNow();
    }
  }

  void _subscribeRemote() {
    final key = _key;
    if (!hasCloud || key == null) return;
    _remoteSub?.cancel();
    _remoteSub = _remote.watchNoteEnvelopes().listen((envelope) async {
      if (envelope.deviceId == _deviceId) return;
      try {
        final payload = EncryptedPayload(
          cipherText: envelope.encryptedPayload,
          nonce: envelope.nonce,
          mac: envelope.mac,
        );
        final json = await VaultCrypto.decryptJson(payload, key);
        final note = Note.fromJson(json);
        _merge([note]);
        await _rollDailyBoardIfNeeded();
        await _materializePlanItemsForToday();
        _lastRemoteEventAt = DateTime.now().toUtc();
        await _saveLocal();
        await _publishWidget();
        notifyListeners();
      } catch (error) {
        _setError(error.toString());
      }
    });
  }

  Future<void> _persistAndPush(Note note) async {
    _replace(note);
    await _saveLocal();
    await _publishWidget();
    notifyListeners();
    // Push to Obsidian if this is the today daily note.
    if (_isDailyBoard(note) && !note.isDeleted && !note.isArchived) {
      unawaited(_obsidianPush(note));
    }
    if (!hasCloud || _key == null) return;
    try {
      _setSync(SyncState.syncing);
      await _remote.pushNote(note, _key!, _deviceId);
      _dirtyNoteIds.remove(note.id);
      _lastPushAt = DateTime.now().toUtc();
      _lastPushedCount = 1;
      _setSync(SyncState.idle);
    } catch (error) {
      _dirtyNoteIds.add(note.id);
      _setError(error.toString());
    }
  }

  void _replace(Note note) {
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      _notes.add(note);
    } else {
      _notes[index] = note;
    }
  }

  void _merge(List<Note> incoming) {
    for (final note in incoming) {
      final index = _notes.indexWhere((item) => item.id == note.id);
      if (index == -1) {
        _notes.add(note);
        continue;
      }
      final current = _notes[index];
      _notes[index] = _mergeNote(current, note);
    }
  }

  Note _mergeNote(Note current, Note incoming) {
    final incomingWins = _noteWins(incoming, current);
    final winner = incomingWins ? incoming : current;
    final other = incomingWins ? current : incoming;
    if (winner.isDeleted || other.isDeleted) return winner;
    if (!_isDailyBoard(winner) || !_isDailyBoard(other)) return winner;

    final deletedKeys = {
      ...winner.deletedChecklistItemKeys,
      ...other.deletedChecklistItemKeys,
    }.where((key) => key.trim().isNotEmpty).toSet();
    final usedKeys = <String>{};
    final checklist = <ChecklistItem>[];
    for (final board in [winner, other]) {
      for (final item in board.checklist) {
        final text = item.text.trim();
        if (text.isEmpty) continue;
        final keys = _checklistItemKeys(item);
        if (keys.any(deletedKeys.contains)) continue;
        if (keys.any(usedKeys.contains)) continue;
        usedKeys.addAll(keys);
        checklist.add(item);
      }
    }

    final body = winner.body.trim().isEmpty
        ? ''
        : _mergeBodyParts([winner.body, other.body]);
    return winner.copyWith(
      type: NoteType.full,
      body: body,
      checklist: checklist,
      deletedChecklistItemKeys: deletedKeys.toList(),
      bodyClearedAt: _latestDate(winner.bodyClearedAt, other.bodyClearedAt),
      isPinned: true,
      popOnDesktop: true,
      showOnMobileWidget: true,
    );
  }

  bool _noteWins(Note candidate, Note current) {
    return candidate.revision > current.revision ||
        (candidate.revision == current.revision &&
            candidate.updatedAt.isAfter(current.updatedAt));
  }

  bool _isDailyBoard(Note note) {
    return note.boardName == 'Today' && note.supportsChecklist;
  }

  bool _isFutureDailyBoard(Note note) {
    return _isDailyBoard(note) && note.dayKey.isAfter(_dayOnly(DateTime.now()));
  }

  Future<void> _rollDailyBoardIfNeeded() async {
    final now = DateTime.now();
    final staleBoards = _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.boardName == 'Today' &&
          note.dayKey.isBefore(_dayOnly(now));
    }).toList();

    final carryTasks = <ChecklistItem>[];
    final carryBodies = <String>[];
    DateTime? bodyClearedAt;
    for (final board in staleBoards) {
      bodyClearedAt = _latestDate(bodyClearedAt, board.bodyClearedAt);
      final body = board.body.trim();
      if (body.isNotEmpty && !_wasBodyClearedAfter(board, bodyClearedAt)) {
        carryBodies.add(body);
      }
      carryTasks.addAll(
        board.checklist
            .where(
              (item) => !item.done && item.text.trim().isNotEmpty,
            )
            .map((item) => item.copyWith(carriedFrom: board.dayKey.toUtc())),
      );
      await _persistAndPush(
        _touch(
          board.copyWith(
            title: _historyTitle(board.dayKey),
            boardName: 'History',
            isArchived: true,
            isPinned: false,
            popOnDesktop: false,
            showOnMobileWidget: false,
          ),
        ),
      );
    }
    if (staleBoards.isEmpty && todayTodoNote == null) {
      carryTasks.addAll(_missedCarryTasksFromLatestHistory(now));
      bodyClearedAt = _latestDate(bodyClearedAt, _latestBodyClearedAt());
      final body = _missedCarryBodyFromLatestHistory(now, bodyClearedAt);
      if (body != null) carryBodies.add(body);
    }

    if (carryTasks.isNotEmpty || carryBodies.isNotEmpty) {
      final today = todayTodoNote ?? _newTodayBoard(now);
      final existingTexts =
          today.checklist.map((item) => item.text.trim().toLowerCase()).toSet();
      final mergedBody = _mergeBodyParts([
        today.body,
        ...carryBodies,
      ]);
      final mergedTasks = [
        ...today.checklist,
        ...carryTasks
            .where((item) =>
                !existingTexts.contains(item.text.trim().toLowerCase()))
            .map(
              (item) => ChecklistItem(
                text: item.text,
                carriedFrom: item.carriedFrom ?? now,
                reminderAt: item.reminderAt,
                isFocus: item.isFocus,
                planId: item.planId,
                planItemId: item.planItemId,
                scheduledFor: item.scheduledFor,
              ),
            ),
      ];
      await _persistAndPush(
        _touch(
          today.copyWith(
            body: mergedBody,
            checklist: mergedTasks,
            bodyClearedAt: bodyClearedAt,
          ),
        ),
      );
    }

    await _mergeDuplicateTodayBoards(now);
    await _deleteHistoryOlderThan365Days();
  }

  List<ChecklistItem> _missedCarryTasksFromLatestHistory(DateTime now) {
    final latestHistory = _notes.where((note) {
      return !note.isDeleted &&
          note.isArchived &&
          note.boardName == 'History' &&
          note.supportsChecklist &&
          note.dayKey.isBefore(_dayOnly(now)) &&
          note.checklist.any(
            (item) => !item.done && item.text.trim().isNotEmpty,
          );
    }).toList()
      ..sort(_byDayThenCreatedDesc);

    if (latestHistory.isEmpty) return const [];
    final source = latestHistory.first;
    final today = todayTodoNote;
    final existingTexts = today?.checklist
            .map((item) => item.text.trim().toLowerCase())
            .where((text) => text.isNotEmpty)
            .toSet() ??
        <String>{};
    return source.checklist
        .where((item) {
          final text = item.text.trim();
          return !item.done &&
              text.isNotEmpty &&
              !existingTexts.contains(text.toLowerCase());
        })
        .map((item) => item.copyWith(carriedFrom: source.dayKey.toUtc()))
        .toList();
  }

  String? _missedCarryBodyFromLatestHistory(
    DateTime now,
    DateTime? bodyClearedAt,
  ) {
    final latestHistory = _notes.where((note) {
      return !note.isDeleted &&
          note.isArchived &&
          note.boardName == 'History' &&
          note.supportsBody &&
          !_wasBodyClearedAfter(note, bodyClearedAt) &&
          note.dayKey.isBefore(_dayOnly(now)) &&
          note.body.trim().isNotEmpty;
    }).toList()
      ..sort(_byDayThenCreatedDesc);

    if (latestHistory.isEmpty) return null;
    return latestHistory.first.body.trim();
  }

  Future<void> _mergeDuplicateTodayBoards(DateTime now) async {
    final boards = _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.boardName == 'Today' &&
          _isSameLocalDay(note.dayKey, now);
    }).toList();
    if (boards.length < 2) return;

    boards.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final keeper = boards.first;
    final duplicateBoards = boards.skip(1).toList();
    final bodyClearedAt = boards
        .map((note) => note.bodyClearedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, _latestDate);
    final body = keeper.body.trim().isEmpty
        ? ''
        : _mergeBodyParts([
            keeper.body,
            ...duplicateBoards
                .where((note) => !_wasBodyClearedAfter(note, bodyClearedAt))
                .map((note) => note.body),
          ]);
    final checklistByKey = <String, ChecklistItem>{};
    final usedKeys = <String>{};
    final deletedKeys = boards
        .expand((note) => note.deletedChecklistItemKeys)
        .where((key) => key.trim().isNotEmpty)
        .toSet();
    for (final board in boards) {
      for (final item in board.checklist) {
        final keys = _checklistItemKeys(item);
        if (keys.any(deletedKeys.contains)) continue;
        if (keys.any(usedKeys.contains)) continue;
        usedKeys.addAll(keys);
        checklistByKey[keys.first] = item;
      }
    }

    await _persistAndPush(
      _touch(
        keeper.copyWith(
          title: _dailyTitle(now),
          type: NoteType.full,
          body: body,
          checklist: checklistByKey.values.toList(),
          deletedChecklistItemKeys: deletedKeys.toList(),
          bodyClearedAt: bodyClearedAt,
          isPinned: true,
          popOnDesktop: true,
          showOnMobileWidget: true,
        ),
      ),
    );

    for (final duplicate in duplicateBoards) {
      await _persistAndPush(
        _touch(
          duplicate.copyWith(
            isDeleted: true,
            deletedAt: DateTime.now().toUtc(),
            popOnDesktop: false,
            showOnMobileWidget: false,
          ),
        ),
      );
    }
  }

  Future<void> _deleteHistoryOlderThan365Days() async {
    final oldest = DateTime.now().toUtc().subtract(const Duration(days: 365));
    final oldHistory = _notes.where((note) {
      return !note.isDeleted &&
          note.isArchived &&
          note.boardName == 'History' &&
          note.createdAt.isBefore(oldest);
    }).toList();
    for (final note in oldHistory) {
      await _persistAndPush(
        _touch(
          note.copyWith(
            isDeleted: true,
            deletedAt: DateTime.now().toUtc(),
            popOnDesktop: false,
            showOnMobileWidget: false,
          ),
        ),
      );
    }
  }

  Note _touch(Note note) {
    return note.copyWith(
      updatedAt: DateTime.now().toUtc(),
      revision: note.revision + 1,
      deviceId: _deviceId,
    );
  }

  Future<void> _saveLocal() async {
    final key = _key;
    if (key == null) return;
    await _localVault.save(_notes, key, lastPulledAt: _lastPulledAt);
  }

  // A board planned for tomorrow must not show on today's widget.
  Future<void> _publishWidget() => _widgetPublisher.publish(
        _notes.where((note) => !_isFutureDailyBoard(note)).toList(),
      );

  void _setSync(SyncState state) {
    _syncState = state;
    if (state != SyncState.error) _error = null;
    notifyListeners();
  }

  void _setError(String error) {
    _syncState = SyncState.error;
    _error = error;
    notifyListeners();
  }

  String _mergeBodyParts(Iterable<String> parts) {
    final seen = <String>{};
    final merged = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) merged.add(trimmed);
    }
    return merged.join('\n\n');
  }

  List<String> _deletedChecklistKeys(
    Note note,
    Iterable<ChecklistItem> items,
  ) {
    final keys = note.deletedChecklistItemKeys
        .where((key) => key.trim().isNotEmpty)
        .toSet();
    for (final item in items) {
      keys.addAll(_checklistItemKeys(item));
    }
    return keys.toList();
  }

  List<String> _checklistItemKeys(ChecklistItem item) {
    final text = item.text.trim().toLowerCase();
    return [
      if (text.isNotEmpty) 'text:$text',
      'id:${item.id}',
    ];
  }

  List<String> _reviveChecklistText(List<String> deletedKeys, String text) {
    final key = 'text:${text.trim().toLowerCase()}';
    if (key == 'text:') return deletedKeys;
    return deletedKeys.where((deletedKey) => deletedKey != key).toList();
  }

  bool _wasBodyClearedAfter(Note note, DateTime? marker) {
    if (marker == null) return false;
    final clearedAt = note.bodyClearedAt;
    if (clearedAt == null) return false;
    // Body was cleared after the marker if bodyClearedAt is at or after marker.
    return !clearedAt.isBefore(marker);
  }

  DateTime? _latestBodyClearedAt() {
    return _notes
        .map((note) => note.bodyClearedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, _latestDate);
  }

  DateTime? _latestDate(DateTime? current, DateTime? candidate) {
    if (current == null) return candidate;
    if (candidate == null) return current;
    return candidate.isAfter(current) ? candidate : current;
  }

  Note? _findNote(String id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  Note _newTodayBoard(DateTime now) {
    final previous = _latestDailyStickySettings;
    return Note.blank(_deviceId, type: NoteType.full).copyWith(
      title: _dailyTitle(now),
      noteDate: _dayOnly(now),
      boardName: 'Today',
      isPinned: true,
      popOnDesktop: previous?.popOnDesktop ?? true,
      showOnMobileWidget: previous?.showOnMobileWidget ?? true,
      isAlwaysOnTop: previous?.isAlwaysOnTop ?? false,
      colorHex: previous?.colorHex ?? 'F2F2F2',
      opacity: previous?.opacity ?? 1,
      bounds: previous?.bounds,
    );
  }

  Note? get _latestDailyStickySettings {
    final candidates = _notes.where((note) {
      return !note.isDeleted &&
          note.supportsChecklist &&
          (note.boardName == 'Today' || note.boardName == 'History') &&
          note.bounds != null;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.firstOrNull;
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _byDayThenCreatedDesc(Note a, Note b) {
    final byDay = b.dayKey.compareTo(a.dayKey);
    return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
  }

  String _dailyTitle(DateTime date) {
    return _dateLabel(date);
  }

  String _historyTitle(DateTime date) {
    return _dateLabel(date);
  }

  String _dateLabel(DateTime date) {
    return DateFormat('d MMM yyyy').format(date);
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _dailyTimer?.cancel();
    _obsidianPollTimer?.cancel();
    _remoteSub?.cancel();
    super.dispose();
  }
}
