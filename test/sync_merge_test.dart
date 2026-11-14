import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/controllers/noterr_controller.dart';
import 'package:noterr/models/note.dart';
import 'package:noterr/services/local_vault.dart';
import 'package:noterr/services/remote_sync_service.dart';
import 'package:noterr/services/widget_publisher.dart';

NoterrController _controller() => NoterrController(
      localVault: LocalVault(profile: 'sync-merge-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );

Note _note({String board = 'Personal', String body = 'first'}) {
  final at = DateTime.utc(2026, 11, 15, 9);
  return Note(
    type: NoteType.full,
    title: 'note',
    body: body,
    colorHex: 'F2F2F2',
    createdAt: at,
    updatedAt: at,
    deviceId: 'phone',
    noteDate: DateTime(2026, 11, 15),
    boardName: board,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the last change wins', () {
    test('a later change beats a copy with a higher revision', () {
      final base = _note();
      // The phone saved many times, the PC changed it once, but later.
      final phone = base.copyWith(
        body: 'from phone',
        revision: 40,
        updatedAt: DateTime.utc(2026, 11, 15, 10),
      );
      final pc = base.copyWith(
        body: 'from pc',
        revision: 3,
        updatedAt: DateTime.utc(2026, 11, 15, 11),
      );

      final onPhone = _controller().mergeCopies(phone, pc);
      expect(onPhone.body, 'from pc');
      // Revisions never go down.
      expect(onPhone.revision, 40);

      final onPc = _controller().mergeCopies(pc, phone);
      expect(onPc.body, 'from pc');
    });

    test('an older copy from the server does not undo a newer one', () {
      final base = _note();
      final newer = base.copyWith(
        body: 'new',
        updatedAt: DateTime.utc(2026, 11, 15, 11),
      );
      final older = base.copyWith(
        body: 'old',
        revision: 9,
        updatedAt: DateTime.utc(2026, 11, 15, 10),
      );
      expect(_controller().mergeCopies(newer, older).body, 'new');
    });
  });

  group('today board', () {
    test('text comes from the last change, tasks from both devices', () {
      final base = _note(board: 'Today', body: 'buy milk');
      final phone = base.copyWith(
        updatedAt: DateTime.utc(2026, 11, 15, 10),
        checklist: [ChecklistItem(id: 'a', text: 'Gym')],
      );
      final pc = base.copyWith(
        body: 'buy milk and eggs',
        updatedAt: DateTime.utc(2026, 11, 15, 11),
        checklist: [ChecklistItem(id: 'b', text: 'Call bank')],
      );

      final onPhone = _controller().mergeCopies(phone, pc);
      // Not "buy milk and eggs" followed by the old "buy milk".
      expect(onPhone.body, 'buy milk and eggs');
      expect(
        onPhone.checklist.map((item) => item.text),
        ['Call bank', 'Gym'],
      );
      // It holds more than the server's copy, so it goes back up as newest.
      expect(onPhone.updatedAt.isAfter(pc.updatedAt), isTrue);

      // The PC takes it as it is, and nothing bounces back and forth.
      final onPc = _controller().mergeCopies(pc, onPhone);
      expect(onPc.updatedAt, onPhone.updatedAt);
      expect(onPc.body, 'buy milk and eggs');
      expect(onPc.checklist.map((item) => item.text), ['Call bank', 'Gym']);
    });

    test('a copy that adds nothing is taken unchanged', () {
      final base = _note(board: 'Today');
      final phone = base.copyWith(
        checklist: [ChecklistItem(id: 'a', text: 'Gym')],
      );
      final pc = phone.copyWith(
        updatedAt: DateTime.utc(2026, 11, 15, 11),
        checklist: [
          ChecklistItem(id: 'a', text: 'Gym'),
          ChecklistItem(id: 'b', text: 'Call bank'),
        ],
      );
      final onPhone = _controller().mergeCopies(phone, pc);
      expect(onPhone.updatedAt, pc.updatedAt);
      expect(onPhone.checklist.length, 2);
    });
  });
}
