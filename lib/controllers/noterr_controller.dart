import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../services/local_vault.dart';
import '../services/remote_sync_service.dart';
import '../services/vault_crypto.dart';
import '../services/widget_publisher.dart';

enum SyncState { offline, idle, syncing, error }

const _templateBoardName = 'System';
const _templateNoteTitle = '__noterr_templates_v1';
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
  })  : _localVault = localVault,
        _remote = remote,
        _widgetPublisher = widgetPublisher;

  final LocalVault _localVault;
  final RemoteSyncService _remote;
  final WidgetPublisher _widgetPublisher;

  final List<Note> _notes = [];
  SecretKey? _key;
  StreamSubscription<RemoteNoteEnvelope>? _remoteSub;
  Timer? _syncTimer;
  Timer? _dailyTimer;
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

  List<Note> get notes => List.unmodifiable(_notes);

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
          _isSameLocalDay(note.createdAt.toLocal(), now);
    }).firstOrNull;
  }

  List<Note> get stickyNotes {
    return _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.id != todayTodoNote?.id &&
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

  Future<Note> ensureTodayTodoNote() async {
    await _rollDailyBoardIfNeeded();
    final existing = todayTodoNote;
    final now = DateTime.now();
    final title = _dailyTitle(now);
    if (existing != null) {
      if (existing.title != title) {
        final updated = _touch(existing.copyWith(title: title));
        await _persistAndPush(updated);
        return updated;
      }
      return existing;
    }
    final note = _newTodayBoard(now);
    _notes.add(note);
    await _persistAndPush(note);
    return note;
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
        checklist: note.checklist
            .where((current) => current.id != item.id)
            .toList(),
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

    final salt = await _localVault.getOrCreateLocalSalt();
    await _openLocalVault(cleanPassphrase, salt);
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
    await _widgetPublisher.configureLiveWidgetSync(passphrase);
    await _publishWidget();
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
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_syncState == SyncState.syncing) return;
      unawaited(syncNow());
    });
  }

  void _startDailyTimer() {
    _dailyTimer?.cancel();
    if (_key == null) return;
    _dailyTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(ensureTodayTodoNote());
    });
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
    final changed = note.copyWith(
      updatedAt: DateTime.now().toUtc(),
      revision: note.revision + 1,
      deviceId: _deviceId,
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
      final remoteNotes = await _remote.pullNotes(key);
      _lastPulledCount = remoteNotes.length;
      _merge(remoteNotes);
      await _rollDailyBoardIfNeeded();
      var pushed = 0;
      for (final note in _notes) {
        await _remote.pushNote(note, key, _deviceId);
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
    if (!hasCloud || _key == null) return;
    try {
      _setSync(SyncState.syncing);
      await _remote.pushNote(note, _key!, _deviceId);
      _lastPushAt = DateTime.now().toUtc();
      _lastPushedCount = 1;
      _setSync(SyncState.idle);
    } catch (error) {
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
      final incomingWins = note.revision > current.revision ||
          (note.revision == current.revision &&
              note.updatedAt.isAfter(current.updatedAt));
      if (incomingWins) _notes[index] = note;
    }
  }

  Future<void> _rollDailyBoardIfNeeded() async {
    final now = DateTime.now();
    final staleBoards = _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.boardName == 'Today' &&
          !_isSameLocalDay(note.createdAt.toLocal(), now);
    }).toList();

    final carryTasks = <ChecklistItem>[];
    final carryBodies = <String>[];
    for (final board in staleBoards) {
      final body = board.body.trim();
      if (body.isNotEmpty) carryBodies.add(body);
      carryTasks.addAll(
        board.checklist
            .where(
              (item) => !item.done && item.text.trim().isNotEmpty,
            )
            .map((item) => item.copyWith(carriedFrom: board.createdAt)),
      );
      await _persistAndPush(
        _touch(
          board.copyWith(
            title: _historyTitle(board.createdAt.toLocal()),
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
      final body = _missedCarryBodyFromLatestHistory(now);
      if (body != null) carryBodies.add(body);
    }

    if (carryTasks.isNotEmpty || carryBodies.isNotEmpty) {
      final today = todayTodoNote ?? _newTodayBoard(now);
      final existingTexts = today.checklist
          .map((item) => item.text.trim().toLowerCase())
          .toSet();
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
              ),
            ),
      ];
      await _persistAndPush(
        _touch(
          today.copyWith(
            body: mergedBody,
            checklist: mergedTasks,
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
          note.createdAt.toLocal().isBefore(DateTime(
                now.year,
                now.month,
                now.day,
              )) &&
          note.checklist.any(
            (item) => !item.done && item.text.trim().isNotEmpty,
          );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
        .map((item) => item.copyWith(carriedFrom: source.createdAt))
        .toList();
  }

  String? _missedCarryBodyFromLatestHistory(DateTime now) {
    final latestHistory = _notes.where((note) {
      return !note.isDeleted &&
          note.isArchived &&
          note.boardName == 'History' &&
          note.supportsBody &&
          note.createdAt.toLocal().isBefore(DateTime(
                now.year,
                now.month,
                now.day,
              )) &&
          note.body.trim().isNotEmpty;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (latestHistory.isEmpty) return null;
    return latestHistory.first.body.trim();
  }

  Future<void> _mergeDuplicateTodayBoards(DateTime now) async {
    final boards = _notes.where((note) {
      return !note.isDeleted &&
          !note.isArchived &&
          note.boardName == 'Today' &&
          _isSameLocalDay(note.createdAt.toLocal(), now);
    }).toList();
    if (boards.length < 2) return;

    boards.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final keeper = boards.first;
    final duplicateBoards = boards.skip(1).toList();
    final body = keeper.body.trim().isEmpty
        ? ''
        : _mergeBodyParts([
            keeper.body,
            ...duplicateBoards.map((note) => note.body),
          ]);
    final checklistByKey = <String, ChecklistItem>{};
    final deletedKeys = boards
        .expand((note) => note.deletedChecklistItemKeys)
        .where((key) => key.trim().isNotEmpty)
        .toSet();
    for (final board in boards) {
      for (final item in board.checklist) {
        final keys = _checklistItemKeys(item);
        if (keys.any(deletedKeys.contains)) continue;
        final key = keys.first;
        checklistByKey.putIfAbsent(key, () => item);
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

  Future<void> _publishWidget() => _widgetPublisher.publish(_notes);

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

  Note _newTodayBoard(DateTime now) {
    final previous = _latestDailyStickySettings;
    return Note.blank(_deviceId, type: NoteType.full).copyWith(
      title: _dailyTitle(now),
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
    _remoteSub?.cancel();
    super.dispose();
  }
}
