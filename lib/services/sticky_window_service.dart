import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../controllers/noterr_controller.dart';
import '../models/note.dart';

class StickyWindowService {
  StickyWindowService._();

  static final StickyWindowService instance = StickyWindowService._();
  static const _channel = WindowMethodChannel(
    'noterr_sticky_notes',
    mode: ChannelMode.unidirectional,
  );

  final Map<String, WindowController> _noteWindows = {};
  final Map<String, int> _dismissedRemoteRevision = {};
  final Set<String> _openingNoteIds = {};
  Future<void>? _showChain;
  NoterrController? _boundController;
  NoterrController? _controller;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void bindController(NoterrController controller) {
    _boundController?.removeListener(_syncOpenWindowsFromController);
    _boundController = controller;
    _controller = controller;
    controller.addListener(_syncOpenWindowsFromController);
    if (!isSupported) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sticky-note-updated':
          final note = Note.fromJson(
            Map<String, dynamic>.from(call.arguments as Map),
          );
          await _controller?.updateNote(note);
          return true;
        case 'sticky-note-closed':
          final noteId = call.arguments as String;
          final note =
              _controller?.notes.where((item) => item.id == noteId).firstOrNull;
          if (note != null) _dismissedRemoteRevision[note.id] = note.revision;
          _noteWindows.remove(noteId);
          return true;
        case 'sticky-note-delete':
          final noteId = call.arguments as String;
          final note =
              _controller?.notes.where((item) => item.id == noteId).firstOrNull;
          if (note != null) await _controller?.softDeleteNote(note);
          return true;
      }
      return null;
    });
  }

  Future<void> show(Note note) async {
    _showChain = (_showChain ?? Future<void>.value()).then((_) {
      return _showSingle(note);
    });
    return _showChain;
  }

  Future<void> _showSingle(Note note) async {
    if (!isSupported) return;
    final target = _controller?.todayTodoNote ?? note;
    if (_openingNoteIds.contains(target.id)) return;

    for (final entry in _noteWindows.entries.toList()) {
      if (entry.key == target.id) continue;
      _noteWindows.remove(entry.key);
      unawaited(_invokeSafely(entry.value, 'sticky-note-lock'));
    }

    final existingWindow = _noteWindows[target.id];
    if (existingWindow != null) {
      await existingWindow.show();
      await _invokeSafely(
          existingWindow, 'sticky-note-replaced', target.toJson());
      return;
    }

    _openingNoteIds.add(target.id);
    try {
      final window = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'type': 'sticky',
            'note': target.toJson(),
          }),
          hiddenAtLaunch: true,
        ),
      );
      if (_noteWindows.containsKey(target.id)) {
        await _invokeSafely(window, 'sticky-note-lock');
        return;
      }
      _noteWindows[target.id] = window;
      await window.show();
    } finally {
      _openingNoteIds.remove(target.id);
    }
  }

  Future<void> closeAll() async {
    final windows = _noteWindows.values.toList();
    _noteWindows.clear();
    _openingNoteIds.clear();
    for (final window in windows) {
      await _invokeSafely(window, 'sticky-note-lock');
    }
  }

  Future<void> hideAll() async {
    for (final window in _noteWindows.values) {
      await _invokeSafely(window, 'sticky-note-hide');
    }
  }

  Future<void> showDailySticky() async {
    final note = _controller?.todayTodoNote;
    if (note == null) return;
    await show(note);
  }

  void _syncOpenWindowsFromController() {
    final controller = _controller;
    if (controller == null || !isSupported) return;
    if (!controller.isUnlocked) {
      unawaited(closeAll());
      return;
    }

    final target = controller.todayTodoNote;

    for (final entry in _noteWindows.entries.toList()) {
      final note =
          controller.notes.where((item) => item.id == entry.key).firstOrNull;
      if (note == null ||
          target == null ||
          note.id != target.id ||
          note.isDeleted ||
          note.isArchived ||
          !note.popOnDesktop) {
        _noteWindows.remove(entry.key);
        unawaited(_invokeSafely(entry.value, 'sticky-note-lock'));
        continue;
      }
      unawaited(
          _invokeSafely(entry.value, 'sticky-note-replaced', note.toJson()));
    }

    if (target == null ||
        !target.popOnDesktop ||
        target.isArchived ||
        target.isDeleted ||
        _noteWindows.containsKey(target.id)) {
      return;
    }
    final dismissedRevision = _dismissedRemoteRevision[target.id] ?? 0;
    if (target.revision <= dismissedRevision) return;
    unawaited(show(target));
  }

  Future<void> _invokeSafely(
    WindowController window,
    String method, [
    Object? arguments,
  ]) async {
    try {
      await window.invokeMethod(method, arguments);
    } catch (_) {
      // The child window may be closing or still booting. The next controller
      // notification will retry active windows.
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
