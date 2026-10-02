import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/controllers/noterr_controller.dart';
import 'package:noterr/models/plan.dart';
import 'package:noterr/services/local_vault.dart';
import 'package:noterr/services/remote_sync_service.dart';
import 'package:noterr/services/widget_publisher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active plan task materializes once in the unified Today board',
      () async {
    final controller = NoterrController(
      localVault: LocalVault(profile: 'plan-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );
    final today = dateOnly(DateTime.now());
    final task = PlanItem(
      text: 'Walk 1 km',
      kind: PlanItemKind.habit,
      cadence: PlanCadence.daily,
    );
    final plan = Plan(
      title: 'Health',
      sourceText: 'Daily:\n- Walk 1 km',
      startDate: today.subtract(const Duration(days: 1)),
      endDate: today.add(const Duration(days: 30)),
      items: [task],
    );

    await controller.savePlan(plan);
    await controller.ensureTodayTodoNote();

    final board = controller.todayTodoNote;
    expect(controller.plans.single.title, 'Health');
    expect(board, isNotNull);
    expect(board!.checklist, hasLength(1));
    expect(board.checklist.single.text, 'Walk 1 km');
    expect(board.checklist.single.planId, plan.id);
    expect(board.checklist.single.planItemId, task.id);
    expect(
      board.checklist.single.id,
      planOccurrenceId(plan.id, task.id, today),
    );

    await controller.ensureTodayTodoNote();
    expect(controller.todayTodoNote!.checklist, hasLength(1));
    controller.dispose();
  });

  test('deleting today plan task does not make it reappear today', () async {
    final controller = NoterrController(
      localVault: LocalVault(profile: 'plan-delete-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );
    final today = dateOnly(DateTime.now());
    final task = PlanItem(
      text: 'Read 10 pages',
      kind: PlanItemKind.habit,
      cadence: PlanCadence.daily,
    );
    final plan = Plan(
      title: 'Reading',
      sourceText: 'Daily:\n- Read 10 pages',
      startDate: today,
      endDate: today.add(const Duration(days: 30)),
      items: [task],
    );

    await controller.savePlan(plan);
    final item = controller.todayTodoNote!.checklist.single;
    await controller.removeTodayTask(item);
    await controller.ensureTodayTodoNote();

    expect(controller.todayTodoNote!.checklist, isEmpty);
    expect(
      controller.todayTodoNote!.deletedChecklistItemKeys,
      contains('id:${planOccurrenceId(plan.id, task.id, today)}'),
    );
    controller.dispose();
  });

  test('pausing a plan removes its pending Today task but keeps the plan',
      () async {
    final controller = NoterrController(
      localVault: LocalVault(profile: 'paused-plan-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );
    final today = dateOnly(DateTime.now());
    final plan = Plan(
      title: 'Paused',
      sourceText: 'Daily:\n- Hidden task',
      startDate: today,
      endDate: today.add(const Duration(days: 7)),
      items: [
        PlanItem(
          text: 'Hidden task',
          kind: PlanItemKind.habit,
          cadence: PlanCadence.daily,
        ),
      ],
    );

    await controller.savePlan(plan);
    expect(controller.todayTodoNote!.checklist, hasLength(1));
    await controller.setPlanActive(plan, false);

    expect(controller.plans.single.isActive, isFalse);
    expect(controller.todayTodoNote!.checklist, isEmpty);
    controller.dispose();
  });
}
