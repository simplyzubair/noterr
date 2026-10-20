import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../controllers/noterr_controller.dart';
import '../ui/plan_tomorrow_screen.dart';

/// Reminds the user to plan the next day at 21:00, 22:00, 23:00 and 00:00,
/// and stops as soon as a plan for that day is saved.
///
/// Android: one-shot notifications are scheduled for the next [_daysAhead]
/// evenings, skipping evenings already planned, and rescheduled whenever the
/// app starts, resumes or a plan is saved. Inexact alarms are used, so no
/// exact-alarm permission is needed; a reminder can arrive a few minutes late.
///
/// Desktop gets no evening reminders (the user is rarely at the PC at night);
/// the planner still opens from the "Plan tomorrow" button.
///
/// If every reminder is ignored, nothing is lost: open tasks carry over to
/// the next day by themselves at day change.
class EveningReminderService {
  EveningReminderService._();

  static final instance = EveningReminderService._();

  /// Local hours of the reminders. 0 is the midnight one, which belongs to the
  /// evening before.
  static const reminderHours = [21, 22, 23, 0];
  static const _daysAhead = 7;
  static const _idBase = 7100;
  static const _payload = 'plan-next-day';

  final _plugin = FlutterLocalNotificationsPlugin();
  NoterrController? _controller;
  GlobalKey<NavigatorState>? _navigator;
  bool _androidReady = false;
  bool _plannerOpen = false;
  AppLifecycleListener? _lifecycle;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> start(
    NoterrController controller,
    GlobalKey<NavigatorState> navigator,
  ) async {
    _controller = controller;
    _navigator = navigator;
    if (!_isAndroid) return;
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(reschedule()));
    await _startAndroid();
  }

  // ── Android ───────────────────────────────────────────────────────────────

  Future<void> _startAndroid() async {
    try {
      tz_data.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == _payload) unawaited(openPlanner());
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _androidReady = true;

      final launch = await _plugin.getNotificationAppLaunchDetails();
      if ((launch?.didNotificationLaunchApp ?? false) &&
          launch?.notificationResponse?.payload == _payload) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(openPlanner()),
        );
      }
      await reschedule();
    } catch (e) {
      debugPrint('[EveningReminder] Android setup failed: $e');
    }
  }

  /// The reminder times still ahead, for evenings whose next day is not yet
  /// planned. Exposed for tests.
  @visibleForTesting
  static List<({DateTime at, int slot})> upcomingSlots(
    DateTime now,
    bool Function(DateTime day) isPlanned,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final out = <({DateTime at, int slot})>[];
    // Start one evening back so a run just after midnight still sees the
    // 00:00 reminder that belongs to yesterday evening.
    for (var d = -1; d < _daysAhead; d++) {
      final evening = today.add(Duration(days: d));
      final target = evening.add(const Duration(days: 1));
      if (isPlanned(target)) continue;
      for (var h = 0; h < reminderHours.length; h++) {
        final hour = reminderHours[h];
        final at = hour == 0
            ? DateTime(target.year, target.month, target.day)
            : DateTime(evening.year, evening.month, evening.day, hour);
        if (!at.isAfter(now)) continue;
        out.add((at: at, slot: (d + 1) * reminderHours.length + h));
      }
    }
    return out;
  }

  Future<void> reschedule() async {
    final controller = _controller;
    if (!_androidReady || controller == null) return;
    try {
      for (var i = 0; i < (_daysAhead + 1) * reminderHours.length; i++) {
        await _plugin.cancel(id: _idBase + i);
      }
      final slots = upcomingSlots(DateTime.now(), controller.isDayPlanned);
      for (final s in slots) {
        final last = s.at.hour == 0;
        await _plugin.zonedSchedule(
          id: _idBase + s.slot,
          scheduledDate: tz.TZDateTime.from(s.at, tz.UTC),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: last ? 'Last call: plan today' : 'Plan tomorrow',
          body: last
              ? 'Skip it and open tasks carry over by themselves.'
              : "Tick off today's tasks, then write tomorrow's to-dos.",
          payload: _payload,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'evening_plan',
              'Evening planning',
              channelDescription:
                  'Reminders at 9, 10, 11 pm and midnight to plan the next day',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[EveningReminder] reschedule failed: $e');
    }
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  /// Opens the planner once, even if several reminders fire.
  Future<void> openPlanner() async {
    final controller = _controller;
    final nav = _navigator?.currentState;
    if (controller == null || nav == null || _plannerOpen) return;
    if (!controller.isUnlocked) return;
    _plannerOpen = true;
    try {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => PlanTomorrowScreen(
            controller: controller,
            onSaved: () => unawaited(reschedule()),
          ),
        ),
      );
    } finally {
      _plannerOpen = false;
    }
  }
}
