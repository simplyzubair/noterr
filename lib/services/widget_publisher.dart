import 'package:flutter/services.dart';

import '../models/note.dart';

class WidgetPublisher {
  static const _channel = MethodChannel('noterr/widget');

  Future<void> publish(List<Note> notes) async {
    final visible = notes
        .where((note) => !note.isDeleted && !note.isArchived)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final widgetNotes = visible
        .where((note) => note.showOnMobileWidget || note.popOnDesktop)
        .toList();
    final todoNotes = widgetNotes
        .where((note) => note.type == NoteType.checklist)
        .toList();
    final stickyNotes = widgetNotes
        .where((note) => note.type != NoteType.checklist)
        .toList();
    final todayTodos =
        todoNotes.where((note) => note.boardName == 'Today').toList();
    final todayTodo = todayTodos.isEmpty ? null : todayTodos.first;
    final primaryTodo = todayTodo ?? (todoNotes.isEmpty ? null : todoNotes.first);
    final primarySticky = stickyNotes.isEmpty ? null : stickyNotes.first;
    final primary = widgetNotes.isNotEmpty
        ? widgetNotes.first
        : visible.isEmpty
            ? null
            : visible.first;

    try {
      await _channel.invokeMethod<void>('publish', {
        'id': primary?.id,
        'title': primary?.title ?? 'Noterr',
        'body': primary?.preview ?? 'No active notes',
        'colorHex': primary?.colorHex ?? 'FFF4B8',
        'boardName': primary?.boardName ?? 'Personal',
        'type': primary?.type.name ?? NoteType.note.name,
        'popOnDesktop': primary?.popOnDesktop ?? true,
        'showOnMobileWidget': primary?.showOnMobileWidget ?? true,
        'todoTitle': primaryTodo?.title ?? 'Today To Do',
        'todoBody': _todoBody(primaryTodo),
        'todoColorHex': primaryTodo?.colorHex ?? 'E7F6EF',
        'stickyTitle': primarySticky?.title ?? 'Sticky Notes',
        'stickyBody': _stickyBody(stickyNotes),
        'stickyColorHex': primarySticky?.colorHex ?? 'FFF4B8',
        'notes': widgetNotes.take(8).map((note) {
          return {
            'id': note.id,
            'title': note.title,
            'body': note.preview,
            'colorHex': note.colorHex,
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
            'updatedAt': note.updatedAt.toIso8601String(),
          };
        }).toList(),
        'stickies': stickyNotes.take(8).map((note) {
          return {
            'id': note.id,
            'title': note.title,
            'body': note.preview,
            'colorHex': note.colorHex,
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
