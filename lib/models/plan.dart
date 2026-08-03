import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _planUuid = Uuid();

enum PlanItemKind {
  outcome,
  project,
  task,
  habit;

  static PlanItemKind fromJson(String? value) {
    return PlanItemKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => PlanItemKind.task,
    );
  }

  String get label => switch (this) {
        PlanItemKind.outcome => 'Outcome',
        PlanItemKind.project => 'Project',
        PlanItemKind.task => 'Task',
        PlanItemKind.habit => 'Habit',
      };
}

enum PlanCadence {
  once,
  daily,
  weekly,
  monthly;

  static PlanCadence fromJson(String? value) {
    return PlanCadence.values.firstWhere(
      (cadence) => cadence.name == value,
      orElse: () => PlanCadence.once,
    );
  }

  String get label => switch (this) {
        PlanCadence.once => 'Once',
        PlanCadence.daily => 'Daily',
        PlanCadence.weekly => 'Weekly',
        PlanCadence.monthly => 'Monthly',
      };
}

class PlanItem {
  PlanItem({
    String? id,
    required this.text,
    this.kind = PlanItemKind.task,
    this.cadence = PlanCadence.once,
    this.weekdays = const [],
    this.scheduledDate,
  }) : id = id ?? _planUuid.v4();

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        id: json['id'] as String?,
        text: json['text'] as String? ?? '',
        kind: PlanItemKind.fromJson(json['kind'] as String?),
        cadence: PlanCadence.fromJson(json['cadence'] as String?),
        weekdays: ((json['weekdays'] as List?) ?? const [])
            .whereType<num>()
            .map((day) => day.toInt())
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet()
            .toList()
          ..sort(),
        scheduledDate: _parsePlanDate(json['scheduledDate'] as String?),
      );

  final String id;
  final String text;
  final PlanItemKind kind;
  final PlanCadence cadence;
  final List<int> weekdays;
  final DateTime? scheduledDate;

  bool get createsDailyTask =>
      kind == PlanItemKind.task || kind == PlanItemKind.habit;

  bool occursOn(DateTime value, Plan plan) {
    if (!createsDailyTask) return false;
    final date = dateOnly(value);
    if (date.isBefore(plan.startDate) || date.isAfter(plan.endDate)) {
      return false;
    }
    final anchor = dateOnly(scheduledDate ?? plan.startDate);
    return switch (cadence) {
      PlanCadence.once => isSamePlanDate(date, anchor),
      PlanCadence.daily => weekdays.isEmpty || weekdays.contains(date.weekday),
      PlanCadence.weekly => weekdays.isEmpty
          ? date.weekday == anchor.weekday
          : weekdays.contains(date.weekday),
      PlanCadence.monthly =>
        date.day == math.min(anchor.day, daysInPlanMonth(date)),
    };
  }

  PlanItem copyWith({
    String? text,
    PlanItemKind? kind,
    PlanCadence? cadence,
    List<int>? weekdays,
    DateTime? scheduledDate,
    bool clearScheduledDate = false,
  }) {
    return PlanItem(
      id: id,
      text: text ?? this.text,
      kind: kind ?? this.kind,
      cadence: cadence ?? this.cadence,
      weekdays: weekdays ?? this.weekdays,
      scheduledDate:
          clearScheduledDate ? null : scheduledDate ?? this.scheduledDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'kind': kind.name,
        'cadence': cadence.name,
        'weekdays': weekdays,
        'scheduledDate': _formatPlanDate(scheduledDate),
      };
}

class Plan {
  Plan({
    String? id,
    required this.title,
    required this.sourceText,
    required DateTime startDate,
    required DateTime endDate,
    required this.items,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _planUuid.v4(),
        startDate = dateOnly(startDate),
        endDate = dateOnly(endDate),
        createdAt = (createdAt ?? DateTime.now()).toUtc(),
        updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  factory Plan.fromJson(Map<String, dynamic> json) {
    final start =
        _parsePlanDate(json['startDate'] as String?) ?? DateTime.now();
    final end = _parsePlanDate(json['endDate'] as String?) ?? start;
    return Plan(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'Untitled plan',
      sourceText: json['sourceText'] as String? ?? '',
      startDate: start,
      endDate: end,
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => PlanItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  final String id;
  final String title;
  final String sourceText;
  final DateTime startDate;
  final DateTime endDate;
  final List<PlanItem> items;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isInRange(DateTime date) {
    final value = dateOnly(date);
    return !value.isBefore(startDate) && !value.isAfter(endDate);
  }

  List<PlanItem> itemsFor(DateTime date) {
    return items.where((item) => item.occursOn(date, this)).toList();
  }

  Plan copyWith({
    String? title,
    String? sourceText,
    DateTime? startDate,
    DateTime? endDate,
    List<PlanItem>? items,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return Plan(
      id: id,
      title: title ?? this.title,
      sourceText: sourceText ?? this.sourceText,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      items: items ?? this.items,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'title': title,
        'sourceText': sourceText,
        'startDate': _formatPlanDate(startDate),
        'endDate': _formatPlanDate(endDate),
        'items': items.map((item) => item.toJson()).toList(),
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class PlanOccurrence {
  const PlanOccurrence({
    required this.plan,
    required this.item,
    required this.date,
  });

  final Plan plan;
  final PlanItem item;
  final DateTime date;

  String get id => planOccurrenceId(plan.id, item.id, date);
}

String planOccurrenceId(String planId, String itemId, DateTime date) {
  return 'plan:$planId:$itemId:${DateFormat('yyyyMMdd').format(dateOnly(date))}';
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSamePlanDate(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

int daysInPlanMonth(DateTime date) =>
    DateTime(date.year, date.month + 1, 0).day;

String? _formatPlanDate(DateTime? date) {
  if (date == null) return null;
  return DateFormat('yyyy-MM-dd').format(dateOnly(date));
}

DateTime? _parsePlanDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : dateOnly(parsed);
}
