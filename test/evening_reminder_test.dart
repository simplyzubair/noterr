import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/controllers/noterr_controller.dart';
import 'package:noterr/services/evening_reminder_service.dart';
import 'package:noterr/services/local_vault.dart';
import 'package:noterr/services/remote_sync_service.dart';
import 'package:noterr/services/widget_publisher.dart';
import 'package:noterr/ui/plan_tomorrow_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reminder slots', () {
    bool never(DateTime _) => false;

    test('at 20:00 the four reminders tonight come first', () {
      final now = DateTime(2026, 10, 7, 20);
      final slots = EveningReminderService.upcomingSlots(now, never);
      expect(slots.take(4).map((s) => s.at), [
        DateTime(2026, 10, 7, 21),
        DateTime(2026, 10, 7, 22),
        DateTime(2026, 10, 7, 23),
        DateTime(2026, 10, 8),
      ]);
      // A week of evenings, four each, no duplicate ids.
      expect(slots, hasLength(28));
      expect(slots.map((s) => s.slot).toSet(), hasLength(28));
    });

    test('at 22:30 only 23:00 and midnight remain tonight', () {
      final now = DateTime(2026, 10, 7, 22, 30);
      final slots = EveningReminderService.upcomingSlots(now, never);
      expect(slots.first.at, DateTime(2026, 10, 7, 23));
      expect(slots[1].at, DateTime(2026, 10, 8));
      expect(slots[2].at, DateTime(2026, 10, 8, 21));
    });

    test('a planned day gets no reminders the evening before', () {
      final now = DateTime(2026, 10, 7, 20);
      bool planned(DateTime d) => d == DateTime(2026, 10, 8);
      final slots = EveningReminderService.upcomingSlots(now, planned);
      expect(slots.first.at, DateTime(2026, 10, 8, 21));
      expect(
        slots.where((s) => s.at.isBefore(DateTime(2026, 10, 8, 1))),
        isEmpty,
      );
    });

    test('just after midnight nothing is left for the night that ended', () {
      final now = DateTime(2026, 10, 8, 0, 5);
      final slots = EveningReminderService.upcomingSlots(now, never);
      expect(slots.first.at, DateTime(2026, 10, 8, 21));
    });
  });

  testWidgets('planner saves tasks for the target day', (tester) async {
    final controller = NoterrController(
      localVault: LocalVault(profile: 'planner-screen-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );
    await tester.runAsync(controller.ensureTodayTodoNote);

    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlanTomorrowScreen(
                    controller: controller,
                    onSaved: () => saved = true,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Buy milk'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Save plan'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(saved, isTrue);
    expect(controller.plannedOwnTasks, ['Buy milk']);
    expect(controller.hasPlannedNextDay, isTrue);
    controller.dispose();
  });
}
