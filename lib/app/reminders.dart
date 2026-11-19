import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Day;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/conti_state.dart';
import '../core/dates.dart';
import '../core/model/crm.dart';
import '../core/money.dart';
import 'error_log.dart';
import 'l10n.dart';

/// Eine geplante Erinnerung.
class PlannedReminder {
  PlannedReminder(this.id, this.at, this.title, this.body);
  final int id;
  final DateTime at;
  final String title;
  final String body;
}

/// Mitteilungen auf dem Gerät (Android und Windows): Fristen von Aufgaben
/// und aufgebrauchte Abos. Geplant wird immer alles neu, wenn sich etwas
/// ändert (höchstens [maxPlanned] Stück in den nächsten 90 Tagen).
class Reminders {
  Reminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const maxPlanned = 60;

  /// Geht es auf diesem Gerät?
  static bool get supported => Platform.isAndroid || Platform.isWindows;

  static const _channel = AndroidNotificationDetails(
    'conti-erinnerungen',
    'Erinnerungen',
    channelDescription: 'Fristen von Aufgaben und aufgebrauchte Abos',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final name = (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Zurich'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'Conti',
            appUserModelId: 'Conti.Conti.Buchhaltung',
            guid: '6d2c66a5-e74c-4b19-9f96-077724d3a9c2',
          ),
        ),
      );
      _ready = true;
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Mitteilungen einrichten');
    }
  }

  /// Android 13+: einmal um Erlaubnis fragen.
  static Future<void> askPermission() async {
    if (!_ready || !Platform.isAndroid) return;
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Erlaubnis für Mitteilungen');
    }
  }

  /// Welche Erinnerungen anstehen (ohne Gerät, auch für Tests).
  static List<PlannedReminder> plan(ContiState s, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final hour = s.device.reminderHour;
    final limit = t.add(const Duration(days: 90));
    final out = <PlannedReminder>[];
    final rules = [...s.business.deadlineRules]..sort((a, b) => b.days.compareTo(a.days));
    for (final task in s.openTasks) {
      final due = task.due;
      if (due == null) continue;
      final who = s.client(task.clientId)?.displayName;
      final body = who == null ? task.title : '${task.title} · $who';
      void add(int daysBefore, String title) {
        final day = due.subtract(Duration(days: daysBefore));
        final at = DateTime(day.year, day.month, day.day, hour);
        if (at.isAfter(t) && at.isBefore(limit)) out.add(PlannedReminder(_id(task.id, daysBefore), at, title, body));
      }

      for (final r in rules) {
        if (r.days > 0) add(r.days, tr('Frist in ${r.days} Tagen', 'Due in ${r.days} days'));
      }
      add(0, tr('Heute fällig', 'Due today'));
    }
    // Rechnungen: am Tag nach der Frist, falls noch nicht bezahlt.
    for (final o in s.orders.where((o) => o.status == OrderStatus.invoiced && o.dueDate != null)) {
      final day = o.dueDate!.add(const Duration(days: 1));
      final at = DateTime(day.year, day.month, day.day, hour);
      if (at.isAfter(t) && at.isBefore(limit)) {
        out.add(
          PlannedReminder(
            _id(o.id, -1),
            at,
            tr('Rechnung überfällig', 'Invoice overdue'),
            '${o.invoiceNumber} · ${s.client(o.clientId)?.displayName ?? o.title} · CHF ${Money.format(o.total)}',
          ),
        );
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.take(maxPlanned).toList();
  }

  static int _id(String key, int n) => (Object.hash(key, n) & 0x3fffffff);

  /// Alle Erinnerungen neu planen.
  static Future<void> reschedule(ContiState s) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!s.device.remindersOn) return;
      for (final r in plan(s)) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Erinnerungen planen');
    }
  }

  /// Gleich eine Mitteilung zeigen (z. B. Abo aufgebraucht).
  static Future<void> showNow(ContiState s, String title, String body) async {
    if (!_ready || !s.device.remindersOn) return;
    try {
      await _plugin.show(
        id: _id(title + body, DateTime.now().millisecond),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
      );
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Mitteilung zeigen');
    }
  }

  /// Mitteilung, wenn ein Abo mit der letzten Lektion aufgebraucht ist.
  static Future<void> subscriptionUsedUp(ContiState s, Order o) => showNow(
    s,
    tr('Abo aufgebraucht', 'Lesson pack used up'),
    tr(
      '${s.client(o.clientId)?.displayName ?? o.title}: alle ${o.lessonsTotal} Lektionen bezogen. Zeit für das nächste Abo?',
      '${s.client(o.clientId)?.displayName ?? o.title}: all ${o.lessonsTotal} lessons used. Time for the next pack?',
    ),
  );

  /// Für Anzeigen: wann die nächste Erinnerung kommt.
  static String describe(PlannedReminder r) =>
      '${Day.short(r.at)}, ${r.at.hour.toString().padLeft(2, '0')}:00 · ${r.title}';
}
