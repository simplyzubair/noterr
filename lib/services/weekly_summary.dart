import '../models/note.dart';

/// Task counts for one day of the week.
class DaySummary {
  const DaySummary({
    required this.day,
    required this.total,
    required this.done,
    required this.added,
  });

  final DateTime day;

  /// Tasks on that day's board, carried-over ones included.
  final int total;
  final int done;

  /// Tasks written that day, as opposed to carried over from an earlier day.
  final int added;

  int get pending => total - done;
}

/// Counts for one Monday-to-Sunday week, built from the daily boards.
///
/// A task left open is copied onto the next day's board, so the same task can
/// sit on several boards. Week totals therefore count each task once, by its
/// text: [total] distinct tasks, [done] of them finished on some day, and the
/// rest [pendingTasks]. The per-day rows count each board as it was.
class WeeklySummary {
  WeeklySummary._({
    required this.weekStart,
    required this.days,
    required this.total,
    required this.done,
    required this.pendingTasks,
  });

  /// Builds the summary for the week starting on [weekStart] (a Monday, local
  /// midnight). Only days up to and including [until] are counted, so a
  /// summary written on Sunday morning doesn't show Sunday's board as empty.
  factory WeeklySummary.compute(
    Iterable<Note> notes,
    DateTime weekStart, {
    DateTime? until,
  }) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));
    final last = until == null
        ? end.subtract(const Duration(days: 1))
        : DateTime(until.year, until.month, until.day);

    final boards = notes.where((note) {
      if (note.isDeleted || !note.supportsChecklist) return false;
      if (note.boardName != 'Today' && note.boardName != 'History') {
        return false;
      }
      final day = note.dayKey;
      return !day.isBefore(start) && day.isBefore(end) && !day.isAfter(last);
    }).toList();

    final days = <DaySummary>[];
    final firstSeen = <String, String>{}; // key -> display text
    final doneKeys = <String>{};

    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      if (day.isAfter(last)) break;
      // Merge if a day somehow has more than one board, by task text.
      final items = <String, ChecklistItem>{};
      for (final board in boards.where((b) => _sameDay(b.dayKey, day))) {
        for (final item in board.checklist) {
          final text = item.text.trim();
          if (text.isEmpty) continue;
          final key = text.toLowerCase();
          final prior = items[key];
          if (prior == null || (item.done && !prior.done)) items[key] = item;
        }
      }
      var done = 0;
      var added = 0;
      for (final entry in items.entries) {
        firstSeen.putIfAbsent(entry.key, () => entry.value.text.trim());
        if (entry.value.done) {
          done++;
          doneKeys.add(entry.key);
        }
        if (entry.value.carriedFrom == null) added++;
      }
      days.add(
        DaySummary(day: day, total: items.length, done: done, added: added),
      );
    }

    final pending = [
      for (final e in firstSeen.entries)
        if (!doneKeys.contains(e.key)) e.value,
    ];

    return WeeklySummary._(
      weekStart: start,
      days: days,
      total: firstSeen.length,
      done: doneKeys.length,
      pendingTasks: pending,
    );
  }

  final DateTime weekStart;
  final List<DaySummary> days;
  final int total;
  final int done;
  final List<String> pendingTasks;

  int get pending => pendingTasks.length;
  DateTime get weekEnd => weekStart.add(const Duration(days: 6));

  /// ISO week label such as `2026-W40`, used as the Obsidian file name.
  String get isoWeek {
    final thursday = weekStart.add(const Duration(days: 3));
    final firstThursday = _firstThursday(thursday.year);
    final week = 1 + thursday.difference(firstThursday).inDays ~/ 7;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// Plain text for the Noterr note.
  String toPlainText() {
    final b = StringBuffer()
      ..writeln(_range())
      ..writeln()
      ..writeln('Tasks: $total   Done: $done   Pending: $pending')
      ..writeln();
    for (final d in days) {
      b.writeln(
        '${_dayLabel(d.day)}: ${d.total} tasks, ${d.done} done, '
        '${d.pending} pending, ${d.added} new',
      );
    }
    if (pendingTasks.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Still open:');
      for (final t in pendingTasks) {
        b.writeln('- $t');
      }
    }
    return b.toString().trimRight();
  }

  /// Markdown for the Obsidian weekly page.
  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Week $isoWeek')
      ..writeln()
      ..writeln(_range())
      ..writeln()
      ..writeln('| Tasks | Done | Pending |')
      ..writeln('|---:|---:|---:|')
      ..writeln('| $total | $done | $pending |')
      ..writeln()
      ..writeln('## Per day')
      ..writeln()
      ..writeln('| Day | Tasks | Done | Pending | New |')
      ..writeln('|---|---:|---:|---:|---:|');
    for (final d in days) {
      b.writeln(
        '| [[${_isoDate(d.day)}\\|${_dayLabel(d.day)}]] | ${d.total} | '
        '${d.done} | ${d.pending} | ${d.added} |',
      );
    }
    if (pendingTasks.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Still open')
        ..writeln();
      for (final t in pendingTasks) {
        b.writeln('- [ ] $t');
      }
    }
    return b.toString().trimRight();
  }

  String _range() {
    final last = days.isEmpty ? weekEnd : days.last.day;
    return '${_dayLabel(weekStart)} to ${_dayLabel(last)} ${last.year}';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dayLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _firstThursday(int year) {
    final jan1 = DateTime(year, 1, 1);
    return jan1.add(Duration(days: (DateTime.thursday - jan1.weekday + 7) % 7));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Monday (local midnight) of the week containing [date].
DateTime mondayOf(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}
