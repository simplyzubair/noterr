import 'package:flutter/services.dart';

import '../models/note.dart';

class WidgetPublisher {
  static const _channel = MethodChannel('noterr/widget');

  Future<void> publish(List<Note> notes) async {
    final visible = notes
        .where((note) => !note.isDeleted && !note.isArchived)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final dailyBoards =
        visible.where((note) => note.boardName == 'Today').toList();
    final dailyBoard = dailyBoards.isEmpty ? null : dailyBoards.first;

    final widgetNotes = visible
        .where((note) => note.showOnMobileWidget || note.popOnDesktop)
        .toList();
    final todoNotes =
        widgetNotes.where((note) => note.supportsChecklist).toList();
    final stickyNotes = widgetNotes.where((note) => note.supportsBody).toList();
    final primaryTodo =
        dailyBoard ?? (todoNotes.isEmpty ? null : todoNotes.first);
    final primarySticky =
        dailyBoard ?? (stickyNotes.isEmpty ? null : stickyNotes.first);
    final primary = dailyBoard ??
        (widgetNotes.isNotEmpty
            ? widgetNotes.first
            : visible.isEmpty
                ? null
                : visible.first);

    try {
      await _channel.invokeMethod<void>('publish', {
        'id': primary?.id,
        'title': primary?.title ?? 'Noterr',
        'body': _dailyBody(primary) ?? 'No active notes',
        'colorHex': primary?.colorHex ?? 'FFF4B8',
        'opacity': primary?.opacity ?? 1,
        'boardName': primary?.boardName ?? 'Personal',
        'type': primary?.type.name ?? NoteType.note.name,
        'popOnDesktop': primary?.popOnDesktop ?? true,
        'showOnMobileWidget': primary?.showOnMobileWidget ?? true,
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

  String _todoBody(Note? note) {
    if (note == null) return 'No tasks yet';
    final pending = note.checklist.where((item) => !item.done).toList();
    if (pending.isEmpty) return 'All done for today';
    return pending.map((item) => '- ${item.text}').join('\n');
  }

  String? _dailyBody(Note? note) {
    if (note == null) return null;
    final parts = <String>[];
    final body = note.body.trim();
    if (body.isNotEmpty) parts.add(body);
    if (note.supportsChecklist) {
      final pending = note.checklist.where((item) => !item.done).toList();
      if (pending.isNotEmpty) {
        parts.add(pending.map((item) => '- ${item.text}').join('\n'));
      }
    }
    if (parts.isEmpty) return 'No notes or tasks yet';
    return parts.join('\n\n');
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
