import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/controllers/noterr_controller.dart';
import 'package:noterr/models/note.dart';

Note _history(DateTime day, List<ChecklistItem> items) {
  return Note(
    type: NoteType.full,
    title: 'board',
    body: '',
    colorHex: 'F2F2F2',
    createdAt: day.toUtc(),
    updatedAt: day.toUtc(),
    deviceId: 'test',
    noteDate: day,
    boardName: 'History',
    isArchived: true,
    checklist: items,
  );
}

void main() {
  group('ticking a task', () {
    test('records when it was ticked', () {
      final item = ChecklistItem(text: 'Gym');
      expect(item.doneChangedAt, isNull);
      final ticked = item.copyWith(done: true);
      expect(ticked.done, isTrue);
      expect(ticked.doneChangedAt, isNotNull);
      // Other edits keep the tick time.
      expect(ticked.copyWith(text: 'Gym!').doneChangedAt, ticked.doneChangedAt);
    });

    test('tick time survives saving and loading', () {
      final ticked = ChecklistItem(text: 'Gym').copyWith(done: true);
      final back = ChecklistItem.fromJson(ticked.toJson());
      expect(back.doneChangedAt, ticked.doneChangedAt);
    });
  });

  group('mergeChecklists', () {
    test('a tick from the other device wins over an older open copy', () {
      final open = ChecklistItem(id: 'a', text: 'Call bank');
      final ticked = open.copyWith(
        done: true,
        doneChangedAt: DateTime.utc(2026, 10, 20, 22),
      );
      final merged = NoterrController.mergeChecklists([
        [open, ChecklistItem(id: 'b', text: 'Gym')],
        [ticked],
      ], {});
      expect(merged.map((i) => i.text), ['Call bank', 'Gym']);
      expect(merged.first.done, isTrue);
    });

    test('the newest change wins, also when it is an untick', () {
      final item = ChecklistItem(id: 'a', text: 'Call bank');
      final ticked = item.copyWith(
        done: true,
        doneChangedAt: DateTime.utc(2026, 10, 20, 9),
      );
      final unticked = item.copyWith(
        done: false,
        doneChangedAt: DateTime.utc(2026, 10, 20, 10),
      );
      final merged = NoterrController.mergeChecklists([
        [ticked],
        [unticked],
      ], {});
      expect(merged.single.done, isFalse);
    });

    test('matches the same task by text and skips deleted ones', () {
      final merged = NoterrController.mergeChecklists([
        [ChecklistItem(id: 'a', text: 'Gym')],
        [
          ChecklistItem(id: 'b', text: ' gym ').copyWith(
            done: true,
            doneChangedAt: DateTime.utc(2026, 10, 20),
          ),
          ChecklistItem(id: 'c', text: 'Old'),
        ],
      ], {'id:c'});
      expect(merged.single.id, 'a');
      expect(merged.single.done, isTrue);
    });
  });

  group('carriedTaskDoneAtSource', () {
    final day = DateTime(2026, 10, 20);
    final carried = ChecklistItem(text: 'Call bank', carriedFrom: day.toUtc());

    test('is true when the source day shows the task done', () {
      final notes = [
        _history(day, [
          ChecklistItem(text: 'call bank').copyWith(done: true),
        ]),
      ];
      expect(NoterrController.carriedTaskDoneAtSource(carried, notes), isTrue);
    });

    test('is false when the source day still has it open', () {
      final notes = [
        _history(day, [ChecklistItem(text: 'Call bank')]),
      ];
      expect(NoterrController.carriedTaskDoneAtSource(carried, notes), isFalse);
    });

    test('is false for tasks that were not carried, or another day', () {
      final notes = [
        _history(DateTime(2026, 10, 19), [
          ChecklistItem(text: 'Call bank').copyWith(done: true),
        ]),
      ];
      expect(NoterrController.carriedTaskDoneAtSource(carried, notes), isFalse);
      expect(
        NoterrController.carriedTaskDoneAtSource(
          ChecklistItem(text: 'Call bank'),
          [
            _history(day, [
              ChecklistItem(text: 'Call bank').copyWith(done: true),
            ]),
          ],
        ),
        isFalse,
      );
    });
  });
}
