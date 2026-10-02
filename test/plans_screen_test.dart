import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/controllers/noterr_controller.dart';
import 'package:noterr/models/plan.dart';
import 'package:noterr/services/local_vault.dart';
import 'package:noterr/services/remote_sync_service.dart';
import 'package:noterr/services/widget_publisher.dart';
import 'package:noterr/ui/plans_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plans remain secondary and fit mobile', (tester) async {
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = NoterrController(
      localVault: LocalVault(profile: 'plans-screen-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );
    final today = dateOnly(DateTime.now());
    await tester.runAsync(
      () => controller.savePlan(
        Plan(
          title: 'August Health',
          sourceText: 'Daily:\n- Walk 1 km',
          startDate: today,
          endDate: today.add(const Duration(days: 30)),
          items: [
            PlanItem(
              text: 'Walk 1 km',
              kind: PlanItemKind.habit,
              cadence: PlanCadence.daily,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: PlansScreen(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('August Health'), findsOneWidget);
    expect(find.text('Plans'), findsWidgets);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('plan import form fits mobile', (tester) async {
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = NoterrController(
      localVault: LocalVault(profile: 'plan-import-screen-test'),
      remote: const NoopRemoteSyncService(),
      widgetPublisher: WidgetPublisher(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlanImportScreen(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Import plan'), findsOneWidget);
    expect(find.text('Review schedule'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
