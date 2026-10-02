import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noterr/models/note.dart';
import 'package:noterr/models/plan.dart';
import 'package:noterr/services/plan_parser.dart';

void main() {
  const parser = PlanParser();

  test('classifies a structured plan and reads its schedule', () {
    final plan = parser.parse(
      sourceText: '''
# Plan: August Health

Outcomes:
- Lose 1 kg

Projects:
- Improve physical fitness

Daily:
- Walk 1 km Monday to Saturday

Weekly:
- Record weight every Sunday

Tasks:
- Buy walking shoes
''',
      startDate: DateTime(2026, 8),
      endDate: DateTime(2026, 8, 31),
    );

    expect(plan.title, 'August Health');
    expect(plan.items, hasLength(5));
    expect(plan.items[0].kind, PlanItemKind.outcome);
    expect(plan.items[1].kind, PlanItemKind.project);
    expect(plan.items[2].kind, PlanItemKind.habit);
    expect(plan.items[2].cadence, PlanCadence.daily);
    expect(plan.items[2].weekdays, [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
    ]);
    expect(plan.items[3].kind, PlanItemKind.habit);
    expect(plan.items[3].cadence, PlanCadence.weekly);
    expect(plan.items[3].weekdays, [DateTime.sunday]);
    expect(plan.items[4].scheduledDate, isNotNull);
  });

  test('only actionable items occur on matching dates', () {
    final plan = parser.parse(
      sourceText: '''
Outcomes:
- Lose 1 kg
Daily:
- Walk 1 km Monday to Saturday
Weekly:
- Weigh myself every Sunday
''',
      startDate: DateTime(2026, 8, 3),
      endDate: DateTime(2026, 8, 31),
      title: 'Health',
    );

    expect(
      plan.itemsFor(DateTime(2026, 8, 3)).map((item) => item.text),
      contains('Walk 1 km Monday to Saturday'),
    );
    expect(
      plan.itemsFor(DateTime(2026, 8, 9)).map((item) => item.text),
      contains('Weigh myself every Sunday'),
    );
    expect(
      plan.itemsFor(DateTime(2026, 8, 9)).map((item) => item.text),
      isNot(contains('Walk 1 km Monday to Saturday')),
    );
    expect(
      plan.itemsFor(DateTime(2026, 8, 3)).map((item) => item.text),
      isNot(contains('Lose 1 kg')),
    );
  });

  test('spreads unscheduled one-time tasks through the selected range', () {
    final plan = parser.parse(
      sourceText: '''
Tasks:
- Prepare documents
- Book appointment
- Buy supplies
''',
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      title: 'August',
    );

    final dates = plan.items.map((item) => item.scheduledDate).toSet();
    expect(dates, hasLength(3));
    expect(dates.every((date) => date != null), isTrue);
    expect(
      dates.every(
        (date) =>
            !date!.isBefore(plan.startDate) && !date.isAfter(plan.endDate),
      ),
      isTrue,
    );
  });

  test('plan and planned checklist metadata round trip', () {
    final plan = parser.parse(
      sourceText: 'Daily:\n- Walk 1 km',
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      title: 'Health',
    );
    final restoredPlan = Plan.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(plan.toJson())) as Map,
      ),
    );
    final item = ChecklistItem(
      id: planOccurrenceId(plan.id, plan.items.first.id, plan.startDate),
      text: plan.items.first.text,
      planId: plan.id,
      planItemId: plan.items.first.id,
      scheduledFor: plan.startDate,
    );
    final restoredItem = ChecklistItem.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(item.toJson())) as Map,
      ),
    );

    expect(restoredPlan.id, plan.id);
    expect(restoredPlan.items.single.kind, PlanItemKind.habit);
    expect(restoredItem.isFromPlan, isTrue);
    expect(restoredItem.planId, plan.id);
    expect(restoredItem.planItemId, plan.items.first.id);
    expect(
      isSamePlanDate(restoredItem.scheduledFor!, plan.startDate),
      isTrue,
    );
  });

  test('rejects an empty or backwards plan', () {
    expect(
      () => parser.parse(
        sourceText: '',
        startDate: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 31),
      ),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        sourceText: 'Tasks:\n- Test',
        startDate: DateTime(2026, 9),
        endDate: DateTime(2026, 8),
      ),
      throwsFormatException,
    );
  });
}
