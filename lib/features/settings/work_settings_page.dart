import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/reminders.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/deadlines.dart';
import '../../core/model/crm.dart';
import '../../core/model/synced.dart';
import '../../widgets/visuals.dart';

/// Auftragsarten, Fristen-Ampel und Erinnerungen.
class WorkSettingsPage extends StatelessWidget {
  const WorkSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final b = s.business;
    final next = Reminders.plan(s).take(3).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Aufträge & Erinnerungen', 'Orders & reminders'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              SectionCard(
                title: tr('Auftragsarten', 'Order kinds'),
                trailing: TextButton.icon(onPressed: () => _editKind(context, null), icon: const Icon(Icons.add), label: Text(tr('Art', 'Kind'))),
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Column(
                  children: [
                    for (final k in s.orderKinds)
                      ListTile(
                        leading: Icon(k.subscription ? Icons.autorenew : Icons.work_outline, color: c.muted),
                        title: Text(k.name),
                        subtitle: k.subscription ? Text(tr('Abo mit ${k.lessons} Lektionen', 'Pack of ${k.lessons} lessons')) : null,
                        onTap: () => _editKind(context, k),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Fristen-Ampel', 'Deadline colours'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Ab wie vielen Tagen vor der Frist eine Aufgabe welche Farbe bekommt.', 'How many days before the deadline a task changes colour.'),
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 10),
                    for (final r in b.deadlineRules)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(width: 16, height: 16, decoration: BoxDecoration(color: parseHex(r.color), shape: BoxShape.circle)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_ruleName(r.id, r.label))),
                            IconButton(
                              onPressed: r.days <= 0 ? null : () => _setDays(s, r.id, r.days - 1),
                              icon: const Icon(Icons.remove),
                            ),
                            SizedBox(width: 70, child: Text(tr('${r.days} Tage', '${r.days} days'), textAlign: TextAlign.center)),
                            IconButton(onPressed: r.days >= 60 ? null : () => _setDays(s, r.id, r.days + 1), icon: const Icon(Icons.add)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Mitteilungen', 'Notifications'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!Reminders.supported)
                      Text(
                        tr('Auf diesem Gerät gibt es keine Mitteilungen. Die Ampel siehst du trotzdem.', 'Notifications are not available on this device. You still see the colours.'),
                        style: TextStyle(color: c.muted),
                      )
                    else ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Erinnerungen als Mitteilung', 'Reminders as notifications')),
                        subtitle: Text(
                          tr(
                            'Bei jeder Farbe der Ampel und am Tag der Frist, dazu wenn ein Abo aufgebraucht ist.',
                            'At each colour step and on the due day, and when a lesson pack is used up.',
                          ),
                        ),
                        value: s.device.remindersOn,
                        onChanged: (v) async {
                          await s.device.setReminders(on: v);
                          if (v) await Reminders.askPermission();
                          await Reminders.reschedule(s);
                          s.refresh();
                        },
                      ),
                      Row(
                        children: [
                          Expanded(child: Text(tr('Uhrzeit', 'Time of day'))),
                          DropdownButton<int>(
                            value: s.device.reminderHour,
                            items: [for (var h = 5; h <= 21; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                            onChanged: !s.device.remindersOn
                                ? null
                                : (h) async {
                                    await s.device.setReminders(hour: h);
                                    await Reminders.reschedule(s);
                                    s.refresh();
                                  },
                          ),
                        ],
                      ),
                      if (next.isNotEmpty && s.device.remindersOn) ...[
                        const SizedBox(height: 8),
                        CapsLabel(tr('Nächste Erinnerungen', 'Next reminders')),
                        const SizedBox(height: 6),
                        for (final r in next) Text('${Reminders.describe(r)} · ${r.body}', style: TextStyle(color: c.muted, fontSize: 13)),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ruleName(String id, String label) => switch (id) {
    'yellow' => tr('Gelb', 'Yellow'),
    'orange' => tr('Orange', 'Orange'),
    'red' => tr('Rot', 'Red'),
    _ => label,
  };

  Future<void> _setDays(ContiState s, String id, int days) async {
    final b = s.business.copy();
    for (final r in b.deadlineRules) {
      if (r.id == id) r.days = days;
    }
    await s.saveBusiness(b);
  }

  Future<void> _editKind(BuildContext context, OrderKind? kind) async {
    final s = ContiScope.read(context);
    final k = kind?.copy() ?? OrderKind(id: newId(), name: '', order: s.orderKinds.length);
    final name = TextEditingController(text: k.name);
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(kind == null ? tr('Neue Auftragsart', 'New order kind') : tr('Auftragsart', 'Order kind')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, autofocus: kind == null, decoration: InputDecoration(labelText: tr('Name', 'Name'), hintText: tr('z. B. Gig', 'e.g. Gig'))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Abo mit Lektionen', 'Lesson pack')),
                  subtitle: Text(tr('Conti zählt die bezogenen Lektionen.', 'Conti counts the lessons used.')),
                  value: k.subscription,
                  onChanged: (v) => setState(() => k.subscription = v),
                ),
                if (k.subscription)
                  Row(
                    children: [
                      Expanded(child: Text(tr('Lektionen pro Abo', 'Lessons per pack'))),
                      IconButton(onPressed: k.lessons <= 1 ? null : () => setState(() => k.lessons--), icon: const Icon(Icons.remove)),
                      SizedBox(width: 32, child: Text('${k.lessons}', textAlign: TextAlign.center)),
                      IconButton(onPressed: k.lessons >= 200 ? null : () => setState(() => k.lessons++), icon: const Icon(Icons.add)),
                    ],
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            if (kind != null)
              TextButton(
                onPressed: () async {
                  if (s.orderKindInUse(kind.id)) {
                    setState(() => error = tr('Diese Art wird noch von Aufträgen gebraucht.', 'Orders still use this kind.'));
                    return;
                  }
                  await s.saveOrderKind(kind.copy()..deleted = true);
                  if (context.mounted) Navigator.pop(context, false);
                },
                child: Text(tr('Löschen', 'Delete')),
              ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setState(() => error = tr('Bitte einen Namen eingeben.', 'Please enter a name.'));
                  return;
                }
                k.name = name.text.trim();
                Navigator.pop(context, true);
              },
              child: Text(tr('Sichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await s.saveOrderKind(k);
  }
}
