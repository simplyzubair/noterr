import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/controllers/noterr_controller.dart';
import 'package:noterr/models/note.dart';
import 'package:noterr/services/local_vault.dart';
import 'package:noterr/services/remote_sync_service.dart';
import 'package:noterr/services/weekly_summary.dart';
import 'package:noterr/services/widget_publisher.dart';

Note _board(DateTime day, List<ChecklistItem> items, {String board = 'History'}) {
  return Note(
    type: NoteType.full,
    title: 'board',
    body: '',
    colorHex: 'F2F2F2',
    // Created the evening before, the way a planned board is.
    createdAt: day.subtract(const Duration(hours: 3)).toUtc(),
    updatedAt: day.toUtc(),
    deviceId: 'test',
    noteDate: day,
    boardName: board,
    isArchived: board == 'History',
    checklist: items,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('noteDate', () {
    test('round-trips as a plain calendar day', () {
      final note = _board(DateTime(2026, 10, 8), const []);
      final json = note.toJson();
      expect(json['noteDate'], '2026-10-08');
      final back = Note.fromJson(json);
      expect(back.noteDate, DateTime(2026, 10, 8));
      expect(back.dayKey, DateTime(2026, 10, 8));
    });

    test('a board created at 21:00 for tomorrow belongs to tomorrow', () {
      final note = _board(DateTime(2026, 10, 8), const []);
      expect(note.createdAt.toLocal().day, 7);
      expect(note.dayKey, DateTime(2026, 10, 8));
    });

    test('older notes without noteDate fall back to createdAt', () {
      final json = _board(DateTime(2026, 10, 8), const []).toJson()
        ..remove('noteDate');
      final legacy = Note.fromJson(json);
      expect(legacy.noteDate, isNull);
      final local = legacy.createdAt.toLocal();
      expect(legacy.dayKey, DateTime(local.year, local.month, local.day));
    });
  });

  group('planning the next day', () {
    test('plan is saved on a separate board dated for the target day',
        () async {
      final controller = NoterrController(
        localVault: LocalVault(profile: 'planning-test'),
        remote: const NoopRemoteSyncService(),
        widgetPublisher: WidgetPublisher(),
      );
      await controller.ensureTodayTodoNote();
      expect(controller.hasPlannedNextDay, isFalse);

      await controller.savePlannedTasks(['Call bank', ' ', 'call bank', 'Gym']);

      final planned = controller.plannedDayNote;
      expect(planned, isNotNull);
      expect(planned!.dayKey, controller.planningTargetDay);
      expect(planned.checklist.map((i) => i.text), ['Call bank', 'Gym']);
      expect(controller.hasPlannedNextDay, isTrue);

      final target = controller.planningTargetDay;
      final today = DateTime.now();
      if (!(target.year == today.year &&
          target.month == today.month &&
          target.day == today.day)) {
        // Planned for tomorrow: today's board and the sticky list don't show it.
        expect(controller.todayTodoNote!.id, isNot(planned.id));
        expect(controller.stickyNotes.any((n) => n.id == planned.id), isFalse);
      }
      controller.dispose();
    });

    test('saving again replaces own tasks and keeps carried ones', () async {
      final controller = NoterrController(
        localVault: LocalVault(profile: 'planning-replace-test'),
        remote: const NoopRemoteSyncService(),
        widgetPublisher: WidgetPublisher(),
      );
      await controller.savePlannedTasks(['A', 'B']);
      final board = controller.plannedDayNote!;
      await controller.updateNote(board.copyWith(checklist: [
        ...board.checklist,
        ChecklistItem(text: 'Old task', carriedFrom: DateTime.now().toUtc()),
      ]));

      await controller.savePlannedTasks(['B', 'C']);
      expect(
        controller.plannedDayNote!.checklist.map((i) => i.text),
        ['B', 'C', 'Old task'],
      );
      controller.dispose();
    });
  });

  group('weekly summary', () {
    final monday = DateTime(2026, 9, 28);

    List<Note> week() => [
          _board(monday, [
            ChecklistItem(text: 'Report', done: true),
            ChecklistItem(text: 'Taxes'),
          ]),
          _board(monday.add(const Duration(days: 1)), [
            ChecklistItem(text: 'Taxes', carriedFrom: monday.toUtc()),
            ChecklistItem(text: 'Gym', done: true),
          ]),
          _board(monday.add(const Duration(days: 2)), [
            ChecklistItem(
              text: 'Taxes',
              done: true,
              carriedFrom: monday.toUtc(),
            ),
            ChecklistItem(text: 'Dentist'),
          ]),
          // Previous week: must not be counted.
          _board(monday.subtract(const Duration(days: 1)), [
            ChecklistItem(text: 'Ignore me'),
          ]),
        ];

    test('counts each task once across carried-over days', () {
      final s = WeeklySummary.compute(week(), monday);
      expect(s.total, 4); // Report, Taxes, Gym, Dentist
      expect(s.done, 3);
      expect(s.pendingTasks, ['Dentist']);
    });

    test('per-day rows show each board as it was', () {
      final s = WeeklySummary.compute(week(), monday);
      expect(s.days, hasLength(7));
      expect(s.days[0].total, 2);
      expect(s.days[0].done, 1);
      expect(s.days[0].added, 2);
      expect(s.days[1].added, 1); // Taxes was carried, Gym is new
      expect(s.days[2].pending, 1);
      expect(s.days[6].total, 0);
    });

    test('until stops at the given day', () {
      final s = WeeklySummary.compute(
        week(),
        monday,
        until: monday.add(const Duration(days: 1)),
      );
      expect(s.days, hasLength(2));
      expect(s.total, 3); // Report, Taxes, Gym
    });

    test('ISO week label and markdown', () {
      final s = WeeklySummary.compute(week(), monday);
      expect(s.isoWeek, '2026-W40');
      final md = s.toMarkdown();
      expect(md, contains('# Week 2026-W40'));
      expect(md, contains('| 4 | 3 | 1 |'));
      expect(md, contains(r'[[2026-09-28\|Mon 28 Sep]]'));
      expect(md, contains('- [ ] Dentist'));
    });

    test('ISO week at a year boundary', () {
      expect(WeeklySummary.compute(const [], DateTime(2026, 12, 28)).isoWeek,
          '2026-W53');
      expect(WeeklySummary.compute(const [], DateTime(2027, 1, 4)).isoWeek,
          '2027-W01');
    });

    test('mondayOf', () {
      expect(mondayOf(DateTime(2026, 10, 4, 9)), DateTime(2026, 9, 28));
      expect(mondayOf(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    });
  });
}
