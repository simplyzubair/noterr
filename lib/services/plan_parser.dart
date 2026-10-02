import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/plan.dart';

class PlanParser {
  const PlanParser();

  Plan parse({
    required String sourceText,
    required DateTime startDate,
    required DateTime endDate,
    String? title,
    Plan? existing,
  }) {
    final start = dateOnly(startDate);
    final end = dateOnly(endDate);
    if (end.isBefore(start)) {
      throw const FormatException('End date must be after the start date.');
    }

    var detectedTitle = title?.trim() ?? '';
    var section = _PlanSection.tasks;
    final parsedItems = <PlanItem>[];
    for (final rawLine in sourceText.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final headingLine = line.replaceFirst(RegExp(r'^[#\s]+'), '');
      final planTitle = RegExp(
        r'^plan\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(headingLine);
      if (planTitle != null) {
        if (detectedTitle.isEmpty) detectedTitle = planTitle.group(1)!.trim();
        continue;
      }
      final heading = _headingFor(line);
      if (heading != null) {
        section = heading;
        continue;
      }
      final text = _cleanItemText(line);
      if (text.isEmpty) continue;
      final kind = _kindFor(section, text);
      final cadence = _cadenceFor(section, text, kind);
      parsedItems.add(
        PlanItem(
          text: text,
          kind: kind,
          cadence: cadence,
          weekdays: _weekdaysFrom(text),
          scheduledDate: _explicitDate(text, start, end),
        ),
      );
    }

    if (parsedItems.isEmpty) {
      throw const FormatException('Add at least one plan item.');
    }
    final scheduled = _spreadUnscheduled(parsedItems, start, end);
    return Plan(
      id: existing?.id,
      title: detectedTitle.isEmpty ? 'My plan' : detectedTitle,
      sourceText: sourceText.trim(),
      startDate: start,
      endDate: end,
      items: scheduled,
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  _PlanSection? _headingFor(String value) {
    final normalized = value
        .replaceAll(RegExp(r'^[#\s]+'), '')
        .replaceAll(RegExp(r':\s*$'), '')
        .trim()
        .toLowerCase();
    return switch (normalized) {
      'outcome' || 'outcomes' || 'goal' || 'goals' => _PlanSection.outcomes,
      'project' || 'projects' => _PlanSection.projects,
      'habit' || 'habits' => _PlanSection.habits,
      'daily' || 'daily plan' || 'every day' => _PlanSection.daily,
      'weekly' || 'weekly plan' => _PlanSection.weekly,
      'monthly' || 'monthly plan' => _PlanSection.monthly,
      'task' ||
      'tasks' ||
      'one-time tasks' ||
      'one time tasks' =>
        _PlanSection.tasks,
      _ => null,
    };
  }

  String _cleanItemText(String value) {
    return value
        .replaceFirst(RegExp(r'^[-*+•]\s*'), '')
        .replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '')
        .replaceFirst(RegExp(r'^\d+[.)]\s*'), '')
        .trim();
  }

  PlanItemKind _kindFor(_PlanSection section, String text) {
    if (section == _PlanSection.outcomes || section == _PlanSection.monthly) {
      return PlanItemKind.outcome;
    }
    if (section == _PlanSection.projects) return PlanItemKind.project;
    if (section == _PlanSection.habits || section == _PlanSection.daily) {
      return PlanItemKind.habit;
    }

    final normalized = text.toLowerCase();
    if (RegExp(r'\b(every|daily|each day|habit)\b').hasMatch(normalized)) {
      return PlanItemKind.habit;
    }
    if (RegExp(r'^(lose|gain|reduce|increase|achieve|reach|improve)\b')
        .hasMatch(normalized)) {
      return PlanItemKind.outcome;
    }
    if (RegExp(r'\b(project|launch|build|deliver)\b').hasMatch(normalized) &&
        !RegExp(r'^(call|email|write|review|buy|walk|read)\b')
            .hasMatch(normalized)) {
      return PlanItemKind.project;
    }
    return PlanItemKind.task;
  }

  PlanCadence _cadenceFor(
    _PlanSection section,
    String text,
    PlanItemKind kind,
  ) {
    if (kind == PlanItemKind.outcome || kind == PlanItemKind.project) {
      return PlanCadence.once;
    }
    final normalized = text.toLowerCase();
    if (section == _PlanSection.daily || section == _PlanSection.habits) {
      return PlanCadence.daily;
    }
    if (section == _PlanSection.weekly ||
        RegExp(r'\b(weekly|every week|every (mon|tue|wed|thu|fri|sat|sun))')
            .hasMatch(normalized)) {
      return PlanCadence.weekly;
    }
    if (RegExp(r'\b(monthly|every month)\b').hasMatch(normalized)) {
      return PlanCadence.monthly;
    }
    if (RegExp(
            r'\b(daily|every day|each day|weekdays|monday\s*(to|through|-)\s*friday|monday\s*(to|through|-)\s*saturday)\b')
        .hasMatch(normalized)) {
      return PlanCadence.daily;
    }
    return PlanCadence.once;
  }

  List<int> _weekdaysFrom(String text) {
    final value = text.toLowerCase();
    if (value.contains('weekdays')) {
      return const [
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
      ];
    }
    final dayMatches = <({int index, int weekday})>[];
    for (final entry in _weekdayPatterns.entries) {
      for (final match in entry.value.allMatches(value)) {
        dayMatches.add((index: match.start, weekday: entry.key));
      }
    }
    dayMatches.sort((a, b) => a.index.compareTo(b.index));
    final ordered = dayMatches.map((item) => item.weekday).toList();
    if (ordered.length >= 2 &&
        RegExp(r'\b(to|through|thru)\b|[-–]').hasMatch(value)) {
      final first = ordered.first;
      final last = ordered[1];
      final range = <int>[first];
      var current = first;
      while (current != last && range.length < 7) {
        current = current == DateTime.sunday ? DateTime.monday : current + 1;
        range.add(current);
      }
      return range;
    }
    return ordered.toSet().toList()..sort();
  }

  DateTime? _explicitDate(String text, DateTime start, DateTime end) {
    final iso = RegExp(r'\b(\d{4}-\d{1,2}-\d{1,2})\b').firstMatch(text);
    if (iso != null) {
      final parsed = DateTime.tryParse(iso.group(1)!);
      if (parsed != null) return _clampDate(parsed, start, end);
    }
    final named = RegExp(
      r'\b(?:on|by)\s+(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (named == null) return null;
    final value = '${named.group(1)} ${named.group(2)} ${start.year}';
    for (final format in ['d MMM yyyy', 'd MMMM yyyy']) {
      try {
        return _clampDate(DateFormat(format).parse(value), start, end);
      } catch (_) {}
    }
    return null;
  }

  List<PlanItem> _spreadUnscheduled(
    List<PlanItem> items,
    DateTime start,
    DateTime end,
  ) {
    final result = [...items];
    final oneTimeIndexes = <int>[];
    final weeklyIndexes = <int>[];
    final monthlyIndexes = <int>[];
    for (var index = 0; index < result.length; index++) {
      final item = result[index];
      if (!item.createsDailyTask || item.scheduledDate != null) continue;
      switch (item.cadence) {
        case PlanCadence.once:
          oneTimeIndexes.add(index);
        case PlanCadence.weekly:
          if (item.weekdays.isEmpty) weeklyIndexes.add(index);
        case PlanCadence.monthly:
          monthlyIndexes.add(index);
        case PlanCadence.daily:
          break;
      }
    }

    final span = end.difference(start).inDays;
    for (var position = 0; position < oneTimeIndexes.length; position++) {
      final fraction = (position + 1) / (oneTimeIndexes.length + 1);
      final offset = (span * fraction).round();
      final index = oneTimeIndexes[position];
      result[index] = result[index].copyWith(
        scheduledDate: start.add(Duration(days: offset)),
      );
    }
    for (var position = 0; position < weeklyIndexes.length; position++) {
      final index = weeklyIndexes[position];
      final offset = position % 7;
      result[index] = result[index].copyWith(
        scheduledDate: start.add(Duration(days: offset)),
      );
    }
    for (var position = 0; position < monthlyIndexes.length; position++) {
      final index = monthlyIndexes[position];
      final day = math.min(start.day + position, daysInPlanMonth(start));
      result[index] = result[index].copyWith(
        scheduledDate: DateTime(start.year, start.month, day),
      );
    }
    return result;
  }

  DateTime _clampDate(DateTime value, DateTime start, DateTime end) {
    final date = dateOnly(value);
    if (date.isBefore(start)) return start;
    if (date.isAfter(end)) return end;
    return date;
  }
}

enum _PlanSection { outcomes, projects, habits, daily, weekly, monthly, tasks }

final Map<int, RegExp> _weekdayPatterns = {
  DateTime.monday: RegExp(r'\bmon(?:day)?\b'),
  DateTime.tuesday: RegExp(r'\btue(?:sday)?\b'),
  DateTime.wednesday: RegExp(r'\bwed(?:nesday)?\b'),
  DateTime.thursday: RegExp(r'\bthu(?:rsday)?\b'),
  DateTime.friday: RegExp(r'\bfri(?:day)?\b'),
  DateTime.saturday: RegExp(r'\bsat(?:urday)?\b'),
  DateTime.sunday: RegExp(r'\bsun(?:day)?\b'),
};
