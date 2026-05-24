import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';
import '../services/local_vault.dart';
import '../services/remote_sync_service.dart';
import '../services/vault_crypto.dart';
import '../services/widget_publisher.dart';

enum SyncState { offline, idle, syncing, error }

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
  String _deviceId = '';
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
          note.type == NoteType.checklist &&
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
    return _notes.where((note) {
      return !note.isDeleted && !note.isArchived;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<Note> get historyNotes {
    final oldest = DateTime.now().toUtc().subtract(const Duration(days: 7));
    return _notes.where((note) => note.updatedAt.isAfter(oldest)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Note> ensureTodayTodoNote() async {
    final existing = todayTodoNote;
    if (existing != null) return existing;
    final note = Note.blank(_deviceId, type: NoteType.checklist).copyWith(
      title: 'Today',
      boardName: 'Today',
      isPinned: true,
      popOnDesktop: true,
      showOnMobileWidget: true,
      colorHex: 'FFF4B8',
    );
    _notes.add(note);
    await _persistAndPush(note);
    return note;
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
    await updateNote(note.copyWith(checklist: items));
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
      ),
    );
  }

  Future<ChecklistItem> addChecklistItem(Note note, {String text = ''}) async {
    final next = ChecklistItem(text: text);
    await updateNote(note.copyWith(checklist: [...note.checklist, next]));
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
    await updateNote(note.copyWith(checklist: items));
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
    return updateNote(
      note.copyWith(
        checklist:
            note.checklist.where((current) => current.id != item.id).toList(),
      ),
    );
  }

  Future<void> clearDoneTodayTasks() async {
    final note = await ensureTodayTodoNote();
    await updateNote(
      note.copyWith(
        checklist: note.checklist.where((item) => !item.done).toList(),
      ),
    );
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

  Future<void> signIn(String email, String password) async {
    await _remote.signIn(email, password);
    notifyListeners();
  }

  Future<void> signUp(String email, String password) async {
    await _remote.signUp(email, password);
    notifyListeners();
  }

  Future<void> signOut() async {
    _syncTimer?.cancel();
    await _remoteSub?.cancel();
    await _remote.signOut();
    _key = null;
    _notes.clear();
    notifyListeners();
  }

  Future<void> lock() async {
    _syncTimer?.cancel();
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
    _deviceId = await _localVault.getOrCreateDeviceId();
    await _ensurePasskeySession(passphrase);
    final salt = hasCloud
        ? await _remote.getOrCreateVaultSalt()
        : await _localVault.getOrCreateLocalSalt();
    _key = await VaultCrypto.deriveKey(passphrase: passphrase, salt: salt);

    LocalVaultSnapshot snapshot;
    try {
      snapshot = await _localVault.load(_key!);
    } catch (_) {
      if (!hasCloud) rethrow;
      await _localVault.backUpVault(suffix: 'local-only-backup');
      snapshot = const LocalVaultSnapshot(notes: [], lastPulledAt: null);
    }
    _notes
      ..clear()
      ..addAll(snapshot.notes);
    _lastPulledAt = snapshot.lastPulledAt;
    _syncState = hasCloud ? SyncState.idle : SyncState.offline;
    notifyListeners();

    await syncNow();
    _subscribeRemote();
    _startSyncTimer();
    await _publishWidget();
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (!hasCloud || _key == null) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_syncState == SyncState.syncing) return;
      unawaited(syncNow());
    });
  }

  Future<void> _ensurePasskeySession(String passphrase) async {
    if (!hasCloud) return;
    final credentials = await VaultCrypto.syncCredentials(passphrase);
    await _remote.signOut();
    try {
      await _remote.signIn(credentials.email, credentials.password);
    } on AuthException catch (error) {
      if (!error.message.toLowerCase().contains('invalid login credentials')) {
        rethrow;
      }
      await _remote.signUp(credentials.email, credentials.password);
      if (_remote.currentUserId == null) {
        await _remote.signIn(credentials.email, credentials.password);
      }
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
      var pushed = 0;
      for (final note in _notes) {
        await _remote.pushNote(note, key, _deviceId);
        pushed++;
      }
      _lastPushedCount = pushed;
      _lastPulledAt = DateTime.now().toUtc();
      _lastSyncAt = _lastPulledAt;
      await _saveLocal();
      _setSync(SyncState.idle);
    } on AuthException catch (error) {
      _setError(error.message);
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

  bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _remoteSub?.cancel();
    super.dispose();
  }
}
