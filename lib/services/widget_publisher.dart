import 'package:flutter/services.dart';

import '../app/app_config.dart';
import '../models/note.dart';
import 'daily_quote.dart';

class WidgetPublisher {
  static const _channel = MethodChannel('noterr/widget');

  Future<void> configureLiveWidgetSync(String passphrase) async {
    if (!AppConfig.hasCloudSync) return;
    try {
      await _channel.invokeMethod<void>('configureLiveWidgetSync', {
        'syncUrl': AppConfig.syncUrl,
        'passphrase': passphrase,
      });
    } catch (_) {
      // Foreground widget sync is Android-only.
    }
  }

  Future<void> publish(List<Note> notes) async {
    final visible = notes
        .where((note) => !note.isDeleted && !note.isArchived)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final dailyBoards = visible
        .where((note) => note.boardName == 'Today' && note.showOnMobileWidget)
        .toList();
    final dailyBoard = _unifiedDailyBoard(dailyBoards);

    final widgetNotes =
        visible.where((note) => note.showOnMobileWidget).toList();
    final todoNotes =
        widgetNotes.where((note) => note.supportsChecklist).toList();
    final stickyNotes = widgetNotes.where((note) => note.supportsBody).toList();
    final primaryTodo =
        dailyBoard ?? (todoNotes.isEmpty ? null : todoNotes.first);
    final primarySticky =
        dailyBoard ?? (stickyNotes.isEmpty ? null : stickyNotes.first);
    final primary = dailyBoard ??
        (widgetNotes.isNotEmpty ? widgetNotes.first : null);

    try {
      await _channel.invokeMethod<void>('publish', {
        'id': primary?.id,
        'title': primary?.title ?? 'Noterr',
        'body': _withQuote(_dailyBody(primary) ?? 'No active notes'),
        'colorHex': primary?.colorHex ?? 'FFF4B8',
        'opacity': primary?.opacity ?? 1,
        'boardName': primary?.boardName ?? 'Personal',
        'type': primary?.type.name ?? NoteType.note.name,
        'popOnDesktop': primary?.popOnDesktop ?? true,
        'showOnMobileWidget': primary?.showOnMobileWidget ?? false,
        'todoTitle': primaryTodo?.title ?? 'Today To Do',
        'todoBody': _todoBody(primaryTodo),
        'todoColorHex': primaryTodo?.colorHex ?? 'E7F6EF',
        'todoOpacity': primaryTodo?.opacity ?? 1,
        'stickyTitle': primarySticky?.title ?? 'Sticky Notes',
        'stickyBody': _stickyBody(stickyNotes),
        'stickyColorHex': primarySticky?.colorHex ?? 'FFF4B8',
        'stickyOpacity': primarySticky?.opacity ?? 1,
        'notes': widgetNotes.take(8).map((note) {
          return {
            'id': note.id,
            'title': note.title,
            'body': note.preview,
            'colorHex': note.colorHex,
            'opacity': note.opacity,
            'type': note.type.name,
            'popOnDesktop': note.popOnDesktop,
            'showOnMobileWidget': note.showOnMobileWidget,
            'updatedAt': note.updatedAt.toIso8601String(),
          };
        }).toList(),
        'todos': todoNotes.take(8).map((note) {
          return {
            'id': note.id,
            'title': note.title,
            'body': _todoBody(note),
            'colorHex': note.colorHex,
            'opacity': note.opacity,
            'updatedAt': note.updatedAt.toIso8601String(),
          };
        }).toList(),
        'stickies': stickyNotes.take(8).map((note) {
          return {
            'id': note.id,
            'title': note.title,
            'body': note.preview,
            'colorHex': note.colorHex,
            'opacity': note.opacity,
            'updatedAt': note.updatedAt.toIso8601String(),
          };
        }).toList(),
        'updatedAt': primary?.updatedAt.toIso8601String(),
      });
    } catch (_) {
      // Widget publishing is only available once native Android files exist.
    }
  }

  String _withQuote(String body) {
    return '${DailyQuote.forDate()}\n\n$body';
  }

  Note? _unifiedDailyBoard(List<Note> dailyBoards) {
    if (dailyBoards.isEmpty) return null;
    if (dailyBoards.length == 1) return dailyBoards.first;

    final bodyParts = <String>[];
    final seenBodies = <String>{};
    final checklistByKey = <String, ChecklistItem>{};
    final deletedKeys = dailyBoards
        .expand((note) => note.deletedChecklistItemKeys)
        .where((key) => key.trim().isNotEmpty)
        .toSet();
    for (final note in dailyBoards) {
      final body = note.body.trim();
      if (body.isNotEmpty && seenBodies.add(body.toLowerCase())) {
        bodyParts.add(body);
      }
      for (final item in note.checklist) {
        final text = item.text.trim();
        if (text.isEmpty) continue;
        final keys = _checklistItemKeys(item);
        if (keys.any(deletedKeys.contains)) continue;
        final key = keys.first;
        checklistByKey.putIfAbsent(key, () => item);
      }
    }

    final base = dailyBoards.first;
    return base.copyWith(
      type: NoteType.full,
      body: bodyParts.join('\n\n'),
      checklist: checklistByKey.values.toList(),
      deletedChecklistItemKeys: deletedKeys.toList(),
    );
  }

  List<String> _checklistItemKeys(ChecklistItem item) {
    final text = item.text.trim().toLowerCase();
    return [
      if (text.isNotEmpty) 'text:$text',
      'id:${item.id}',
    ];
  }

  String _todoBody(Note? note) {
    if (note == null) return 'No tasks yet';
    final pending = note.checklist.where((item) => !item.done).toList();
    if (pending.isEmpty) return 'All done for today';
    final focus = pending.where((item) => item.isFocus).toList();
    final regular = pending.where((item) => !item.isFocus).toList();
    final ordered = [...focus, ...regular];
    return ordered.map(_taskLine).join('\n');
  }

  String? _dailyBody(Note? note) {
    if (note == null) return null;
    final parts = <String>[];
    final body = note.body.trim();
    if (body.isNotEmpty) parts.add(body);
    if (note.supportsChecklist) {
      final taskLines = note.checklist
          .where((item) => item.text.trim().isNotEmpty)
          .map((item) => item.done ? '[x] ${item.text}' : _taskLine(item))
          .toList();
      if (taskLines.isNotEmpty) {
        parts.add(taskLines.join('\n'));
      }
    }
    if (parts.isEmpty) return 'No notes or tasks yet';
    return parts.join('\n\n');
  }

  String _taskLine(ChecklistItem item) {
    final prefix = item.isFocus ? 'NOW: ' : '- ';
    return '$prefix${item.text}';
  }

  String _stickyBody(List<Note> notes) {
    if (notes.isEmpty) return 'No sticky notes yet';
    return notes.take(4).map((note) {
      final title = note.title.trim();
      final body = note.preview.trim();
      if (title.isEmpty) return body;
      if (body.isEmpty || body == title) return title;
      return '$title: $body';
    }).join('\n\n');
  }
}
