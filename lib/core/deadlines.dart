import 'package:flutter/material.dart';

import '../app/l10n.dart';
import 'dates.dart';
import 'model/business.dart';
import 'model/crm.dart';

/// Wie dringend eine Aufgabe ist (Fristen-Ampel).
class Urgency {
  const Urgency({this.color, required this.label, this.overdue = false, this.daysLeft});

  /// Farbe der Ampel (null = noch keine Farbe).
  final Color? color;
  final String label;
  final bool overdue;
  final int? daysLeft;

  /// Ampel für [t] nach den Regeln (z. B. gelb ab 7 Tagen, orange ab 4, rot ab 2).
  static Urgency of(Task t, List<DeadlineRule> rules, {DateTime? today}) {
    final due = t.due;
    if (t.done) return Urgency(label: tr('Erledigt', 'Done'));
    if (due == null) return Urgency(label: tr('Ohne Frist', 'No deadline'));
    final now = today ?? Day.today();
    final left = due.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (left < 0) {
      return Urgency(
        color: const Color(0xFFFF5A6E),
        overdue: true,
        daysLeft: left,
        label: tr('${-left} ${-left == 1 ? 'Tag' : 'Tage'} überfällig', '${-left} ${-left == 1 ? 'day' : 'days'} overdue'),
      );
    }
    final sorted = [...rules]..sort((a, b) => a.days.compareTo(b.days));
    Color? color;
    for (final r in sorted) {
      if (left <= r.days) {
        color = parseHex(r.color);
        break;
      }
    }
    final label = left == 0
        ? tr('Heute fällig', 'Due today')
        : left == 1
        ? tr('Morgen fällig', 'Due tomorrow')
        : tr('In $left Tagen', 'In $left days');
    return Urgency(color: color, label: label, daysLeft: left);
  }
}

/// „#ffcc44“ → Farbe.
Color parseHex(String hex, [Color fallback = const Color(0xFFFFC83D)]) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}
